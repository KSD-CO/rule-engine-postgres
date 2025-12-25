use crate::nats::error::NatsError;
/// NATS configuration types
///
/// This module defines configuration structures for NATS connections.
use serde::{Deserialize, Serialize};

/// Authentication type for NATS connection
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum AuthType {
    /// No authentication
    #[default]
    None,

    /// Token-based authentication
    Token { token: String },

    /// Credentials file authentication (.creds file)
    Credentials { path: String },

    /// NKey authentication
    NKey { seed: String },
}

/// NATS connection configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NatsConfig {
    /// Primary NATS server URL (e.g., "nats://localhost:4222")
    pub nats_url: String,

    /// Optional cluster URLs for failover
    #[serde(default)]
    pub cluster_urls: Option<Vec<String>>,

    /// Authentication configuration
    #[serde(default)]
    pub auth_type: AuthType,

    /// Connection timeout in milliseconds
    #[serde(default = "default_connection_timeout")]
    pub connection_timeout_ms: u64,

    /// Maximum number of connections in the pool
    #[serde(default = "default_max_connections")]
    pub max_connections: usize,

    /// Enable JetStream features
    #[serde(default = "default_true")]
    pub jetstream_enabled: bool,

    /// JetStream stream name
    #[serde(default = "default_stream_name")]
    pub stream_name: String,

    /// Subject prefix for all messages
    #[serde(default = "default_subject_prefix")]
    pub subject_prefix: String,

    /// Reconnect delay in milliseconds
    #[serde(default = "default_reconnect_delay")]
    pub reconnect_delay_ms: u64,

    /// Maximum reconnect attempts (-1 for infinite)
    #[serde(default = "default_max_reconnect_attempts")]
    pub max_reconnect_attempts: i32,

    /// Enable TLS
    #[serde(default)]
    pub tls_enabled: bool,

    /// TLS certificate file path (optional)
    #[serde(default)]
    pub tls_cert_file: Option<String>,

    /// TLS key file path (optional)
    #[serde(default)]
    pub tls_key_file: Option<String>,

    /// TLS CA file path (optional)
    #[serde(default)]
    pub tls_ca_file: Option<String>,
}

// Default value functions
fn default_connection_timeout() -> u64 {
    5000
}
fn default_max_connections() -> usize {
    10
}
fn default_true() -> bool {
    true
}
fn default_stream_name() -> String {
    "WEBHOOKS".to_string()
}
fn default_subject_prefix() -> String {
    "webhooks".to_string()
}
fn default_reconnect_delay() -> u64 {
    2000
}
fn default_max_reconnect_attempts() -> i32 {
    -1
}

impl Default for NatsConfig {
    fn default() -> Self {
        Self {
            nats_url: "nats://localhost:4222".to_string(),
            cluster_urls: None,
            auth_type: AuthType::None,
            connection_timeout_ms: default_connection_timeout(),
            max_connections: default_max_connections(),
            jetstream_enabled: true,
            stream_name: default_stream_name(),
            subject_prefix: default_subject_prefix(),
            reconnect_delay_ms: default_reconnect_delay(),
            max_reconnect_attempts: default_max_reconnect_attempts(),
            tls_enabled: false,
            tls_cert_file: None,
            tls_key_file: None,
            tls_ca_file: None,
        }
    }
}

impl NatsConfig {
    /// Create a new configuration with minimal settings
    pub fn new(nats_url: impl Into<String>) -> Self {
        Self {
            nats_url: nats_url.into(),
            ..Default::default()
        }
    }

    /// Enable JetStream with custom stream name
    pub fn with_jetstream(mut self, stream_name: impl Into<String>) -> Self {
        self.jetstream_enabled = true;
        self.stream_name = stream_name.into();
        self
    }

    /// Set authentication
    pub fn with_auth(mut self, auth_type: AuthType) -> Self {
        self.auth_type = auth_type;
        self
    }

    /// Set connection pool size
    pub fn with_pool_size(mut self, size: usize) -> Self {
        self.max_connections = size;
        self
    }

    /// Enable TLS
    pub fn with_tls(
        mut self,
        cert_file: Option<String>,
        key_file: Option<String>,
        ca_file: Option<String>,
    ) -> Self {
        self.tls_enabled = true;
        self.tls_cert_file = cert_file;
        self.tls_key_file = key_file;
        self.tls_ca_file = ca_file;
        self
    }

    /// Validate configuration
    pub fn validate(&self) -> Result<(), NatsError> {
        // Validate URL format
        if self.nats_url.is_empty() {
            return Err(NatsError::ConfigError(
                "NATS URL cannot be empty".to_string(),
            ));
        }

        if !self.nats_url.starts_with("nats://") && !self.nats_url.starts_with("tls://") {
            return Err(NatsError::ConfigError(
                "NATS URL must start with nats:// or tls://".to_string(),
            ));
        }

        // Validate connection timeout
        if self.connection_timeout_ms == 0 {
            return Err(NatsError::ConfigError(
                "Connection timeout must be greater than 0".to_string(),
            ));
        }

        // Validate pool size
        if self.max_connections == 0 {
            return Err(NatsError::ConfigError(
                "Max connections must be greater than 0".to_string(),
            ));
        }

        // Validate stream name if JetStream is enabled
        if self.jetstream_enabled && self.stream_name.is_empty() {
            return Err(NatsError::ConfigError(
                "Stream name cannot be empty when JetStream is enabled".to_string(),
            ));
        }

        // Validate TLS configuration
        if self.tls_enabled {
            if let AuthType::Credentials { path } = &self.auth_type {
                // Credentials file should exist (we'll check later)
                if path.is_empty() {
                    return Err(NatsError::ConfigError(
                        "Credentials file path cannot be empty".to_string(),
                    ));
                }
            }
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = NatsConfig::default();
        assert_eq!(config.nats_url, "nats://localhost:4222");
        assert_eq!(config.max_connections, 10);
        assert!(config.jetstream_enabled);
        assert_eq!(config.stream_name, "WEBHOOKS");
        assert_eq!(config.subject_prefix, "webhooks");
    }

    #[test]
    fn test_builder_pattern() {
        let config = NatsConfig::new("nats://example.com:4222")
            .with_jetstream("MY_STREAM")
            .with_pool_size(20)
            .with_auth(AuthType::Token {
                token: "secret".to_string(),
            });

        assert_eq!(config.nats_url, "nats://example.com:4222");
        assert_eq!(config.stream_name, "MY_STREAM");
        assert_eq!(config.max_connections, 20);
        assert!(matches!(config.auth_type, AuthType::Token { .. }));
    }

    #[test]
    fn test_validation_success() {
        let config = NatsConfig::default();
        assert!(config.validate().is_ok());
    }

    #[test]
    fn test_validation_empty_url() {
        let config = NatsConfig {
            nats_url: "".to_string(),
            ..Default::default()
        };
        assert!(config.validate().is_err());
    }

    #[test]
    fn test_validation_invalid_url_scheme() {
        let config = NatsConfig {
            nats_url: "http://localhost:4222".to_string(),
            ..Default::default()
        };
        assert!(config.validate().is_err());
    }

    #[test]
    fn test_validation_zero_timeout() {
        let config = NatsConfig {
            connection_timeout_ms: 0,
            ..Default::default()
        };
        assert!(config.validate().is_err());
    }

    #[test]
    fn test_validation_zero_connections() {
        let config = NatsConfig {
            max_connections: 0,
            ..Default::default()
        };
        assert!(config.validate().is_err());
    }

    #[test]
    fn test_validation_empty_stream_name() {
        let config = NatsConfig {
            stream_name: "".to_string(),
            ..Default::default()
        };
        assert!(config.validate().is_err());
    }

    #[test]
    fn test_auth_type_serialization() {
        let auth = AuthType::Token {
            token: "secret".to_string(),
        };
        let json = serde_json::to_string(&auth).unwrap();
        let deserialized: AuthType = serde_json::from_str(&json).unwrap();
        assert_eq!(auth, deserialized);
    }

    #[test]
    fn test_config_serialization() {
        let config = NatsConfig::default();
        let json = serde_json::to_string(&config).unwrap();
        let deserialized: NatsConfig = serde_json::from_str(&json).unwrap();
        assert_eq!(config.nats_url, deserialized.nats_url);
        assert_eq!(config.stream_name, deserialized.stream_name);
    }
}
