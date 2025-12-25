/// NATS connection pool
///
/// This module provides connection pooling for NATS clients.
use async_nats::Client;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use crate::nats::client::{check_connection, create_client};
use crate::nats::config::NatsConfig;
use crate::nats::error::NatsError;
use crate::nats::models::PoolStats;

/// NATS connection pool
///
/// Maintains a pool of NATS connections and distributes requests across them
/// using round-robin load balancing.
pub struct NatsPool {
    /// Pool of NATS clients
    clients: Vec<Client>,

    /// Current index for round-robin selection
    current_index: Arc<AtomicUsize>,

    /// Configuration used to create clients
    config: NatsConfig,

    /// Total number of requests served
    requests_served: Arc<AtomicUsize>,
}

impl NatsPool {
    /// Create a new connection pool
    ///
    /// Creates `config.max_connections` clients and stores them in the pool.
    pub async fn new(config: NatsConfig) -> Result<Self, NatsError> {
        config.validate()?;

        let pool_size = config.max_connections;
        let mut clients = Vec::with_capacity(pool_size);

        // Create all connections
        for i in 0..pool_size {
            match create_client(&config).await {
                Ok(client) => clients.push(client),
                Err(e) => {
                    return Err(NatsError::PoolError(format!(
                        "Failed to create connection {}/{}: {}",
                        i + 1,
                        pool_size,
                        e
                    )));
                }
            }
        }

        Ok(Self {
            clients,
            current_index: Arc::new(AtomicUsize::new(0)),
            config,
            requests_served: Arc::new(AtomicUsize::new(0)),
        })
    }

    /// Get the next available client using round-robin
    pub fn get_client(&self) -> &Client {
        if self.clients.is_empty() {
            panic!("Pool has no clients");
        }

        // Increment request counter
        self.requests_served.fetch_add(1, Ordering::Relaxed);

        // Get next client using round-robin
        let index = self.current_index.fetch_add(1, Ordering::Relaxed) % self.clients.len();
        &self.clients[index]
    }

    /// Get all clients in the pool
    pub fn get_all_clients(&self) -> &[Client] {
        &self.clients
    }

    /// Get pool statistics
    pub fn pool_stats(&self) -> PoolStats {
        let total_connections = self.clients.len();
        let healthy_connections = self.clients.iter().filter(|c| check_connection(c)).count();

        PoolStats {
            total_connections,
            healthy_connections,
            requests_served: self.requests_served.load(Ordering::Relaxed) as u64,
            active_requests: 0, // We don't track this in simple pool
        }
    }

    /// Check if the pool is healthy (at least 50% connections available)
    pub fn is_healthy(&self) -> bool {
        self.pool_stats().is_healthy()
    }

    /// Get configuration
    pub fn config(&self) -> &NatsConfig {
        &self.config
    }

    /// Get pool size
    pub fn size(&self) -> usize {
        self.clients.len()
    }

    /// Gracefully close all connections
    pub async fn close(&mut self) -> Result<(), NatsError> {
        for client in &self.clients {
            client
                .flush()
                .await
                .map_err(|e| NatsError::PoolError(format!("Failed to flush client: {}", e)))?;
        }

        Ok(())
    }

    /// Attempt to reconnect unhealthy clients
    pub async fn heal(&mut self) -> Result<usize, NatsError> {
        let mut reconnected = 0;

        for (i, client) in self.clients.iter_mut().enumerate() {
            if !check_connection(client) {
                // Try to create a new connection
                match create_client(&self.config).await {
                    Ok(new_client) => {
                        *client = new_client;
                        reconnected += 1;
                    }
                    Err(e) => {
                        // Log error but continue with other connections
                        eprintln!("Failed to reconnect client {}: {}", i, e);
                    }
                }
            }
        }

        Ok(reconnected)
    }
}

impl Clone for NatsPool {
    fn clone(&self) -> Self {
        Self {
            clients: self.clients.clone(),
            current_index: Arc::clone(&self.current_index),
            config: self.config.clone(),
            requests_served: Arc::clone(&self.requests_served),
        }
    }
}

// Implement Debug manually to avoid printing sensitive data
impl std::fmt::Debug for NatsPool {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("NatsPool")
            .field("size", &self.clients.len())
            .field("current_index", &self.current_index.load(Ordering::Relaxed))
            .field(
                "requests_served",
                &self.requests_served.load(Ordering::Relaxed),
            )
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pool_size() {
        // This test would require a running NATS server
        // Skipping actual connection tests in unit tests
    }

    #[test]
    fn test_round_robin_math() {
        // Test round-robin index calculation
        let pool_size = 5;
        let counter = AtomicUsize::new(0);

        let indices: Vec<usize> = (0..15)
            .map(|_| counter.fetch_add(1, Ordering::Relaxed) % pool_size)
            .collect();

        // Should cycle through 0,1,2,3,4,0,1,2,3,4,0,1,2,3,4
        assert_eq!(indices, vec![0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4]);
    }

    #[test]
    fn test_config_validation() {
        let config = NatsConfig {
            max_connections: 0,
            ..Default::default()
        };

        // Should fail validation
        assert!(config.validate().is_err());
    }
}
