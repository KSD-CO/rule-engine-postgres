/// Unit tests for NatsPool and PoolStats
#[cfg(test)]
mod tests {
    use crate::nats::models::PoolStats;

    #[test]
    fn test_pool_stats_default() {
        let stats = PoolStats::default();

        assert_eq!(stats.total_connections, 0);
        assert_eq!(stats.healthy_connections, 0);
        assert_eq!(stats.requests_served, 0);
    }

    #[test]
    fn test_pool_stats_health_percentage_all_healthy() {
        let stats = PoolStats {
            total_connections: 10,
            healthy_connections: 10,
            requests_served: 100,
            active_requests: 0,
        };

        assert_eq!(stats.health_percentage(), 100.0);
    }

    #[test]
    fn test_pool_stats_health_percentage_partial() {
        let stats = PoolStats {
            total_connections: 10,
            healthy_connections: 7,
            requests_served: 50,
            active_requests: 0,
        };

        assert_eq!(stats.health_percentage(), 70.0);
    }

    #[test]
    fn test_pool_stats_health_percentage_none_healthy() {
        let stats = PoolStats {
            total_connections: 5,
            healthy_connections: 0,
            requests_served: 0,
            active_requests: 0,
        };

        assert_eq!(stats.health_percentage(), 0.0);
    }

    #[test]
    fn test_pool_stats_health_percentage_zero_total() {
        let stats = PoolStats {
            total_connections: 0,
            healthy_connections: 0,
            requests_served: 0,
            active_requests: 0,
        };

        assert_eq!(stats.health_percentage(), 0.0);
    }

    #[test]
    fn test_pool_stats_increment_requests() {
        let mut stats = PoolStats {
            total_connections: 5,
            healthy_connections: 5,
            requests_served: 0,
            active_requests: 0,
        };

        stats.requests_served += 1;
        assert_eq!(stats.requests_served, 1);

        stats.requests_served += 99;
        assert_eq!(stats.requests_served, 100);
    }

    #[test]
    fn test_pool_stats_health_degradation() {
        let mut stats = PoolStats {
            total_connections: 10,
            healthy_connections: 10,
            requests_served: 0,
            active_requests: 0,
        };

        // Simulate connection failures
        stats.healthy_connections = 8;
        assert_eq!(stats.health_percentage(), 80.0);

        stats.healthy_connections = 5;
        assert_eq!(stats.health_percentage(), 50.0);

        stats.healthy_connections = 1;
        assert_eq!(stats.health_percentage(), 10.0);
    }

    #[test]
    fn test_pool_stats_clone() {
        let stats1 = PoolStats {
            total_connections: 5,
            healthy_connections: 4,
            requests_served: 100,
            active_requests: 2,
        };

        let stats2 = stats1.clone();

        assert_eq!(stats1.total_connections, stats2.total_connections);
        assert_eq!(stats1.healthy_connections, stats2.healthy_connections);
        assert_eq!(stats1.requests_served, stats2.requests_served);
        assert_eq!(stats1.active_requests, stats2.active_requests);
    }

    #[test]
    fn test_pool_stats_debug() {
        let stats = PoolStats {
            total_connections: 3,
            healthy_connections: 2,
            requests_served: 50,
            active_requests: 1,
        };

        let debug_str = format!("{:?}", stats);
        assert!(debug_str.contains("total_connections"));
        assert!(debug_str.contains("3"));
        assert!(debug_str.contains("2"));
        assert!(debug_str.contains("50"));
    }

    #[test]
    fn test_pool_stats_equality() {
        let stats1 = PoolStats {
            total_connections: 5,
            healthy_connections: 5,
            requests_served: 100,
            active_requests: 0,
        };

        let stats2 = PoolStats {
            total_connections: 5,
            healthy_connections: 5,
            requests_served: 100,
            active_requests: 0,
        };

        let stats3 = PoolStats {
            total_connections: 5,
            healthy_connections: 4,
            requests_served: 100,
            active_requests: 0,
        };

        assert_eq!(stats1, stats2);
        assert_ne!(stats1, stats3);
    }

    #[test]
    fn test_pool_stats_edge_cases() {
        // Very large numbers
        let stats = PoolStats {
            total_connections: usize::MAX,
            healthy_connections: usize::MAX,
            requests_served: u64::MAX,
            active_requests: 0,
        };

        assert_eq!(stats.health_percentage(), 100.0);

        // Mismatched counts (should still calculate correctly)
        let bad_stats = PoolStats {
            total_connections: 5,
            healthy_connections: 10, // More healthy than total (shouldn't happen)
            requests_served: 0,
            active_requests: 0,
        };

        // Health percentage would be > 100%, but mathematically correct
        assert_eq!(bad_stats.health_percentage(), 200.0);
    }

    #[test]
    fn test_pool_stats_realistic_scenario() {
        // Simulate a pool with 10 connections processing requests
        let mut stats = PoolStats {
            total_connections: 10,
            healthy_connections: 10,
            requests_served: 0,
            active_requests: 0,
        };

        // Process 1000 requests
        for _ in 0..1000 {
            stats.requests_served += 1;
        }

        assert_eq!(stats.requests_served, 1000);
        assert_eq!(stats.health_percentage(), 100.0);

        // Simulate 2 connections failing
        stats.healthy_connections = 8;
        assert_eq!(stats.health_percentage(), 80.0);

        // Continue processing
        for _ in 0..500 {
            stats.requests_served += 1;
        }

        assert_eq!(stats.requests_served, 1500);
        assert_eq!(stats.health_percentage(), 80.0);
    }

    // Note: Full NatsPool tests require async runtime and are in integration tests
    // These unit tests cover PoolStats which is synchronous
}
