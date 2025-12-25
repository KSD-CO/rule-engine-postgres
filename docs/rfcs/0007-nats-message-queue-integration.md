# RFC-0007: NATS Message Queue Integration for Webhooks

- **Status:** Draft
- **Author:** Rule Engine Team
- **Created:** 2024-12-24
- **Updated:** 2024-12-24
- **Phase:** 4.5 (Enhanced Integration & Scalability)
- **Priority:** P1 - High
- **Depends On:** RFC-0005 (Webhook Support)

---

## Summary

Add NATS (Message Queue) integration to the webhook system, enabling event-driven architecture with pub/sub patterns, distributed processing, and horizontal scalability. This extends the current webhook implementation (RFC-0005) with asynchronous message queue capabilities using NATS/JetStream.

---

## Motivation

The current webhook implementation (v1.5.0) supports two processing modes:
1. **PostgreSQL HTTP Extension** - Synchronous, limited scalability
2. **PostgreSQL Table Queue + External Workers** - Polling-based, database overhead

Both approaches have limitations in distributed, high-throughput scenarios.

### Current Limitations

1. **Polling Overhead:** Workers must continuously poll PostgreSQL for pending webhooks
2. **Database Load:** Queue tables create unnecessary database I/O and connections
3. **Scalability Bottleneck:** Limited by database connection pool
4. **No Pub/Sub:** Cannot broadcast events to multiple subscribers
5. **Single Region:** Difficult to scale across multiple data centers
6. **Latency:** Polling introduces 1-5 second delays
7. **Resource Inefficient:** Workers idle most of the time between polls

### Use Cases

1. **Real-time Event Distribution:** Push webhook events to multiple consumers instantly
2. **Horizontal Scaling:** Add workers dynamically without database connection limits
3. **Multi-Region Deployment:** Process webhooks in different geographic regions
4. **Event Streaming:** Stream rule execution events to analytics systems
5. **Microservices Integration:** Decouple rule engine from webhook processing services
6. **Fan-out Patterns:** Send one event to multiple downstream services
7. **Event Replay:** Replay historical events for debugging or reprocessing

---

## Detailed Design

### Architecture Overview

```
PostgreSQL Rule Engine
       ↓ (publish event)
  NATS JetStream Server
       ↓ (subscribe)
  ┌────┴────┬────────┬────────┬────────┐
  ↓         ↓        ↓        ↓        ↓
Worker 1  Worker 2 Worker 3  Analytics  Audit
(HTTP)    (HTTP)   (HTTP)    Consumer   Logger
  ↓         ↓        ↓
External APIs/Webhooks
```

**Key Components:**
1. **NATS Client (Rust)** - Embedded in PostgreSQL extension via pgrx
2. **JetStream** - Persistent message streaming (retention, replay, acknowledgment)
3. **Queue Groups** - Load balancing across multiple workers
4. **Subjects** - Topic-based routing (e.g., `webhooks.slack`, `webhooks.email`)
5. **Workers** - External services that consume and process webhook events

### Database Schema

```sql
-- NATS Server Configuration
CREATE TABLE rule_nats_config (
    config_id SERIAL PRIMARY KEY,
    config_name TEXT NOT NULL UNIQUE DEFAULT 'default',

    -- Connection
    nats_url TEXT NOT NULL DEFAULT 'nats://localhost:4222',
    nats_cluster_urls TEXT[], -- For cluster setup

    -- Authentication
    auth_type TEXT DEFAULT 'none', -- 'none', 'token', 'credentials', 'nkey'
    auth_token TEXT,
    auth_credentials_file TEXT, -- Path to .creds file
    auth_nkey_seed TEXT,

    -- TLS
    tls_enabled BOOLEAN DEFAULT false,
    tls_cert_file TEXT,
    tls_key_file TEXT,
    tls_ca_file TEXT,

    -- Connection Pool
    max_connections INTEGER DEFAULT 10,
    connection_timeout_ms INTEGER DEFAULT 5000,
    reconnect_delay_ms INTEGER DEFAULT 2000,
    max_reconnect_attempts INTEGER DEFAULT -1, -- -1 = infinite

    -- JetStream
    jetstream_enabled BOOLEAN DEFAULT true,
    stream_name TEXT DEFAULT 'WEBHOOKS',
    subject_prefix TEXT DEFAULT 'webhooks',

    -- Status
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT valid_auth_type CHECK (auth_type IN ('none', 'token', 'credentials', 'nkey'))
);

-- Default configuration
INSERT INTO rule_nats_config (config_name, nats_url)
VALUES ('default', 'nats://localhost:4222')
ON CONFLICT (config_name) DO NOTHING;

-- NATS Stream Configuration (JetStream)
CREATE TABLE rule_nats_streams (
    stream_id SERIAL PRIMARY KEY,
    config_id INTEGER REFERENCES rule_nats_config(config_id) ON DELETE CASCADE,

    -- Stream Definition
    stream_name TEXT NOT NULL,
    subjects TEXT[] NOT NULL, -- e.g., ['webhooks.*', 'events.*']
    description TEXT,

    -- Storage
    storage_type TEXT DEFAULT 'file', -- 'memory', 'file'
    max_messages BIGINT DEFAULT 1000000,
    max_bytes BIGINT DEFAULT 1073741824, -- 1GB
    max_age_seconds BIGINT DEFAULT 604800, -- 7 days

    -- Retention Policy
    retention_policy TEXT DEFAULT 'limits', -- 'limits', 'interest', 'workqueue'
    discard_policy TEXT DEFAULT 'old', -- 'old', 'new'

    -- Replication (cluster)
    replicas INTEGER DEFAULT 1,

    -- Deduplication
    duplicate_window_seconds INTEGER DEFAULT 120,

    -- Status
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(config_id, stream_name),
    CONSTRAINT valid_storage CHECK (storage_type IN ('memory', 'file')),
    CONSTRAINT valid_retention CHECK (retention_policy IN ('limits', 'interest', 'workqueue')),
    CONSTRAINT valid_discard CHECK (discard_policy IN ('old', 'new'))
);

-- Extend rule_webhooks table to support NATS
ALTER TABLE rule_webhooks ADD COLUMN IF NOT EXISTS nats_enabled BOOLEAN DEFAULT false;
ALTER TABLE rule_webhooks ADD COLUMN IF NOT EXISTS nats_subject TEXT;
ALTER TABLE rule_webhooks ADD COLUMN IF NOT EXISTS nats_config_id INTEGER REFERENCES rule_nats_config(config_id);
ALTER TABLE rule_webhooks ADD COLUMN IF NOT EXISTS publish_mode TEXT DEFAULT 'queue';
-- 'queue' (PostgreSQL queue only), 'nats' (NATS only), 'both' (queue + NATS)

-- NATS Publishing History
CREATE TABLE rule_nats_publish_history (
    publish_id BIGSERIAL PRIMARY KEY,
    webhook_id INTEGER REFERENCES rule_webhooks(webhook_id) ON DELETE CASCADE,

    -- NATS Message
    subject TEXT NOT NULL,
    payload JSONB NOT NULL,
    headers JSONB,

    -- Publishing
    published_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    message_id TEXT, -- NATS message ID for deduplication
    sequence_number BIGINT, -- JetStream sequence number

    -- Status
    success BOOLEAN NOT NULL,
    error_message TEXT,
    latency_ms NUMERIC(10,2),

    -- Context
    triggered_by TEXT,
    rule_execution_id BIGINT,

    -- Cleanup
    expires_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP + INTERVAL '7 days'
);

CREATE INDEX idx_nats_publish_webhook ON rule_nats_publish_history(webhook_id);
CREATE INDEX idx_nats_publish_time ON rule_nats_publish_history(published_at DESC);
CREATE INDEX idx_nats_publish_subject ON rule_nats_publish_history(subject);
CREATE INDEX idx_nats_publish_expires ON rule_nats_publish_history(expires_at);

-- NATS Consumer Statistics (for monitoring external workers)
CREATE TABLE rule_nats_consumer_stats (
    consumer_id SERIAL PRIMARY KEY,
    stream_name TEXT NOT NULL,
    consumer_name TEXT NOT NULL,

    -- Consumer Info
    queue_group TEXT, -- For load balancing
    ack_policy TEXT, -- 'none', 'all', 'explicit'
    max_deliver INTEGER,

    -- Statistics (updated by workers or admin queries)
    messages_delivered BIGINT DEFAULT 0,
    messages_acknowledged BIGINT DEFAULT 0,
    messages_pending BIGINT DEFAULT 0,
    messages_redelivered BIGINT DEFAULT 0,

    -- Performance
    avg_processing_time_ms NUMERIC(10,2),
    last_active_at TIMESTAMPTZ,

    -- Status
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(stream_name, consumer_name)
);
```

### Rust Implementation

#### NATS Client Module (`src/nats/mod.rs`)

```rust
use async_nats::{Client, ConnectOptions};
use async_nats::jetstream::{self, Context as JetStreamContext};
use std::time::Duration;
use serde::{Deserialize, Serialize};

pub mod client;
pub mod config;
pub mod publisher;
pub mod stream;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NatsConfig {
    pub nats_url: String,
    pub cluster_urls: Option<Vec<String>>,
    pub auth_type: AuthType,
    pub tls_enabled: bool,
    pub max_connections: usize,
    pub connection_timeout_ms: u64,
    pub jetstream_enabled: bool,
    pub stream_name: String,
    pub subject_prefix: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AuthType {
    None,
    Token(String),
    Credentials(String), // Path to .creds file
    NKey(String),
}

/// NATS Connection Pool
pub struct NatsPool {
    clients: Vec<Client>,
    current_index: std::sync::atomic::AtomicUsize,
    config: NatsConfig,
}

impl NatsPool {
    pub async fn new(config: NatsConfig) -> Result<Self, NatsError> {
        let mut clients = Vec::with_capacity(config.max_connections);

        for _ in 0..config.max_connections {
            let client = Self::create_client(&config).await?;
            clients.push(client);
        }

        Ok(Self {
            clients,
            current_index: std::sync::atomic::AtomicUsize::new(0),
            config,
        })
    }

    async fn create_client(config: &NatsConfig) -> Result<Client, NatsError> {
        let mut options = ConnectOptions::new()
            .connection_timeout(Duration::from_millis(config.connection_timeout_ms));

        // Authentication
        options = match &config.auth_type {
            AuthType::None => options,
            AuthType::Token(token) => options.token(token.clone()),
            AuthType::Credentials(path) => options.credentials_file(path).await?,
            AuthType::NKey(seed) => options.nkey(seed.clone()),
        };

        // TLS
        if config.tls_enabled {
            // Add TLS configuration
            options = options.require_tls(true);
        }

        // Connect
        let client = options.connect(&config.nats_url).await?;

        Ok(client)
    }

    /// Get next available client (round-robin)
    pub fn get_client(&self) -> &Client {
        let index = self.current_index.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
                    % self.clients.len();
        &self.clients[index]
    }
}

/// NATS Publisher
pub struct NatsPublisher {
    pool: NatsPool,
    jetstream: Option<JetStreamContext>,
}

impl NatsPublisher {
    pub async fn new(config: NatsConfig) -> Result<Self, NatsError> {
        let pool = NatsPool::new(config.clone()).await?;

        let jetstream = if config.jetstream_enabled {
            let client = pool.get_client();
            Some(jetstream::new(client.clone()))
        } else {
            None
        };

        Ok(Self { pool, jetstream })
    }

    /// Publish message to NATS (core NATS - fire and forget)
    pub async fn publish(&self, subject: &str, payload: &[u8]) -> Result<(), NatsError> {
        let client = self.pool.get_client();
        client.publish(subject, payload.into()).await?;
        Ok(())
    }

    /// Publish message with headers
    pub async fn publish_with_headers(
        &self,
        subject: &str,
        headers: async_nats::HeaderMap,
        payload: &[u8]
    ) -> Result<(), NatsError> {
        let client = self.pool.get_client();
        client.publish_with_headers(subject, headers, payload.into()).await?;
        Ok(())
    }

    /// Publish to JetStream (persistent, acknowledged)
    pub async fn publish_jetstream(
        &self,
        subject: &str,
        payload: &[u8]
    ) -> Result<JetStreamPublishAck, NatsError> {
        let js = self.jetstream.as_ref()
            .ok_or(NatsError::JetStreamNotEnabled)?;

        let ack = js.publish(subject, payload.into()).await?;

        Ok(JetStreamPublishAck {
            stream: ack.stream,
            sequence: ack.sequence,
        })
    }

    /// Publish with deduplication (using message ID)
    pub async fn publish_jetstream_with_id(
        &self,
        subject: &str,
        message_id: &str,
        payload: &[u8]
    ) -> Result<JetStreamPublishAck, NatsError> {
        let js = self.jetstream.as_ref()
            .ok_or(NatsError::JetStreamNotEnabled)?;

        let ack = js.publish_with_headers(
            subject,
            async_nats::HeaderMap::from_iter(vec![
                ("Nats-Msg-Id".to_string(), message_id.to_string())
            ]),
            payload.into()
        ).await?;

        Ok(JetStreamPublishAck {
            stream: ack.stream,
            sequence: ack.sequence,
        })
    }
}

#[derive(Debug, Clone)]
pub struct JetStreamPublishAck {
    pub stream: String,
    pub sequence: u64,
}

#[derive(Debug, thiserror::Error)]
pub enum NatsError {
    #[error("NATS connection error: {0}")]
    ConnectionError(String),

    #[error("JetStream not enabled")]
    JetStreamNotEnabled,

    #[error("Publish error: {0}")]
    PublishError(String),

    #[error("Authentication error: {0}")]
    AuthError(String),
}

impl From<async_nats::Error> for NatsError {
    fn from(err: async_nats::Error) -> Self {
        NatsError::ConnectionError(err.to_string())
    }
}
```

#### PostgreSQL API Functions (`src/api/nats.rs`)

```rust
use pgrx::prelude::*;
use serde_json::json;

/// Initialize NATS connection pool
#[pg_extern]
fn rule_nats_init(
    config_name: &str,
) -> Result<JsonB, Box<dyn std::error::Error>> {
    // Load config from rule_nats_config table
    let config = load_nats_config(config_name)?;

    // Create NATS publisher (async runtime in pgrx)
    let publisher = tokio::runtime::Runtime::new()?
        .block_on(NatsPublisher::new(config))?;

    // Store in global state (thread-safe)
    NATS_PUBLISHERS.lock()?.insert(config_name.to_string(), publisher);

    Ok(JsonB(json!({
        "success": true,
        "config": config_name,
        "message": "NATS connection initialized"
    })))
}

/// Publish webhook event to NATS
#[pg_extern]
fn rule_webhook_publish_nats(
    webhook_id: i32,
    payload: JsonB,
    message_id: Option<String>,
) -> Result<JsonB, Box<dyn std::error::Error>> {
    let start = std::time::Instant::now();

    // Get webhook config
    let webhook = Spi::get_one::<WebhookRow>(&format!(
        "SELECT * FROM rule_webhooks WHERE webhook_id = {} AND nats_enabled = true",
        webhook_id
    ))?;

    let webhook = webhook.ok_or("Webhook not found or NATS not enabled")?;

    // Get NATS publisher
    let publishers = NATS_PUBLISHERS.lock()?;
    let config_name = webhook.nats_config_name.unwrap_or("default".to_string());
    let publisher = publishers.get(&config_name)
        .ok_or("NATS publisher not initialized")?;

    // Build subject
    let subject = webhook.nats_subject.clone()
        .unwrap_or(format!("webhooks.{}", webhook.webhook_name));

    // Serialize payload
    let payload_bytes = serde_json::to_vec(&payload.0)?;

    // Publish to NATS JetStream
    let ack = tokio::runtime::Runtime::new()?
        .block_on(async {
            if let Some(msg_id) = message_id {
                publisher.publish_jetstream_with_id(&subject, &msg_id, &payload_bytes).await
            } else {
                publisher.publish_jetstream(&subject, &payload_bytes).await
            }
        })?;

    let latency = start.elapsed().as_secs_f64() * 1000.0;

    // Log to history
    Spi::run(&format!(
        "INSERT INTO rule_nats_publish_history
        (webhook_id, subject, payload, published_at, message_id, sequence_number, success, latency_ms)
        VALUES ({}, '{}', '{}', NOW(), {}, {}, true, {})",
        webhook_id,
        subject,
        serde_json::to_string(&payload.0)?,
        message_id.map(|s| format!("'{}'", s)).unwrap_or("NULL".to_string()),
        ack.sequence,
        latency
    ))?;

    Ok(JsonB(json!({
        "success": true,
        "subject": subject,
        "stream": ack.stream,
        "sequence": ack.sequence,
        "latency_ms": latency
    })))
}

/// Unified webhook call (supports both queue and NATS)
#[pg_extern]
fn rule_webhook_call_unified(
    webhook_id: i32,
    payload: JsonB,
) -> Result<JsonB, Box<dyn std::error::Error>> {
    // Get webhook config
    let webhook = Spi::get_one::<WebhookRow>(&format!(
        "SELECT * FROM rule_webhooks WHERE webhook_id = {}",
        webhook_id
    ))?;

    let webhook = webhook.ok_or("Webhook not found")?;

    let mut results = json!({});

    // Handle based on publish_mode
    match webhook.publish_mode.as_str() {
        "queue" => {
            // Use existing PostgreSQL queue
            let result = Spi::get_one::<JsonB>(&format!(
                "SELECT rule_webhook_enqueue({}, '{}')",
                webhook_id,
                serde_json::to_string(&payload.0)?
            ))?;
            results["queue"] = result.unwrap().0;
        },
        "nats" => {
            // Publish to NATS only
            let result = rule_webhook_publish_nats(webhook_id, payload, None)?;
            results["nats"] = result.0;
        },
        "both" => {
            // Both queue and NATS
            let queue_result = Spi::get_one::<JsonB>(&format!(
                "SELECT rule_webhook_enqueue({}, '{}')",
                webhook_id,
                serde_json::to_string(&payload.0)?
            ))?;
            results["queue"] = queue_result.unwrap().0;

            let nats_result = rule_webhook_publish_nats(webhook_id, payload, None)?;
            results["nats"] = nats_result.0;
        },
        _ => return Err("Invalid publish_mode".into()),
    }

    Ok(JsonB(results))
}
```

### SQL API Functions

```sql
-- Configure NATS connection
CREATE OR REPLACE FUNCTION rule_nats_configure(
    p_config_name TEXT DEFAULT 'default',
    p_nats_url TEXT DEFAULT 'nats://localhost:4222',
    p_auth_type TEXT DEFAULT 'none',
    p_jetstream_enabled BOOLEAN DEFAULT true
) RETURNS BOOLEAN AS $$
BEGIN
    INSERT INTO rule_nats_config (config_name, nats_url, auth_type, jetstream_enabled)
    VALUES (p_config_name, p_nats_url, p_auth_type, p_jetstream_enabled)
    ON CONFLICT (config_name)
    DO UPDATE SET
        nats_url = EXCLUDED.nats_url,
        auth_type = EXCLUDED.auth_type,
        jetstream_enabled = EXCLUDED.jetstream_enabled,
        updated_at = CURRENT_TIMESTAMP;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Create JetStream stream
CREATE OR REPLACE FUNCTION rule_nats_stream_create(
    p_stream_name TEXT,
    p_subjects TEXT[],
    p_config_name TEXT DEFAULT 'default',
    p_retention_policy TEXT DEFAULT 'limits',
    p_max_age_seconds BIGINT DEFAULT 604800
) RETURNS INTEGER AS $$
DECLARE
    v_config_id INTEGER;
    v_stream_id INTEGER;
BEGIN
    -- Get config ID
    SELECT config_id INTO v_config_id
    FROM rule_nats_config
    WHERE config_name = p_config_name;

    IF v_config_id IS NULL THEN
        RAISE EXCEPTION 'NATS config % not found', p_config_name;
    END IF;

    -- Create stream definition
    INSERT INTO rule_nats_streams (
        config_id, stream_name, subjects, retention_policy, max_age_seconds
    ) VALUES (
        v_config_id, p_stream_name, p_subjects, p_retention_policy, p_max_age_seconds
    )
    RETURNING stream_id INTO v_stream_id;

    RETURN v_stream_id;
END;
$$ LANGUAGE plpgsql;

-- Enable NATS for a webhook
CREATE OR REPLACE FUNCTION rule_webhook_enable_nats(
    p_webhook_id INTEGER,
    p_nats_subject TEXT DEFAULT NULL,
    p_publish_mode TEXT DEFAULT 'both',
    p_config_name TEXT DEFAULT 'default'
) RETURNS BOOLEAN AS $$
DECLARE
    v_config_id INTEGER;
    v_webhook_name TEXT;
    v_subject TEXT;
BEGIN
    -- Get config ID
    SELECT config_id INTO v_config_id
    FROM rule_nats_config
    WHERE config_name = p_config_name;

    IF v_config_id IS NULL THEN
        RAISE EXCEPTION 'NATS config % not found', p_config_name;
    END IF;

    -- Get webhook name for default subject
    SELECT webhook_name INTO v_webhook_name
    FROM rule_webhooks
    WHERE webhook_id = p_webhook_id;

    IF v_webhook_name IS NULL THEN
        RAISE EXCEPTION 'Webhook % not found', p_webhook_id;
    END IF;

    -- Default subject: webhooks.<webhook_name>
    v_subject := COALESCE(p_nats_subject, 'webhooks.' || v_webhook_name);

    -- Enable NATS
    UPDATE rule_webhooks
    SET nats_enabled = true,
        nats_subject = v_subject,
        nats_config_id = v_config_id,
        publish_mode = p_publish_mode
    WHERE webhook_id = p_webhook_id;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Get NATS statistics
CREATE OR REPLACE FUNCTION rule_nats_stats(
    p_webhook_id INTEGER DEFAULT NULL,
    p_hours INTEGER DEFAULT 24
) RETURNS JSON AS $$
DECLARE
    v_stats JSON;
BEGIN
    SELECT json_build_object(
        'total_published', COUNT(*),
        'successful', COUNT(*) FILTER (WHERE success = true),
        'failed', COUNT(*) FILTER (WHERE success = false),
        'success_rate_pct', ROUND(
            100.0 * COUNT(*) FILTER (WHERE success = true) / NULLIF(COUNT(*), 0),
            2
        ),
        'avg_latency_ms', ROUND(AVG(latency_ms), 2),
        'min_latency_ms', MIN(latency_ms),
        'max_latency_ms', MAX(latency_ms),
        'p50_latency_ms', PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY latency_ms),
        'p95_latency_ms', PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY latency_ms),
        'p99_latency_ms', PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY latency_ms),
        'unique_subjects', COUNT(DISTINCT subject),
        'time_range_hours', p_hours
    ) INTO v_stats
    FROM rule_nats_publish_history
    WHERE (p_webhook_id IS NULL OR webhook_id = p_webhook_id)
      AND published_at >= NOW() - (p_hours || ' hours')::INTERVAL;

    RETURN v_stats;
END;
$$ LANGUAGE plpgsql;
```

### Views for Monitoring

```sql
-- NATS Publish Summary
CREATE OR REPLACE VIEW nats_publish_summary AS
SELECT
    w.webhook_id,
    w.webhook_name,
    w.nats_subject as subject,
    w.publish_mode,
    COUNT(h.publish_id) as total_published,
    COUNT(*) FILTER (WHERE h.success = true) as successful,
    COUNT(*) FILTER (WHERE h.success = false) as failed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE h.success = true) / NULLIF(COUNT(*), 0), 2) as success_rate_pct,
    ROUND(AVG(h.latency_ms), 2) as avg_latency_ms,
    MAX(h.published_at) as last_published_at
FROM rule_webhooks w
LEFT JOIN rule_nats_publish_history h ON w.webhook_id = h.webhook_id
WHERE w.nats_enabled = true
GROUP BY w.webhook_id, w.webhook_name, w.nats_subject, w.publish_mode;

-- NATS Recent Failures
CREATE OR REPLACE VIEW nats_recent_failures AS
SELECT
    h.publish_id,
    w.webhook_name,
    h.subject,
    h.error_message,
    h.payload,
    h.published_at
FROM rule_nats_publish_history h
JOIN rule_webhooks w ON h.webhook_id = w.webhook_id
WHERE h.success = false
  AND h.published_at >= NOW() - INTERVAL '24 hours'
ORDER BY h.published_at DESC
LIMIT 100;

-- NATS Performance Stats
CREATE OR REPLACE VIEW nats_performance_stats AS
SELECT
    w.webhook_name,
    h.subject,
    COUNT(*) as message_count,
    ROUND(AVG(h.latency_ms), 2) as avg_latency_ms,
    MIN(h.latency_ms) as min_latency_ms,
    MAX(h.latency_ms) as max_latency_ms,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY h.latency_ms) as p50_latency_ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY h.latency_ms) as p95_latency_ms,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY h.latency_ms) as p99_latency_ms
FROM rule_nats_publish_history h
JOIN rule_webhooks w ON h.webhook_id = w.webhook_id
WHERE h.success = true
  AND h.published_at >= NOW() - INTERVAL '24 hours'
GROUP BY w.webhook_name, h.subject;
```

---

## Examples

### Example 1: Basic NATS Setup

```sql
-- 1. Configure NATS connection
SELECT rule_nats_configure(
    'default',
    'nats://nats-server:4222',
    'none',
    true -- Enable JetStream
);

-- 2. Initialize NATS connection pool (Rust function)
SELECT rule_nats_init('default');

-- 3. Create JetStream stream
SELECT rule_nats_stream_create(
    'WEBHOOKS',
    ARRAY['webhooks.*', 'events.*'],
    'default',
    'limits',
    604800 -- 7 days retention
);

-- 4. Register webhook with NATS enabled
SELECT rule_webhook_register(
    'slack_alerts',
    'https://hooks.slack.com/services/XXX',
    'POST',
    '{"Content-Type": "application/json"}'::JSONB
);

-- 5. Enable NATS for webhook
SELECT rule_webhook_enable_nats(
    1, -- webhook_id
    'webhooks.slack', -- subject
    'nats', -- publish to NATS only
    'default'
);

-- 6. Publish event
SELECT rule_webhook_call_unified(
    1,
    '{"text": "Alert: System error detected!"}'::JSONB
);
```

### Example 2: Fan-out Pattern (Multiple Consumers)

```sql
-- Setup: One webhook publishes to NATS subject
-- Multiple workers subscribe to same subject with different queue groups

-- Enable NATS for webhook
SELECT rule_webhook_enable_nats(
    1, -- webhook_id
    'events.order.created', -- subject
    'nats'
);

-- Publish event (will be received by ALL subscribers)
SELECT rule_webhook_call_unified(
    1,
    '{
        "order_id": 12345,
        "customer_id": 678,
        "amount": 999.99
    }'::JSONB
);

-- External workers:
-- Worker 1 (Email Service): nats sub -s nats://server:4222 events.order.created
-- Worker 2 (Analytics): nats sub -s nats://server:4222 events.order.created
-- Worker 3 (Audit Log): nats sub -s nats://server:4222 events.order.created
```

### Example 3: Load Balancing with Queue Groups

```sql
-- External workers join same queue group for load balancing
-- Only ONE worker in the group receives each message

-- Worker 1: nats sub -s nats://server:4222 --queue=webhook-workers events.order.*
-- Worker 2: nats sub -s nats://server:4222 --queue=webhook-workers events.order.*
-- Worker 3: nats sub -s nats://server:4222 --queue=webhook-workers events.order.*

-- Publish 100 events - distributed across 3 workers
DO $$
BEGIN
    FOR i IN 1..100 LOOP
        PERFORM rule_webhook_call_unified(
            1,
            jsonb_build_object('order_id', i, 'amount', i * 10)
        );
    END LOOP;
END $$;
```

### Example 4: Hybrid Mode (Queue + NATS)

```sql
-- Use BOTH PostgreSQL queue AND NATS for redundancy
SELECT rule_webhook_enable_nats(
    1,
    'webhooks.critical',
    'both' -- Queue + NATS
);

-- This will:
-- 1. Enqueue to rule_webhook_calls (for PG-based workers)
-- 2. Publish to NATS (for NATS-based workers)
SELECT rule_webhook_call_unified(
    1,
    '{"critical": true, "message": "Payment failed"}'::JSONB
);
```

### Example 5: Monitoring and Stats

```sql
-- View NATS publish summary
SELECT * FROM nats_publish_summary;

-- Recent failures
SELECT * FROM nats_recent_failures;

-- Performance stats
SELECT * FROM nats_performance_stats;

-- Detailed stats for specific webhook
SELECT rule_nats_stats(1, 24); -- Last 24 hours

-- Overall stats
SELECT rule_nats_stats(NULL, 168); -- Last 7 days, all webhooks
```

---

## External Worker Implementation

### Node.js NATS Worker Example

```javascript
const { connect, StringCodec } = require('nats');
const axios = require('axios');

async function startWorker() {
  // Connect to NATS
  const nc = await connect({
    servers: 'nats://localhost:4222',
  });

  const sc = StringCodec();
  const js = nc.jetstream();

  // Create durable consumer (survives restarts)
  const consumer = await js.consumers.get('WEBHOOKS', 'webhook-worker-1');

  console.log('Worker started, listening for webhook events...');

  // Subscribe to webhooks.* subject with queue group
  const subscription = await consumer.consume({
    callback: async (msg) => {
      const startTime = Date.now();

      try {
        // Parse payload
        const payload = JSON.parse(sc.decode(msg.data));
        const subject = msg.subject;

        console.log(`Processing: ${subject}`, payload);

        // Extract webhook config from subject or payload
        // In real implementation, fetch webhook URL from cache or database

        // Make HTTP request
        const response = await axios.post(
          payload.webhook_url,
          payload.data,
          {
            headers: payload.headers || {},
            timeout: 5000
          }
        );

        console.log(`Success: ${subject} - Status ${response.status}`);

        // Acknowledge message (removes from queue)
        msg.ack();

        const duration = Date.now() - startTime;
        console.log(`Processed in ${duration}ms`);

      } catch (error) {
        console.error(`Error processing message:`, error.message);

        // Negative acknowledge (requeue for retry)
        // JetStream will redeliver based on consumer config
        msg.nak();
      }
    },
  });

  // Graceful shutdown
  process.on('SIGINT', async () => {
    console.log('Shutting down...');
    await subscription.close();
    await nc.close();
    process.exit(0);
  });
}

startWorker().catch(console.error);
```

### Go NATS Worker Example

```go
package main

import (
    "context"
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "time"

    "github.com/nats-io/nats.go"
)

type WebhookPayload struct {
    WebhookURL string                 `json:"webhook_url"`
    Data       map[string]interface{} `json:"data"`
    Headers    map[string]string      `json:"headers"`
}

func main() {
    // Connect to NATS
    nc, err := nats.Connect("nats://localhost:4222")
    if err != nil {
        log.Fatal(err)
    }
    defer nc.Close()

    // Get JetStream context
    js, err := nc.JetStream()
    if err != nil {
        log.Fatal(err)
    }

    // Create durable consumer
    sub, err := js.QueueSubscribe(
        "webhooks.*",
        "webhook-workers", // Queue group
        processMessage,
        nats.Durable("webhook-worker"),
        nats.ManualAck(),
        nats.MaxDeliver(3), // Max 3 delivery attempts
        nats.AckWait(30*time.Second),
    )
    if err != nil {
        log.Fatal(err)
    }
    defer sub.Unsubscribe()

    log.Println("Worker started, listening for webhook events...")

    // Keep running
    select {}
}

func processMessage(msg *nats.Msg) {
    startTime := time.Now()

    // Parse payload
    var payload WebhookPayload
    if err := json.Unmarshal(msg.Data, &payload); err != nil {
        log.Printf("Error parsing payload: %v", err)
        msg.Nak() // Requeue
        return
    }

    log.Printf("Processing: %s", msg.Subject)

    // Make HTTP request
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    body, _ := json.Marshal(payload.Data)
    req, _ := http.NewRequestWithContext(ctx, "POST", payload.WebhookURL, bytes.NewBuffer(body))

    for k, v := range payload.Headers {
        req.Header.Set(k, v)
    }

    client := &http.Client{}
    resp, err := client.Do(req)
    if err != nil {
        log.Printf("Error making request: %v", err)
        msg.Nak() // Requeue for retry
        return
    }
    defer resp.Body.Close()

    if resp.StatusCode >= 200 && resp.StatusCode < 300 {
        log.Printf("Success: %s - Status %d", msg.Subject, resp.StatusCode)
        msg.Ack() // Success
    } else {
        log.Printf("Failed: %s - Status %d", msg.Subject, resp.StatusCode)
        msg.Nak() // Requeue
    }

    duration := time.Since(startTime)
    log.Printf("Processed in %v", duration)
}
```

---

## Performance Considerations

### Throughput

| Metric | PostgreSQL Queue | NATS Core | NATS JetStream |
|--------|-----------------|-----------|----------------|
| **Messages/sec** | ~1,000 | ~1,000,000 | ~100,000 |
| **Latency (p50)** | 10-50ms (polling) | <1ms | 1-5ms |
| **Latency (p99)** | 100-500ms | <5ms | 10-20ms |
| **Max Throughput** | ~10K/sec | >1M/sec | ~500K/sec |

### Resource Usage

- **Memory:** ~10MB per NATS connection, ~100MB for JetStream
- **CPU:** Minimal (<1% idle, 5-10% at 100K msg/sec)
- **Network:** ~1KB per message + overhead
- **Disk (JetStream):** Depends on retention policy

### Scalability

- **Horizontal Scaling:** Add workers without database connections
- **Multi-Region:** Deploy NATS clusters across regions
- **Load Balancing:** Queue groups distribute work automatically
- **Backpressure:** JetStream handles slow consumers gracefully

---

## Security Considerations

### Connection Security

- **TLS/SSL:** Enforce encrypted connections
- **Authentication:** Token, credentials file, or NKey
- **Authorization:** Subject-level permissions
- **Network Isolation:** NATS in private network

### Message Security

- **Encryption:** Optional message-level encryption
- **Deduplication:** Message ID prevents duplicates
- **Audit Trail:** Complete publish history
- **Access Control:** Limit who can publish/subscribe

### Best Practices

```sql
-- Use TLS in production
UPDATE rule_nats_config
SET tls_enabled = true,
    tls_cert_file = '/path/to/client-cert.pem',
    tls_key_file = '/path/to/client-key.pem',
    tls_ca_file = '/path/to/ca.pem'
WHERE config_name = 'default';

-- Use authentication
UPDATE rule_nats_config
SET auth_type = 'credentials',
    auth_credentials_file = '/path/to/nats.creds'
WHERE config_name = 'default';

-- Restrict access to sensitive functions
REVOKE EXECUTE ON FUNCTION rule_nats_configure FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rule_nats_configure TO admin_role;
```

---

## Migration Path

### Phase 1: Add NATS Support (Backward Compatible)

```sql
-- Run migration
\i migrations/007_nats_integration.sql

-- No breaking changes - existing webhooks continue to work
SELECT * FROM rule_webhooks; -- All existing webhooks have nats_enabled = false
```

### Phase 2: Opt-in NATS

```sql
-- Gradually enable NATS for webhooks
SELECT rule_webhook_enable_nats(1, NULL, 'both'); -- Hybrid mode
SELECT rule_webhook_enable_nats(2, NULL, 'both');

-- Test with both modes for safety
-- Monitor: SELECT * FROM nats_publish_summary;
```

### Phase 3: Full NATS Migration

```sql
-- Switch to NATS-only after validation
UPDATE rule_webhooks
SET publish_mode = 'nats'
WHERE nats_enabled = true AND publish_mode = 'both';

-- Cleanup old queue entries (optional)
DELETE FROM rule_webhook_calls WHERE status = 'completed' AND completed_at < NOW() - INTERVAL '7 days';
```

---

## Alternatives Considered

### Alternative 1: RabbitMQ

**Pros:**
- Mature, enterprise-ready
- Rich feature set (exchanges, routing)
- Management UI

**Cons:**
- Heavier resource usage
- More complex setup
- Slower than NATS (10x)

**Why Rejected:** NATS is simpler, faster, and better suited for high-throughput event streaming.

### Alternative 2: Apache Kafka

**Pros:**
- Excellent for event streaming
- Strong ordering guarantees
- Large ecosystem

**Cons:**
- Very heavy (requires JVM, Zookeeper)
- Overkill for webhooks
- Complex operations

**Why Rejected:** Too complex for this use case. NATS JetStream provides similar features with much simpler operations.

### Alternative 3: Redis Streams

**Pros:**
- Simple, fast
- In-memory performance
- Many users already have Redis

**Cons:**
- No native clustering (requires Redis Enterprise)
- Less mature than NATS for messaging
- Limited persistence options

**Why Rejected:** NATS provides better clustering, persistence, and messaging primitives out of the box.

---

## Drawbacks and Risks

### Technical Risks

1. **NATS Server Dependency**
   - **Risk:** Single point of failure
   - **Mitigation:** Deploy NATS cluster (3+ nodes), use JetStream replication

2. **Async Rust in pgrx**
   - **Risk:** Tokio runtime overhead in PostgreSQL
   - **Mitigation:** Connection pooling, reuse runtime across calls

3. **Message Loss**
   - **Risk:** Messages lost if NATS down
   - **Mitigation:** JetStream persistence, hybrid mode fallback to PG queue

### Maintenance Burden

- Additional service to manage (NATS server)
- Need to monitor NATS cluster health
- Workers need to handle JetStream consumer management

### Breaking Changes

- **None** - This is purely additive
- Existing webhooks continue to work with PostgreSQL queue
- NATS is opt-in per webhook

---

## Dependencies

### External Dependencies

- **Rust Crates:**
  - `async-nats = "0.33"` - NATS client
  - `tokio = { version = "1.35", features = ["rt-multi-thread"] }` - Async runtime
  - `serde = { version = "1.0", features = ["derive"] }`
  - `serde_json = "1.0"`

- **NATS Server:**
  - NATS Server 2.10+ (supports JetStream)
  - Deployment: Docker, Kubernetes, or binary

### Internal Dependencies

- **Depends On:** RFC-0005 (Webhook Support) must be implemented first
- **Integrates With:** Rule execution, triggers, external data sources

---

## Testing Strategy

### Unit Tests

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_nats_connection() {
        let config = NatsConfig {
            nats_url: "nats://localhost:4222".to_string(),
            ..Default::default()
        };

        let pool = NatsPool::new(config).await.unwrap();
        assert_eq!(pool.clients.len(), 10);
    }

    #[tokio::test]
    async fn test_publish_jetstream() {
        let publisher = create_test_publisher().await;
        let ack = publisher.publish_jetstream("test.subject", b"payload").await.unwrap();

        assert!(ack.sequence > 0);
        assert_eq!(ack.stream, "WEBHOOKS");
    }

    #[tokio::test]
    async fn test_deduplication() {
        let publisher = create_test_publisher().await;

        // Publish same message twice with same ID
        let msg_id = "msg-12345";
        let ack1 = publisher.publish_jetstream_with_id("test", msg_id, b"data").await.unwrap();
        let ack2 = publisher.publish_jetstream_with_id("test", msg_id, b"data").await.unwrap();

        // Second publish should be deduplicated (same sequence)
        assert_eq!(ack1.sequence, ack2.sequence);
    }
}
```

### Integration Tests

```sql
-- Test NATS configuration
BEGIN;
SELECT plan(5);

-- Test: Create NATS config
SELECT ok(
    rule_nats_configure('test', 'nats://localhost:4222', 'none', true),
    'Should create NATS config'
);

-- Test: Enable NATS for webhook
SELECT ok(
    rule_webhook_enable_nats(1, 'test.subject', 'nats', 'test'),
    'Should enable NATS for webhook'
);

-- Test: Publish to NATS
SELECT ok(
    (rule_webhook_call_unified(1, '{"test": true}'::jsonb)->>'success')::boolean,
    'Should publish to NATS successfully'
);

-- Test: Verify history
SELECT ok(
    EXISTS(SELECT 1 FROM rule_nats_publish_history WHERE webhook_id = 1),
    'Should record publish in history'
);

-- Test: Get stats
SELECT ok(
    (rule_nats_stats(1, 1)->>'total_published')::int > 0,
    'Should return stats'
);

SELECT * FROM finish();
ROLLBACK;
```

### Performance Tests

```sql
-- Load test: Publish 10,000 messages
DO $$
DECLARE
    v_start TIMESTAMP;
    v_end TIMESTAMP;
    v_duration NUMERIC;
BEGIN
    v_start := clock_timestamp();

    FOR i IN 1..10000 LOOP
        PERFORM rule_webhook_call_unified(
            1,
            jsonb_build_object('id', i, 'data', 'test')
        );
    END LOOP;

    v_end := clock_timestamp();
    v_duration := EXTRACT(EPOCH FROM (v_end - v_start));

    RAISE NOTICE 'Published 10,000 messages in % seconds (% msg/sec)',
        v_duration,
        ROUND(10000 / v_duration);
END $$;

-- Expected: >1,000 msg/sec with NATS
```

### Worker Tests

```bash
# Test worker with NATS CLI
# Terminal 1: Start worker
node worker.js

# Terminal 2: Publish test messages
nats pub webhooks.test '{"test": "message 1"}'
nats pub webhooks.test '{"test": "message 2"}'

# Terminal 3: Monitor stream
nats stream info WEBHOOKS
nats consumer info WEBHOOKS webhook-worker-1
```

---

## Documentation Plan

- [x] RFC document (this file)
- [ ] User guide: [NATS_INTEGRATION.md](../NATS_INTEGRATION.md)
  - Setup instructions
  - Configuration examples
  - Worker implementation guide
  - Monitoring and troubleshooting
- [ ] API reference (auto-generated from SQL functions)
- [ ] Migration guide from PostgreSQL queue to NATS
- [ ] Performance tuning guide
- [ ] FAQ section
- [ ] Video tutorial (optional)

---

## Rollout Plan

### Phase 1: Experimental (v1.6.0-alpha)

- **Timeline:** Week 1-2
- **Scope:**
  - Basic NATS publish functionality
  - Simple worker examples
  - Limited to test environments
- **Feature Flag:** `nats.enabled = false` by default
- **Deliverables:**
  - Rust implementation
  - Basic SQL functions
  - Example Node.js worker

### Phase 2: Beta (v1.6.0-beta)

- **Timeline:** Week 3-4
- **Scope:**
  - JetStream integration
  - Full API surface
  - Performance optimization
  - Documentation complete
- **Feature Flag:** `nats.enabled = true` opt-in
- **Deliverables:**
  - Complete test coverage
  - Performance benchmarks
  - Multiple worker examples (Node.js, Go, Python)
  - Migration guide

### Phase 3: GA (v1.6.0)

- **Timeline:** Week 5-6
- **Scope:**
  - Production ready
  - Monitoring and observability
  - Enterprise features (TLS, auth)
- **Deliverables:**
  - Full documentation
  - Production deployment guide
  - Case studies
  - Support for NATS clusters

---

## Success Metrics

### Adoption
- **Target:** 30% of webhook users adopt NATS within 3 months
- **Measurement:** Count of webhooks with `nats_enabled = true`

### Performance
- **Target:**
  - P50 publish latency < 5ms
  - P99 publish latency < 20ms
  - Throughput > 10,000 msg/sec per instance
- **Measurement:** `nats_performance_stats` view

### Reliability
- **Target:** 99.9% publish success rate
- **Measurement:** `nats_publish_summary` view

### Scalability
- **Target:** Support 100+ concurrent workers without database bottleneck
- **Measurement:** Monitor database connections, NATS consumer count

### Community
- **Target:**
  - 5+ worker implementations in different languages
  - Positive feedback on GitHub
  - 10+ production deployments
- **Measurement:** GitHub issues, discussions, testimonials

---

## Open Questions

- [ ] Should we support NATS KV (Key-Value) store for webhook configuration caching?
- [ ] Should we provide built-in monitoring dashboard (Grafana integration)?
- [ ] Should we support multi-tenancy with separate NATS accounts per customer?
- [ ] Should we provide automatic NATS cluster setup scripts (Terraform, Helm)?
- [ ] Should webhook workers be part of this extension or separate repository?
- [ ] Should we support NATS Object Store for large payloads (>1MB)?

---

## References

- [NATS Documentation](https://docs.nats.io/)
- [NATS JetStream](https://docs.nats.io/nats-concepts/jetstream)
- [async-nats Rust Crate](https://docs.rs/async-nats/)
- [RFC-0005: Webhook Support](0005-webhook-support.md)
- [NATS vs Kafka vs RabbitMQ Comparison](https://docs.nats.io/nats-concepts/overview/compare-nats)
- [NATS Cluster Setup](https://docs.nats.io/running-a-nats-service/configuration/clustering)
- [PostgreSQL pgrx Async Guide](https://github.com/tcdi/pgrx)

---

## Changelog

- **2024-12-24:** Initial draft
