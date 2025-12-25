/// Unit tests for NatsError
#[cfg(test)]
mod tests {
    use crate::nats::error::NatsError;

    #[test]
    fn test_connection_error() {
        let err = NatsError::ConnectionError("Failed to connect".to_string());
        assert_eq!(err.to_string(), "NATS connection error: Failed to connect");
        assert!(err.is_retriable());
        assert_eq!(err.category(), "connection");
    }

    #[test]
    fn test_jetstream_not_enabled() {
        let err = NatsError::JetStreamNotEnabled;
        assert_eq!(err.to_string(), "JetStream not enabled in configuration");
        assert!(!err.is_retriable());
        assert_eq!(err.category(), "configuration");
    }

    #[test]
    fn test_publish_error() {
        let err = NatsError::PublishError("Timeout".to_string());
        assert_eq!(err.to_string(), "Publish error: Timeout");
        assert!(err.is_retriable());
        assert_eq!(err.category(), "publish");
    }

    #[test]
    fn test_auth_error() {
        let err = NatsError::AuthError("Invalid credentials".to_string());
        assert_eq!(err.to_string(), "Authentication error: Invalid credentials");
        assert!(!err.is_retriable());
        assert_eq!(err.category(), "authentication");
    }

    #[test]
    fn test_config_error() {
        let err = NatsError::ConfigError("URL cannot be empty".to_string());
        assert_eq!(err.to_string(), "Configuration error: URL cannot be empty");
        assert!(!err.is_retriable());
        assert_eq!(err.category(), "configuration");
    }

    #[test]
    fn test_pool_error() {
        let err = NatsError::PoolError("Pool exhausted".to_string());
        assert_eq!(err.to_string(), "Pool error: Pool exhausted");
        assert!(!err.is_retriable());
        assert_eq!(err.category(), "pool");
    }

    #[test]
    fn test_timeout_error() {
        let err = NatsError::TimeoutError("Operation timed out after 5s".to_string());
        assert_eq!(
            err.to_string(),
            "Operation timeout: Operation timed out after 5s"
        );
        assert!(err.is_retriable());
        assert_eq!(err.category(), "timeout");
    }

    #[test]
    fn test_serialization_error() {
        let err = NatsError::SerializationError("Invalid JSON".to_string());
        assert_eq!(err.to_string(), "Serialization error: Invalid JSON");
        assert!(!err.is_retriable());
        assert_eq!(err.category(), "serialization");
    }

    #[test]
    fn test_io_error() {
        let err = NatsError::IoError("File not found".to_string());
        assert_eq!(err.to_string(), "I/O error: File not found");
        assert!(err.is_retriable());
        assert_eq!(err.category(), "io");
    }

    #[test]
    fn test_is_retriable_comprehensive() {
        // Retriable errors
        assert!(NatsError::ConnectionError("test".to_string()).is_retriable());
        assert!(NatsError::PublishError("test".to_string()).is_retriable());
        assert!(NatsError::TimeoutError("test".to_string()).is_retriable());
        assert!(NatsError::IoError("test".to_string()).is_retriable());

        // Non-retriable errors
        assert!(!NatsError::JetStreamNotEnabled.is_retriable());
        assert!(!NatsError::AuthError("test".to_string()).is_retriable());
        assert!(!NatsError::ConfigError("test".to_string()).is_retriable());
        assert!(!NatsError::PoolError("test".to_string()).is_retriable());
        assert!(!NatsError::SerializationError("test".to_string()).is_retriable());
    }

    #[test]
    fn test_error_display() {
        let err = NatsError::ConnectionError("test error".to_string());
        let display = format!("{}", err);
        assert!(display.contains("NATS connection error"));
        assert!(display.contains("test error"));
    }

    #[test]
    fn test_error_debug() {
        let err = NatsError::PublishError("debug test".to_string());
        let debug = format!("{:?}", err);
        assert!(debug.contains("PublishError"));
    }

    #[test]
    fn test_from_serde_json_error() {
        let json_err = serde_json::from_str::<serde_json::Value>("invalid json");
        assert!(json_err.is_err());

        let nats_err: NatsError = json_err.unwrap_err().into();
        match nats_err {
            NatsError::SerializationError(msg) => {
                assert!(msg.contains("expected"));
            }
            _ => panic!("Expected SerializationError"),
        }
    }

    #[test]
    fn test_from_io_error() {
        let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "file not found");
        let nats_err: NatsError = io_err.into();

        match nats_err {
            NatsError::IoError(msg) => {
                assert!(msg.contains("file not found"));
            }
            _ => panic!("Expected IoError"),
        }
    }

    #[test]
    fn test_error_chain() {
        // Simulate error chain
        let original = std::io::Error::new(std::io::ErrorKind::TimedOut, "connection timeout");
        let nats_err: NatsError = original.into();

        assert!(nats_err.is_retriable());
        assert!(nats_err.to_string().contains("timeout"));
    }

    #[test]
    fn test_multiple_error_conversions() {
        // Test that errors can be converted multiple times
        let json_str = r#"{"invalid": json}"#;
        let parse_result = serde_json::from_str::<serde_json::Value>(json_str);

        if let Err(e) = parse_result {
            let err1: NatsError = e.into();
            let err_str = err1.to_string();
            assert!(err_str.contains("Serialization error"));
        }
    }

    #[test]
    fn test_error_categorization() {
        // Network/connection errors - retriable
        let network_errors = vec![
            NatsError::ConnectionError("network unreachable".to_string()),
            NatsError::TimeoutError("timeout".to_string()),
            NatsError::IoError("io error".to_string()),
            NatsError::PublishError("publish failed".to_string()),
        ];

        for err in network_errors {
            assert!(
                err.is_retriable(),
                "Network error should be retriable: {}",
                err
            );
        }

        // Configuration/logic errors - not retriable
        let logic_errors = vec![
            NatsError::ConfigError("bad config".to_string()),
            NatsError::JetStreamNotEnabled,
            NatsError::SerializationError("bad format".to_string()),
            NatsError::AuthError("auth failed".to_string()),
            NatsError::PoolError("pool error".to_string()),
        ];

        for err in logic_errors {
            assert!(
                !err.is_retriable(),
                "Logic error should not be retriable: {}",
                err
            );
        }
    }

    #[test]
    fn test_all_error_categories() {
        assert_eq!(
            NatsError::ConnectionError("".to_string()).category(),
            "connection"
        );
        assert_eq!(NatsError::JetStreamNotEnabled.category(), "configuration");
        assert_eq!(
            NatsError::PublishError("".to_string()).category(),
            "publish"
        );
        assert_eq!(
            NatsError::AuthError("".to_string()).category(),
            "authentication"
        );
        assert_eq!(
            NatsError::ConfigError("".to_string()).category(),
            "configuration"
        );
        assert_eq!(NatsError::PoolError("".to_string()).category(), "pool");
        assert_eq!(
            NatsError::TimeoutError("".to_string()).category(),
            "timeout"
        );
        assert_eq!(
            NatsError::SerializationError("".to_string()).category(),
            "serialization"
        );
        assert_eq!(NatsError::IoError("".to_string()).category(), "io");
    }
}
