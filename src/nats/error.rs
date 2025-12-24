/// NATS integration error types
///
/// This module defines all error types that can occur during NATS operations.
use thiserror::Error;

/// Main error type for NATS operations
#[derive(Debug, Error)]
pub enum NatsError {
    /// Connection errors (network, authentication, etc.)
    #[error("NATS connection error: {0}")]
    ConnectionError(String),

    /// JetStream feature is not enabled
    #[error("JetStream not enabled in configuration")]
    JetStreamNotEnabled,

    /// Publishing errors
    #[error("Publish error: {0}")]
    PublishError(String),

    /// Authentication errors
    #[error("Authentication error: {0}")]
    AuthError(String),

    /// Configuration errors
    #[error("Configuration error: {0}")]
    ConfigError(String),

    /// Connection pool errors
    #[error("Pool error: {0}")]
    PoolError(String),

    /// Timeout errors
    #[error("Operation timeout: {0}")]
    TimeoutError(String),

    /// Serialization/deserialization errors
    #[error("Serialization error: {0}")]
    SerializationError(String),

    /// Generic I/O errors
    #[error("I/O error: {0}")]
    IoError(String),
}

impl NatsError {
    /// Check if the error is retriable
    ///
    /// Returns true for transient errors that might succeed on retry
    pub fn is_retriable(&self) -> bool {
        matches!(
            self,
            Self::ConnectionError(_)
                | Self::PublishError(_)
                | Self::TimeoutError(_)
                | Self::IoError(_)
        )
    }

    /// Get error category for logging/monitoring
    pub fn category(&self) -> &'static str {
        match self {
            Self::ConnectionError(_) => "connection",
            Self::JetStreamNotEnabled => "configuration",
            Self::PublishError(_) => "publish",
            Self::AuthError(_) => "authentication",
            Self::ConfigError(_) => "configuration",
            Self::PoolError(_) => "pool",
            Self::TimeoutError(_) => "timeout",
            Self::SerializationError(_) => "serialization",
            Self::IoError(_) => "io",
        }
    }
}

/// Convert async-nats errors to NatsError
impl From<async_nats::Error> for NatsError {
    fn from(err: async_nats::Error) -> Self {
        NatsError::ConnectionError(err.to_string())
    }
}

/// Convert serde_json errors to NatsError
impl From<serde_json::Error> for NatsError {
    fn from(err: serde_json::Error) -> Self {
        NatsError::SerializationError(err.to_string())
    }
}

/// Convert std::io errors to NatsError
impl From<std::io::Error> for NatsError {
    fn from(err: std::io::Error) -> Self {
        NatsError::IoError(err.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_retriability() {
        assert!(NatsError::ConnectionError("test".to_string()).is_retriable());
        assert!(NatsError::PublishError("test".to_string()).is_retriable());
        assert!(NatsError::TimeoutError("test".to_string()).is_retriable());
        assert!(!NatsError::JetStreamNotEnabled.is_retriable());
        assert!(!NatsError::ConfigError("test".to_string()).is_retriable());
    }

    #[test]
    fn test_error_categories() {
        assert_eq!(
            NatsError::ConnectionError("test".to_string()).category(),
            "connection"
        );
        assert_eq!(
            NatsError::PublishError("test".to_string()).category(),
            "publish"
        );
        assert_eq!(NatsError::JetStreamNotEnabled.category(), "configuration");
    }

    #[test]
    fn test_error_display() {
        let err = NatsError::ConnectionError("network timeout".to_string());
        assert_eq!(err.to_string(), "NATS connection error: network timeout");
    }
}
