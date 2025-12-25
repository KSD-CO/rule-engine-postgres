/// NATS Integration Module
///
/// This module provides NATS (Message Queue) integration for the rule engine,
/// enabling event-driven architecture with pub/sub patterns, distributed processing,
/// and horizontal scalability.
///
/// # Features
///
/// - **NATS Core Publishing**: Fire-and-forget message publishing
/// - **JetStream**: Persistent, acknowledged message streaming
/// - **Connection Pooling**: Efficient connection reuse with round-robin load balancing
/// - **Deduplication**: Prevent duplicate message processing using message IDs
/// - **Error Handling**: Comprehensive error types with retry classification
///
/// # Example
///
/// ```rust,no_run
/// use rule_engine_postgres::nats::{NatsConfig, NatsPublisher};
///
/// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
/// // Create configuration
/// let config = NatsConfig::new("nats://localhost:4222")
///     .with_jetstream("WEBHOOKS")
///     .with_pool_size(10);
///
/// // Create publisher with explicit type
/// let publisher: NatsPublisher = NatsPublisher::new(config).await?;
///
/// // Publish message
/// publisher.publish("webhooks.test", b"Hello NATS!").await?;
///
/// // Publish to JetStream with acknowledgment
/// let ack = publisher.publish_jetstream("webhooks.important", b"Critical message").await?;
/// println!("Published to {} with sequence {}", ack.stream, ack.sequence);
/// # Ok(())
/// # }
/// ```
// Module declarations
pub mod client;
pub mod config;
pub mod error;
pub mod models;
pub mod pool;
pub mod publisher;

#[cfg(test)]
mod tests;

// Re-exports for convenience
#[allow(unused_imports)]
pub use client::{check_connection, create_client, create_client_with_retry, ConnectionStats};
pub use config::{AuthType, NatsConfig};
#[allow(unused_imports)]
pub use error::NatsError;
#[allow(unused_imports)]
pub use models::{
    DiscardPolicy, JetStreamAck, NatsMessage, PoolStats, RetentionPolicy, StorageType, StreamConfig,
};
#[allow(unused_imports)]
pub use pool::NatsPool;
pub use publisher::NatsPublisher;

/// NATS integration version
#[allow(dead_code)]
pub const NATS_INTEGRATION_VERSION: &str = "0.1.0";
