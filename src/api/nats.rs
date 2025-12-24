/// NATS API Functions (pgrx)
///
/// This module provides PostgreSQL-callable functions for NATS integration.
use pgrx::prelude::*;
use pgrx::JsonB;
use serde_json::json;
use std::collections::HashMap;
use std::sync::Mutex;

use crate::nats::{AuthType, NatsConfig, NatsPublisher};

// Global registry of NATS publishers
lazy_static::lazy_static! {
    static ref NATS_PUBLISHERS: Mutex<HashMap<String, NatsPublisher>> =
        Mutex::new(HashMap::new());
}

/// Initialize NATS connection pool from database configuration
///
/// This function loads NATS configuration from the rule_nats_config table
/// and creates a connection pool. Must be called before publishing.
///
/// # Arguments
/// * `config_name` - Name of the configuration (default: "default")
///
/// # Returns
/// JSON with success status and details
///
/// # Example
/// ```sql
/// SELECT rule_nats_init('default');
/// -- Returns: {"success": true, "config": "default", "message": "..."}
/// ```
#[pg_extern]
fn rule_nats_init(config_name: &str) -> Result<JsonB, Box<dyn std::error::Error>> {
    // Load configuration fields individually (pgrx doesn't support large tuples)
    let query = format!(
        "SELECT nats_url FROM rule_nats_config WHERE config_name = '{}' AND enabled = true",
        config_name
    );
    let nats_url =
        Spi::get_one::<String>(&query)?.ok_or("NATS configuration not found or disabled")?;

    let jetstream_enabled = Spi::get_one::<bool>(&format!(
        "SELECT jetstream_enabled FROM rule_nats_config WHERE config_name = '{}'",
        config_name
    ))?
    .unwrap_or(true);

    let stream_name = Spi::get_one::<String>(&format!(
        "SELECT stream_name FROM rule_nats_config WHERE config_name = '{}'",
        config_name
    ))?
    .unwrap_or("WEBHOOKS".to_string());

    let subject_prefix = Spi::get_one::<String>(&format!(
        "SELECT subject_prefix FROM rule_nats_config WHERE config_name = '{}'",
        config_name
    ))?
    .unwrap_or("webhooks".to_string());

    let max_connections = Spi::get_one::<i32>(&format!(
        "SELECT max_connections FROM rule_nats_config WHERE config_name = '{}'",
        config_name
    ))?
    .unwrap_or(10) as usize;

    let connection_timeout_ms = Spi::get_one::<i32>(&format!(
        "SELECT connection_timeout_ms FROM rule_nats_config WHERE config_name = '{}'",
        config_name
    ))?
    .unwrap_or(5000) as u64;

    // Build NATS configuration
    let config = NatsConfig {
        nats_url: nats_url.clone(),
        cluster_urls: None,
        auth_type: AuthType::None, // Simplified for initial version
        connection_timeout_ms,
        max_connections,
        jetstream_enabled,
        stream_name: stream_name.clone(),
        subject_prefix: subject_prefix.clone(),
        reconnect_delay_ms: 2000,
        max_reconnect_attempts: -1,
        tls_enabled: false,
        tls_cert_file: None,
        tls_key_file: None,
        tls_ca_file: None,
    };

    // Create publisher with tokio runtime
    let publisher = tokio::runtime::Runtime::new()?.block_on(NatsPublisher::new(config))?;

    // Store in global registry
    NATS_PUBLISHERS
        .lock()
        .map_err(|e| format!("Failed to lock publisher registry: {}", e))?
        .insert(config_name.to_string(), publisher);

    Ok(JsonB(json!({
        "success": true,
        "config": config_name,
        "message": format!("NATS connection initialized for config '{}'", config_name),
        "nats_url": nats_url,
        "jetstream_enabled": jetstream_enabled,
        "stream_name": stream_name
    })))
}

/// Publish a webhook event to NATS
///
/// # Arguments
/// * `webhook_id` - Webhook ID
/// * `payload` - JSON payload to publish
/// * `message_id` - Optional message ID for deduplication
///
/// # Returns
/// JSON with publish acknowledgment
///
/// # Example
/// ```sql
/// SELECT rule_webhook_publish_nats(1, '{"test": true}'::jsonb, 'msg-123');
/// ```
#[pg_extern]
fn rule_webhook_publish_nats(
    webhook_id: i32,
    payload: JsonB,
    message_id: Option<String>,
) -> Result<JsonB, Box<dyn std::error::Error>> {
    let start = std::time::Instant::now();

    // Get webhook configuration - load fields individually
    let webhook_name = Spi::get_one::<String>(&format!(
        "SELECT webhook_name FROM rule_webhooks WHERE webhook_id = {} AND nats_enabled = true",
        webhook_id
    ))?
    .ok_or("Webhook not found or NATS not enabled")?;

    let subject = Spi::get_one::<String>(&format!(
        "SELECT nats_subject FROM rule_webhooks WHERE webhook_id = {}",
        webhook_id
    ))?
    .ok_or("NATS subject not configured")?;

    let config_name = Spi::get_one::<String>(&format!(
        "SELECT c.config_name FROM rule_webhooks w \
         JOIN rule_nats_config c ON w.nats_config_id = c.config_id \
         WHERE w.webhook_id = {}",
        webhook_id
    ))?
    .unwrap_or("default".to_string());

    // Get publisher from registry
    let publishers = NATS_PUBLISHERS
        .lock()
        .map_err(|e| format!("Failed to lock publisher registry: {}", e))?;

    let publisher = publishers.get(&config_name).ok_or(format!(
        "NATS publisher not initialized for config '{}'. Call rule_nats_init() first",
        config_name
    ))?;

    // Serialize payload
    let payload_bytes = serde_json::to_vec(&payload.0)?;

    // Publish to NATS JetStream
    let ack = tokio::runtime::Runtime::new()?.block_on(async {
        if let Some(msg_id) = message_id.as_ref() {
            publisher
                .publish_jetstream_with_id(&subject, msg_id, &payload_bytes)
                .await
        } else {
            publisher.publish_jetstream(&subject, &payload_bytes).await
        }
    })?;

    let latency = start.elapsed().as_secs_f64() * 1000.0;

    // Log to history
    Spi::run(&format!(
        "INSERT INTO rule_nats_publish_history \
         (webhook_id, subject, payload, published_at, message_id, sequence_number, success, latency_ms) \
         VALUES ({}, '{}', '{}'::jsonb, NOW(), {}, {}, true, {})",
        webhook_id,
        subject,
        serde_json::to_string(&payload.0)?,
        message_id
            .as_ref()
            .map(|s| format!("'{}'", s))
            .unwrap_or("NULL".to_string()),
        ack.sequence,
        latency
    ))?;

    Ok(JsonB(json!({
        "success": true,
        "webhook_name": webhook_name,
        "subject": subject,
        "stream": ack.stream,
        "sequence": ack.sequence,
        "duplicate": ack.duplicate,
        "latency_ms": latency
    })))
}

/// Unified webhook call (supports both queue and NATS)
///
/// Routes webhook calls based on publish_mode configuration
///
/// # Arguments
/// * `webhook_id` - Webhook ID
/// * `payload` - JSON payload
///
/// # Returns
/// JSON with results from queue and/or NATS
///
/// # Example
/// ```sql
/// SELECT rule_webhook_call_unified(1, '{"test": true}'::jsonb);
/// ```
#[pg_extern]
fn rule_webhook_call_unified(
    webhook_id: i32,
    payload: JsonB,
) -> Result<JsonB, Box<dyn std::error::Error>> {
    // Get webhook configuration
    let publish_mode = Spi::get_one::<String>(&format!(
        "SELECT publish_mode FROM rule_webhooks WHERE webhook_id = {}",
        webhook_id
    ))?;

    let publish_mode = publish_mode.ok_or("Webhook not found")?;

    let mut results = json!({});

    // Handle based on publish_mode
    match publish_mode.as_str() {
        "queue" => {
            // Use existing PostgreSQL queue
            let result = Spi::get_one::<JsonB>(&format!(
                "SELECT rule_webhook_enqueue({}, '{}'::jsonb)",
                webhook_id,
                serde_json::to_string(&payload.0)?
            ))?;
            if let Some(r) = result {
                results["queue"] = r.0;
            }
        }
        "nats" => {
            // Publish to NATS only
            let result = rule_webhook_publish_nats(webhook_id, payload, None)?;
            results["nats"] = result.0;
        }
        "both" => {
            // Both queue and NATS
            let queue_result = Spi::get_one::<JsonB>(&format!(
                "SELECT rule_webhook_enqueue({}, '{}'::jsonb)",
                webhook_id,
                serde_json::to_string(&payload.0)?
            ))?;
            if let Some(r) = queue_result {
                results["queue"] = r.0;
            }

            let nats_result = rule_webhook_publish_nats(webhook_id, payload, None)?;
            results["nats"] = nats_result.0;
        }
        _ => return Err(format!("Invalid publish_mode: {}", publish_mode).into()),
    }

    Ok(JsonB(results))
}

/// Health check for NATS connection
///
/// # Arguments
/// * `config_name` - Configuration name
///
/// # Returns
/// JSON with connection status
///
/// # Example
/// ```sql
/// SELECT rule_nats_health_check('default');
/// ```
#[pg_extern]
fn rule_nats_health_check(config_name: &str) -> Result<JsonB, Box<dyn std::error::Error>> {
    let publishers = NATS_PUBLISHERS
        .lock()
        .map_err(|e| format!("Failed to lock publisher registry: {}", e))?;

    if let Some(publisher) = publishers.get(config_name) {
        let pool_stats = publisher.pool().pool_stats();

        Ok(JsonB(json!({
            "success": true,
            "config": config_name,
            "connected": true,
            "pool_stats": {
                "total_connections": pool_stats.total_connections,
                "healthy_connections": pool_stats.healthy_connections,
                "health_percentage": pool_stats.health_percentage(),
                "requests_served": pool_stats.requests_served
            },
            "jetstream_enabled": publisher.is_jetstream_enabled()
        })))
    } else {
        Ok(JsonB(json!({
            "success": false,
            "config": config_name,
            "connected": false,
            "message": "Publisher not initialized. Call rule_nats_init() first"
        })))
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn test_publisher_registry() {
        // Test that we can create and store publishers
        // Actual tests require running PostgreSQL and NATS
    }
}
