/// NATS Integration Tests
///
/// This module contains unit tests for NATS functionality.
/// Integration tests that require a running NATS server are in the tests/ directory.
pub mod config_tests;
pub mod error_tests;
pub mod pool_tests;

#[cfg(test)]
mod common {
    use crate::nats::{AuthType, NatsConfig};

    /// Create a default test configuration
    pub fn default_test_config() -> NatsConfig {
        NatsConfig {
            nats_url: "nats://localhost:4222".to_string(),
            cluster_urls: None,
            auth_type: AuthType::None,
            connection_timeout_ms: 5000,
            max_connections: 3,
            jetstream_enabled: true,
            stream_name: "TEST_WEBHOOKS".to_string(),
            subject_prefix: "test.webhooks".to_string(),
            reconnect_delay_ms: 1000,
            max_reconnect_attempts: -1,
            tls_enabled: false,
            tls_cert_file: None,
            tls_key_file: None,
            tls_ca_file: None,
        }
    }

    /// Create configuration with custom values
    pub fn custom_config(url: &str, max_connections: usize, jetstream: bool) -> NatsConfig {
        NatsConfig {
            nats_url: url.to_string(),
            max_connections,
            jetstream_enabled: jetstream,
            ..default_test_config()
        }
    }
}
