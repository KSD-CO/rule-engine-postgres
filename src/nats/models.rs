/// NATS data models
///
/// This module defines data structures for NATS operations.
use serde::{Deserialize, Serialize};

/// JetStream publish acknowledgment
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JetStreamAck {
    /// Stream name where message was published
    pub stream: String,

    /// Sequence number assigned to the message
    pub sequence: u64,

    /// Whether this was a duplicate message (deduplicated)
    #[serde(default)]
    pub duplicate: bool,
}

impl JetStreamAck {
    /// Create a new acknowledgment
    pub fn new(stream: impl Into<String>, sequence: u64) -> Self {
        Self {
            stream: stream.into(),
            sequence,
            duplicate: false,
        }
    }

    /// Mark as duplicate
    pub fn with_duplicate(mut self, duplicate: bool) -> Self {
        self.duplicate = duplicate;
        self
    }
}

/// Connection pool statistics
#[derive(Debug, Clone, Serialize, Deserialize, Default, PartialEq)]
pub struct PoolStats {
    /// Total number of connections in the pool
    pub total_connections: usize,

    /// Number of healthy (connected) connections
    pub healthy_connections: usize,

    /// Number of requests served
    pub requests_served: u64,

    /// Current request being processed
    pub active_requests: usize,
}

impl PoolStats {
    /// Create empty stats
    pub fn new(total_connections: usize) -> Self {
        Self {
            total_connections,
            healthy_connections: 0,
            requests_served: 0,
            active_requests: 0,
        }
    }

    /// Calculate health percentage
    pub fn health_percentage(&self) -> f64 {
        if self.total_connections == 0 {
            0.0
        } else {
            (self.healthy_connections as f64 / self.total_connections as f64) * 100.0
        }
    }

    /// Check if pool is healthy (at least 50% connections available)
    pub fn is_healthy(&self) -> bool {
        self.health_percentage() >= 50.0
    }
}

/// NATS message with metadata
#[derive(Debug, Clone)]
pub struct NatsMessage {
    /// Subject the message was published to
    pub subject: String,

    /// Message payload
    pub payload: Vec<u8>,

    /// Optional message ID for deduplication
    pub message_id: Option<String>,

    /// Optional headers
    pub headers: Option<async_nats::HeaderMap>,
}

impl NatsMessage {
    /// Create a new message
    pub fn new(subject: impl Into<String>, payload: Vec<u8>) -> Self {
        Self {
            subject: subject.into(),
            payload,
            message_id: None,
            headers: None,
        }
    }

    /// Set message ID for deduplication
    pub fn with_id(mut self, id: impl Into<String>) -> Self {
        self.message_id = Some(id.into());
        self
    }

    /// Add headers
    pub fn with_headers(mut self, headers: async_nats::HeaderMap) -> Self {
        self.headers = Some(headers);
        self
    }

    /// Get payload as UTF-8 string
    pub fn payload_as_string(&self) -> Result<String, std::string::FromUtf8Error> {
        String::from_utf8(self.payload.clone())
    }

    /// Get payload as JSON
    pub fn payload_as_json<T: for<'de> Deserialize<'de>>(&self) -> Result<T, serde_json::Error> {
        serde_json::from_slice(&self.payload)
    }
}

/// Stream configuration for JetStream
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamConfig {
    /// Stream name
    pub name: String,

    /// Subjects this stream listens to
    pub subjects: Vec<String>,

    /// Optional description
    #[serde(default)]
    pub description: Option<String>,

    /// Storage type (memory or file)
    #[serde(default = "default_storage_type")]
    pub storage_type: StorageType,

    /// Maximum number of messages
    #[serde(default = "default_max_messages")]
    pub max_messages: i64,

    /// Maximum bytes
    #[serde(default = "default_max_bytes")]
    pub max_bytes: i64,

    /// Maximum age in seconds
    #[serde(default = "default_max_age_seconds")]
    pub max_age_seconds: i64,

    /// Retention policy
    #[serde(default)]
    pub retention_policy: RetentionPolicy,

    /// Discard policy
    #[serde(default)]
    pub discard_policy: DiscardPolicy,

    /// Number of replicas
    #[serde(default = "default_replicas")]
    pub replicas: usize,

    /// Duplicate window in seconds
    #[serde(default = "default_duplicate_window")]
    pub duplicate_window_seconds: i64,
}

fn default_storage_type() -> StorageType {
    StorageType::File
}
fn default_max_messages() -> i64 {
    1_000_000
}
fn default_max_bytes() -> i64 {
    1_073_741_824
} // 1GB
fn default_max_age_seconds() -> i64 {
    604_800
} // 7 days
fn default_replicas() -> usize {
    1
}
fn default_duplicate_window() -> i64 {
    120
}

impl Default for StreamConfig {
    fn default() -> Self {
        Self {
            name: "WEBHOOKS".to_string(),
            subjects: vec!["webhooks.*".to_string()],
            description: None,
            storage_type: StorageType::File,
            max_messages: default_max_messages(),
            max_bytes: default_max_bytes(),
            max_age_seconds: default_max_age_seconds(),
            retention_policy: RetentionPolicy::Limits,
            discard_policy: DiscardPolicy::Old,
            replicas: 1,
            duplicate_window_seconds: default_duplicate_window(),
        }
    }
}

/// Storage type for JetStream
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum StorageType {
    /// In-memory storage (faster, but not persistent)
    Memory,
    /// File-based storage (persistent)
    File,
}

/// Retention policy for JetStream
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Default)]
#[serde(rename_all = "lowercase")]
pub enum RetentionPolicy {
    /// Retain based on limits (max messages, bytes, age)
    #[default]
    Limits,
    /// Retain based on consumer interest
    Interest,
    /// Work queue (messages deleted after ack)
    WorkQueue,
}

/// Discard policy when limits are reached
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Default)]
#[serde(rename_all = "lowercase")]
pub enum DiscardPolicy {
    /// Discard old messages
    #[default]
    Old,
    /// Discard new messages
    New,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_jetstream_ack() {
        let ack = JetStreamAck::new("TEST_STREAM", 42);
        assert_eq!(ack.stream, "TEST_STREAM");
        assert_eq!(ack.sequence, 42);
        assert!(!ack.duplicate);

        let ack_dup = ack.with_duplicate(true);
        assert!(ack_dup.duplicate);
    }

    #[test]
    fn test_pool_stats() {
        let stats = PoolStats::new(10);
        assert_eq!(stats.total_connections, 10);
        assert_eq!(stats.healthy_connections, 0);
        assert_eq!(stats.health_percentage(), 0.0);
        assert!(!stats.is_healthy());

        let mut stats = stats;
        stats.healthy_connections = 8;
        assert_eq!(stats.health_percentage(), 80.0);
        assert!(stats.is_healthy());

        stats.healthy_connections = 4;
        assert_eq!(stats.health_percentage(), 40.0);
        assert!(!stats.is_healthy());
    }

    #[test]
    fn test_nats_message() {
        let msg = NatsMessage::new("test.subject", b"payload".to_vec()).with_id("msg-123");

        assert_eq!(msg.subject, "test.subject");
        assert_eq!(msg.payload, b"payload");
        assert_eq!(msg.message_id, Some("msg-123".to_string()));

        let payload_str = msg.payload_as_string().unwrap();
        assert_eq!(payload_str, "payload");
    }

    #[test]
    fn test_message_json_payload() {
        #[derive(Serialize, Deserialize, PartialEq, Debug)]
        struct TestData {
            value: i32,
        }

        let data = TestData { value: 42 };
        let json = serde_json::to_vec(&data).unwrap();

        let msg = NatsMessage::new("test", json);
        let parsed: TestData = msg.payload_as_json().unwrap();

        assert_eq!(parsed, data);
    }

    #[test]
    fn test_stream_config_default() {
        let config = StreamConfig::default();
        assert_eq!(config.name, "WEBHOOKS");
        assert_eq!(config.subjects, vec!["webhooks.*"]);
        assert_eq!(config.storage_type, StorageType::File);
        assert_eq!(config.retention_policy, RetentionPolicy::Limits);
        assert_eq!(config.discard_policy, DiscardPolicy::Old);
        assert_eq!(config.replicas, 1);
    }

    #[test]
    fn test_storage_type_serialization() {
        let memory = StorageType::Memory;
        let file = StorageType::File;

        let memory_json = serde_json::to_string(&memory).unwrap();
        let file_json = serde_json::to_string(&file).unwrap();

        assert_eq!(memory_json, "\"memory\"");
        assert_eq!(file_json, "\"file\"");
    }

    #[test]
    fn test_retention_policy_serialization() {
        let policy = RetentionPolicy::Limits;
        let json = serde_json::to_string(&policy).unwrap();
        assert_eq!(json, "\"limits\"");

        let deserialized: RetentionPolicy = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized, policy);
    }
}
