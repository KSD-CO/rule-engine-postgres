/// NATS publisher
///
/// This module provides high-level publishing interface for NATS.
use async_nats::jetstream::{self, Context as JetStreamContext};
use async_nats::HeaderMap;
use std::time::Duration;

use crate::nats::config::NatsConfig;
use crate::nats::error::NatsError;
use crate::nats::models::{JetStreamAck, NatsMessage};
use crate::nats::pool::NatsPool;

/// NATS Publisher
///
/// Provides methods to publish messages to NATS core and JetStream.
pub struct NatsPublisher {
    /// Connection pool
    pool: NatsPool,

    /// JetStream context (if enabled)
    jetstream: Option<JetStreamContext>,
}

impl NatsPublisher {
    /// Create a new publisher from configuration
    pub async fn new(config: NatsConfig) -> Result<Self, NatsError> {
        let pool = NatsPool::new(config.clone()).await?;

        // Initialize JetStream if enabled
        let jetstream = if config.jetstream_enabled {
            let client = pool.get_client();
            Some(jetstream::new(client.clone()))
        } else {
            None
        };

        Ok(Self { pool, jetstream })
    }

    /// Publish a message to NATS core (fire-and-forget)
    ///
    /// This is the fastest option but provides no delivery guarantees.
    pub async fn publish(&self, subject: &str, payload: &[u8]) -> Result<(), NatsError> {
        let client = self.pool.get_client();

        client
            .publish(subject.to_string(), payload.to_vec().into())
            .await
            .map_err(|e| {
                NatsError::PublishError(format!("Failed to publish to {}: {}", subject, e))
            })?;

        Ok(())
    }

    /// Publish a message with custom headers
    pub async fn publish_with_headers(
        &self,
        subject: &str,
        headers: HeaderMap,
        payload: &[u8],
    ) -> Result<(), NatsError> {
        let client = self.pool.get_client();

        client
            .publish_with_headers(subject.to_string(), headers, payload.to_vec().into())
            .await
            .map_err(|e| {
                NatsError::PublishError(format!(
                    "Failed to publish with headers to {}: {}",
                    subject, e
                ))
            })?;

        Ok(())
    }

    /// Publish a message with timeout
    pub async fn publish_with_timeout(
        &self,
        subject: &str,
        payload: &[u8],
        timeout: Duration,
    ) -> Result<(), NatsError> {
        tokio::time::timeout(timeout, self.publish(subject, payload))
            .await
            .map_err(|_| NatsError::TimeoutError(format!("Publish to {} timed out", subject)))?
    }

    /// Publish to JetStream (acknowledged, persistent)
    ///
    /// Returns acknowledgment with stream name and sequence number.
    pub async fn publish_jetstream(
        &self,
        subject: &str,
        payload: &[u8],
    ) -> Result<JetStreamAck, NatsError> {
        let js = self
            .jetstream
            .as_ref()
            .ok_or(NatsError::JetStreamNotEnabled)?;

        let pub_ack = js
            .publish(subject.to_string(), payload.to_vec().into())
            .await
            .map_err(|e| NatsError::PublishError(format!("Failed to publish to JetStream: {}", e)))?
            .await
            .map_err(|e| {
                NatsError::PublishError(format!("Failed to get JetStream acknowledgment: {}", e))
            })?;

        Ok(JetStreamAck::new(pub_ack.stream, pub_ack.sequence))
    }

    /// Publish to JetStream with message ID for deduplication
    ///
    /// Messages with the same ID within the duplicate window will be rejected.
    pub async fn publish_jetstream_with_id(
        &self,
        subject: &str,
        message_id: &str,
        payload: &[u8],
    ) -> Result<JetStreamAck, NatsError> {
        let js = self
            .jetstream
            .as_ref()
            .ok_or(NatsError::JetStreamNotEnabled)?;

        // Create headers with message ID
        let mut headers = HeaderMap::new();
        headers.insert("Nats-Msg-Id", message_id);

        let pub_ack = js
            .publish_with_headers(subject.to_string(), headers, payload.to_vec().into())
            .await
            .map_err(|e| {
                NatsError::PublishError(format!("Failed to publish to JetStream with ID: {}", e))
            })?
            .await
            .map_err(|e| {
                NatsError::PublishError(format!(
                    "Failed to get JetStream acknowledgment with ID: {}",
                    e
                ))
            })?;

        // Check if this was a duplicate
        let duplicate = pub_ack.duplicate;

        Ok(JetStreamAck::new(pub_ack.stream, pub_ack.sequence).with_duplicate(duplicate))
    }

    /// Publish a NatsMessage (convenience method)
    pub async fn publish_message(&self, message: NatsMessage) -> Result<(), NatsError> {
        if let Some(headers) = message.headers {
            self.publish_with_headers(&message.subject, headers, &message.payload)
                .await
        } else {
            self.publish(&message.subject, &message.payload).await
        }
    }

    /// Publish a NatsMessage to JetStream
    pub async fn publish_message_jetstream(
        &self,
        message: NatsMessage,
    ) -> Result<JetStreamAck, NatsError> {
        if let Some(msg_id) = message.message_id {
            self.publish_jetstream_with_id(&message.subject, &msg_id, &message.payload)
                .await
        } else {
            self.publish_jetstream(&message.subject, &message.payload)
                .await
        }
    }

    /// Get the connection pool
    pub fn pool(&self) -> &NatsPool {
        &self.pool
    }

    /// Check if JetStream is enabled
    pub fn is_jetstream_enabled(&self) -> bool {
        self.jetstream.is_some()
    }

    /// Get JetStream context
    pub fn jetstream(&self) -> Option<&JetStreamContext> {
        self.jetstream.as_ref()
    }

    /// Flush all pending messages
    pub async fn flush(&self) -> Result<(), NatsError> {
        for client in self.pool.get_all_clients() {
            client
                .flush()
                .await
                .map_err(|e| NatsError::PublishError(format!("Failed to flush: {}", e)))?;
        }
        Ok(())
    }

    /// Close the publisher and all connections
    pub async fn close(mut self) -> Result<(), NatsError> {
        self.flush().await?;
        self.pool.close().await?;
        Ok(())
    }
}

impl Clone for NatsPublisher {
    fn clone(&self) -> Self {
        Self {
            pool: self.pool.clone(),
            jetstream: self.jetstream.clone(),
        }
    }
}

impl std::fmt::Debug for NatsPublisher {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("NatsPublisher")
            .field("pool", &self.pool)
            .field("jetstream_enabled", &self.jetstream.is_some())
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_jetstream_check() {
        // Unit test for JetStream enabled check
        // Actual publishing requires a running NATS server (integration test)
    }

    #[test]
    fn test_nats_message_creation() {
        let msg = NatsMessage::new("test.subject", b"payload".to_vec()).with_id("msg-123");

        assert_eq!(msg.subject, "test.subject");
        assert_eq!(msg.message_id, Some("msg-123".to_string()));
    }
}
