/// Unit tests for NatsConfig
#[cfg(test)]
mod tests {
    use crate::nats::{AuthType, NatsConfig};

    #[test]
    fn test_default_config() {
        let config = NatsConfig::default();

        assert_eq!(config.nats_url, "nats://localhost:4222");
        assert_eq!(config.max_connections, 10);
        assert!(config.jetstream_enabled);
        assert_eq!(config.stream_name, "WEBHOOKS");
        assert_eq!(config.subject_prefix, "webhooks");
        assert_eq!(config.connection_timeout_ms, 5000);
        assert_eq!(config.reconnect_delay_ms, 2000);
        assert_eq!(config.max_reconnect_attempts, -1);
    }

    #[test]
    fn test_config_builder() {
        let config = NatsConfig {
            nats_url: "nats://example.com:4222".to_string(),
            cluster_urls: Some(vec![
                "nats://node1:4222".to_string(),
                "nats://node2:4222".to_string(),
            ]),
            auth_type: AuthType::Token {
                token: "secret123".to_string(),
            },
            max_connections: 20,
            jetstream_enabled: false,
            stream_name: "CUSTOM_STREAM".to_string(),
            subject_prefix: "custom".to_string(),
            ..Default::default()
        };

        assert_eq!(config.nats_url, "nats://example.com:4222");
        assert_eq!(config.cluster_urls.as_ref().unwrap().len(), 2);
        assert_eq!(config.max_connections, 20);
        assert!(!config.jetstream_enabled);
        assert_eq!(config.stream_name, "CUSTOM_STREAM");

        match config.auth_type {
            AuthType::Token { token } => assert_eq!(token, "secret123"),
            _ => panic!("Expected Token auth type"),
        }
    }

    #[test]
    fn test_config_validation_valid_url() {
        let config = NatsConfig {
            nats_url: "nats://localhost:4222".to_string(),
            ..Default::default()
        };

        assert!(config.validate().is_ok());
    }

    #[test]
    fn test_config_validation_invalid_url() {
        let config = NatsConfig {
            nats_url: "".to_string(),
            ..Default::default()
        };

        assert!(config.validate().is_err());
        assert!(config.validate().unwrap_err().to_string().contains("empty"));
    }

    #[test]
    fn test_config_validation_invalid_timeout() {
        let config = NatsConfig {
            connection_timeout_ms: 0,
            ..Default::default()
        };

        assert!(config.validate().is_err());
    }

    #[test]
    fn test_config_validation_invalid_pool_size() {
        let config = NatsConfig {
            max_connections: 0,
            ..Default::default()
        };

        assert!(config.validate().is_err());
        assert!(config
            .validate()
            .unwrap_err()
            .to_string()
            .contains("greater than 0"));
    }

    #[test]
    fn test_config_validation_large_pool_size() {
        // Large pool sizes are allowed (no upper limit)
        let config = NatsConfig {
            max_connections: 1000,
            ..Default::default()
        };

        assert!(config.validate().is_ok());
    }

    #[test]
    fn test_auth_type_none() {
        let auth = AuthType::None;
        assert!(matches!(auth, AuthType::None));
    }

    #[test]
    fn test_auth_type_token() {
        let auth = AuthType::Token {
            token: "test_token".to_string(),
        };
        match auth {
            AuthType::Token { token } => assert_eq!(token, "test_token"),
            _ => panic!("Expected Token auth type"),
        }
    }

    #[test]
    fn test_auth_type_credentials() {
        let auth = AuthType::Credentials {
            path: "/path/to/creds.creds".to_string(),
        };
        match auth {
            AuthType::Credentials { path } => {
                assert_eq!(path, "/path/to/creds.creds");
            }
            _ => panic!("Expected Credentials auth type"),
        }
    }

    #[test]
    fn test_auth_type_nkey() {
        let auth = AuthType::NKey {
            seed: "seed_value".to_string(),
        };
        match auth {
            AuthType::NKey { seed } => assert_eq!(seed, "seed_value"),
            _ => panic!("Expected NKey auth type"),
        }
    }

    #[test]
    fn test_tls_config() {
        let config = NatsConfig {
            tls_enabled: true,
            tls_cert_file: Some("/path/to/cert.pem".to_string()),
            tls_key_file: Some("/path/to/key.pem".to_string()),
            tls_ca_file: Some("/path/to/ca.pem".to_string()),
            ..Default::default()
        };

        assert!(config.tls_enabled);
        assert_eq!(config.tls_cert_file.as_ref().unwrap(), "/path/to/cert.pem");
        assert_eq!(config.tls_key_file.as_ref().unwrap(), "/path/to/key.pem");
        assert_eq!(config.tls_ca_file.as_ref().unwrap(), "/path/to/ca.pem");
    }

    #[test]
    fn test_config_clone() {
        let config1 = NatsConfig {
            nats_url: "nats://test:4222".to_string(),
            max_connections: 5,
            ..Default::default()
        };

        let config2 = config1.clone();

        assert_eq!(config1.nats_url, config2.nats_url);
        assert_eq!(config1.max_connections, config2.max_connections);
    }

    #[test]
    fn test_config_debug_format() {
        let config = NatsConfig {
            nats_url: "nats://localhost:4222".to_string(),
            auth_type: AuthType::Token {
                token: "secret".to_string(),
            },
            ..Default::default()
        };

        let debug_str = format!("{:?}", config);
        assert!(debug_str.contains("nats://localhost:4222"));
        assert!(debug_str.contains("Token"));
    }

    #[test]
    fn test_reconnect_configuration() {
        let config = NatsConfig {
            reconnect_delay_ms: 3000,
            max_reconnect_attempts: 10,
            ..Default::default()
        };

        assert_eq!(config.reconnect_delay_ms, 3000);
        assert_eq!(config.max_reconnect_attempts, 10);
    }

    #[test]
    fn test_reconnect_infinite() {
        let config = NatsConfig {
            max_reconnect_attempts: -1,
            ..Default::default()
        };

        assert_eq!(config.max_reconnect_attempts, -1);
    }

    #[test]
    fn test_jetstream_config() {
        let config_enabled = NatsConfig {
            jetstream_enabled: true,
            stream_name: "MY_STREAM".to_string(),
            subject_prefix: "my.prefix".to_string(),
            ..Default::default()
        };

        assert!(config_enabled.jetstream_enabled);
        assert_eq!(config_enabled.stream_name, "MY_STREAM");
        assert_eq!(config_enabled.subject_prefix, "my.prefix");

        let config_disabled = NatsConfig {
            jetstream_enabled: false,
            ..Default::default()
        };

        assert!(!config_disabled.jetstream_enabled);
    }
}
