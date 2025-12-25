/// NATS client creation and management
///
/// This module handles creating and configuring NATS clients.
use async_nats::{Client, ConnectOptions};
use std::time::Duration;

use crate::nats::config::{AuthType, NatsConfig};
use crate::nats::error::NatsError;

/// Create a NATS client from configuration
pub async fn create_client(config: &NatsConfig) -> Result<Client, NatsError> {
    // Validate configuration first
    config.validate()?;

    // Create connection options
    let reconnect_delay = config.reconnect_delay_ms;
    let mut options = ConnectOptions::new()
        .connection_timeout(Duration::from_millis(config.connection_timeout_ms))
        .reconnect_delay_callback(move |_| Duration::from_millis(reconnect_delay));

    // Note: max_reconnects configuration handled by default async-nats behavior
    // The library will reconnect indefinitely by default

    // Apply authentication
    options = apply_auth(options, &config.auth_type).await?;

    // Apply TLS if enabled
    if config.tls_enabled {
        options = apply_tls(options, config)?;
    }

    // Set custom name for connection
    options = options.name("rule-engine-nats");

    // Connect to NATS server
    let client = options
        .connect(config.nats_url.as_str())
        .await
        .map_err(|e| {
            NatsError::ConnectionError(format!("Failed to connect to {}: {}", config.nats_url, e))
        })?;

    Ok(client)
}

/// Apply authentication to connection options
async fn apply_auth(
    options: ConnectOptions,
    auth_type: &AuthType,
) -> Result<ConnectOptions, NatsError> {
    let options = match auth_type {
        AuthType::None => options,

        AuthType::Token { token } => options.token(token.clone()),

        AuthType::Credentials { path } => {
            // Load credentials from file
            options.credentials_file(path).await.map_err(|e| {
                NatsError::AuthError(format!("Failed to load credentials from {}: {}", path, e))
            })?
        }

        AuthType::NKey { seed } => {
            // Use NKey authentication
            options.nkey(seed.clone())
        }
    };

    Ok(options)
}

/// Apply TLS configuration
fn apply_tls(options: ConnectOptions, _config: &NatsConfig) -> Result<ConnectOptions, NatsError> {
    // Enable TLS
    let options = options.require_tls(true);

    // Note: Certificate configuration in async-nats v0.33 requires different approach
    // For now, we'll use system certificates
    // TODO: Add custom certificate support in future versions

    Ok(options)
}

/// Create a client with retry logic
pub async fn create_client_with_retry(
    config: &NatsConfig,
    max_retries: usize,
) -> Result<Client, NatsError> {
    let mut last_error = None;

    for attempt in 0..=max_retries {
        match create_client(config).await {
            Ok(client) => return Ok(client),
            Err(e) => {
                if !e.is_retriable() {
                    // Non-retriable error, fail immediately
                    return Err(e);
                }

                last_error = Some(e);

                if attempt < max_retries {
                    // Wait before retry (exponential backoff)
                    let delay = Duration::from_millis(
                        config.reconnect_delay_ms * 2_u64.pow(attempt as u32),
                    );
                    tokio::time::sleep(delay).await;
                }
            }
        }
    }

    Err(last_error
        .unwrap_or_else(|| NatsError::ConnectionError("Max retries exceeded".to_string())))
}

/// Check if a client is connected
pub fn check_connection(client: &Client) -> bool {
    client.connection_state() == async_nats::connection::State::Connected
}

/// Get connection statistics
pub fn get_connection_stats(client: &Client) -> ConnectionStats {
    ConnectionStats {
        is_connected: check_connection(client),
        server_info: client.server_info().clone(),
    }
}

/// Connection statistics
#[derive(Debug, Clone)]
pub struct ConnectionStats {
    /// Whether the client is currently connected
    pub is_connected: bool,

    /// Server information
    pub server_info: async_nats::ServerInfo,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_auth_type_none() {
        let config = NatsConfig::default();
        assert!(matches!(config.auth_type, AuthType::None));
    }

    #[test]
    fn test_config_validation() {
        let config = NatsConfig::default();
        assert!(config.validate().is_ok());

        let bad_config = NatsConfig {
            nats_url: "".to_string(),
            ..Default::default()
        };
        assert!(bad_config.validate().is_err());
    }

    // Note: Actual connection tests require a running NATS server
    // Those would be integration tests, not unit tests
}
