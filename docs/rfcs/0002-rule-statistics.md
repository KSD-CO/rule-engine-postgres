# RFC-0002: Rule Execution Statistics & Performance Monitoring

- **Status:** Draft
- **Author:** Rule Engine Team
- **Created:** 2025-12-06
- **Updated:** 2025-12-06
- **Phase:** 1.3 (Foundation)
- **Priority:** P0 - Critical

---

## Summary

Implement comprehensive performance monitoring and statistics tracking for rule execution, enabling users to identify bottlenecks, optimize rule performance, and gain insights into rule usage patterns.

---

## Motivation

Current implementation provides no visibility into:
- How often rules are executed
- How long rules take to execute
- Which rules are performant vs slow
- Success/failure rates
- Resource consumption patterns

### Use Cases

1. **Performance Optimization:** Identify slow rules for refactoring
2. **Capacity Planning:** Understand load patterns and resource needs
3. **Debugging:** Correlate errors with specific rules
4. **Business Intelligence:** Which business rules are most active?
5. **SLA Monitoring:** Ensure rules meet performance SLAs

---

## Detailed Design

### Database Schema

```sql
-- Aggregated statistics per rule
CREATE TABLE rule_execution_stats (
    id SERIAL PRIMARY KEY,
    rule_name TEXT NOT NULL,
    rule_version TEXT,
    
    -- Execution counts
    execution_count BIGINT NOT NULL DEFAULT 0,
    success_count BIGINT NOT NULL DEFAULT 0,
    failure_count BIGINT NOT NULL DEFAULT 0,
    
    -- Timing statistics (microseconds)
    total_duration_us BIGINT NOT NULL DEFAULT 0,
    min_duration_us INTEGER,
    max_duration_us INTEGER,
    avg_duration_us INTEGER,
    
    -- Percentiles (computed periodically)
    p50_duration_us INTEGER,
    p95_duration_us INTEGER,
    p99_duration_us INTEGER,
    
    -- Fact modification tracking
    facts_modified_count BIGINT NOT NULL DEFAULT 0,
    
    -- Time window
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    
    -- Last execution
    last_executed_at TIMESTAMP,
    last_error TEXT,
    last_error_at TIMESTAMP,
    
    CONSTRAINT rule_stats_unique UNIQUE (rule_name, rule_version, window_start)
);

CREATE INDEX idx_rule_stats_name ON rule_execution_stats(rule_name);
CREATE INDEX idx_rule_stats_window ON rule_execution_stats(window_start, window_end);
CREATE INDEX idx_rule_stats_last_exec ON rule_execution_stats(last_executed_at);

-- Detailed execution log (for debugging, TTL 7 days)
CREATE TABLE rule_execution_log (
    id BIGSERIAL PRIMARY KEY,
    rule_name TEXT NOT NULL,
    rule_version TEXT,
    
    -- Execution details
    executed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    duration_us INTEGER NOT NULL,
    success BOOLEAN NOT NULL,
    error_message TEXT,
    error_code TEXT,
    
    -- Input/output snapshots (optional, for debugging)
    facts_before JSONB,
    facts_after JSONB,
    
    -- Context
    user_context TEXT,
    execution_id UUID DEFAULT gen_random_uuid(),
    
    -- Retention policy
    expires_at TIMESTAMP NOT NULL DEFAULT NOW() + INTERVAL '7 days'
);

CREATE INDEX idx_rule_exec_log_name ON rule_execution_log(rule_name);
CREATE INDEX idx_rule_exec_log_time ON rule_execution_log(executed_at);
CREATE INDEX idx_rule_exec_log_expires ON rule_execution_log(expires_at);
CREATE INDEX idx_rule_exec_log_error ON rule_execution_log(error_code) WHERE error_code IS NOT NULL;

-- Automatic cleanup of old logs
CREATE OR REPLACE FUNCTION cleanup_execution_logs()
RETURNS VOID AS $$
BEGIN
    DELETE FROM rule_execution_log WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- Real-time performance view
CREATE VIEW rule_performance_summary AS
SELECT 
    rule_name,
    rule_version,
    SUM(execution_count) as total_executions,
    SUM(success_count) as total_successes,
    SUM(failure_count) as total_failures,
    ROUND(100.0 * SUM(success_count) / NULLIF(SUM(execution_count), 0), 2) as success_rate,
    ROUND(AVG(avg_duration_us) / 1000.0, 2) as avg_duration_ms,
    ROUND(MAX(max_duration_us) / 1000.0, 2) as max_duration_ms,
    MAX(last_executed_at) as last_execution
FROM rule_execution_stats
WHERE window_end > NOW() - INTERVAL '24 hours'
GROUP BY rule_name, rule_version
ORDER BY total_executions DESC;
```

### API Functions

#### Function 1: `rule_stats(rule_name TEXT, time_range INTERVAL DEFAULT '24 hours') → JSON`

**Purpose:** Get comprehensive statistics for a rule

**Example:**
```sql
SELECT rule_stats('discount_calculator', '7 days');

-- Returns:
{
  "rule_name": "discount_calculator",
  "rule_version": "1.0.0",
  "period": {
    "start": "2025-12-01T00:00:00Z",
    "end": "2025-12-06T00:00:00Z"
  },
  "executions": {
    "total": 15420,
    "successes": 15380,
    "failures": 40,
    "success_rate": 99.74
  },
  "performance": {
    "avg_ms": 1.23,
    "min_ms": 0.45,
    "max_ms": 45.2,
    "p50_ms": 1.1,
    "p95_ms": 2.8,
    "p99_ms": 5.6
  },
  "impact": {
    "facts_modified": 14820,
    "modification_rate": 96.3
  },
  "errors": {
    "last_error": "RE-301: Timeout exceeded",
    "last_error_at": "2025-12-05T14:32:15Z"
  }
}
```

#### Function 2: `rule_performance_report(limit INTEGER DEFAULT 10, order_by TEXT DEFAULT 'executions') → TABLE`

**Purpose:** Get top N rules by various metrics

**Example:**
```sql
-- Top 10 most executed rules
SELECT * FROM rule_performance_report(10, 'executions');

-- Top 10 slowest rules
SELECT * FROM rule_performance_report(10, 'duration');

-- Top 10 highest error rate
SELECT * FROM rule_performance_report(10, 'errors');
```

#### Function 3: `rule_execution_history(rule_name TEXT, limit INTEGER DEFAULT 100) → TABLE`

**Purpose:** Get recent execution history for debugging

**Example:**
```sql
SELECT * FROM rule_execution_history('discount_calculator', 50)
WHERE success = false
ORDER BY executed_at DESC;
```

#### Function 4: `rule_clear_stats(rule_name TEXT) → BOOLEAN`

**Purpose:** Clear statistics for a rule (useful after optimization)

#### Function 5: `rule_compare_performance(rule_name TEXT, version1 TEXT, version2 TEXT, time_range INTERVAL) → JSON`

**Purpose:** Compare performance between two versions

**Example:**
```sql
SELECT rule_compare_performance('discount_calculator', '1.0.0', '2.0.0', '24 hours');

-- Returns:
{
  "version_1": {
    "version": "1.0.0",
    "avg_ms": 2.5,
    "p95_ms": 4.2,
    "success_rate": 98.5
  },
  "version_2": {
    "version": "2.0.0",
    "avg_ms": 1.8,
    "p95_ms": 3.1,
    "success_rate": 99.2
  },
  "improvement": {
    "avg_speedup": "28%",
    "p95_speedup": "26%",
    "reliability_gain": "0.7%"
  }
}
```

### Internal Implementation

```rust
// src/monitoring/stats.rs
use std::time::Instant;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct ExecutionMetrics {
    pub rule_name: String,
    pub rule_version: Option<String>,
    pub duration_us: i64,
    pub success: bool,
    pub error_message: Option<String>,
    pub facts_modified: bool,
}

pub struct StatsCollector {
    start_time: Instant,
    rule_name: String,
    rule_version: Option<String>,
}

impl StatsCollector {
    pub fn new(rule_name: String, rule_version: Option<String>) -> Self {
        Self {
            start_time: Instant::now(),
            rule_name,
            rule_version,
        }
    }
    
    pub fn record_success(&self, facts_modified: bool) {
        let duration_us = self.start_time.elapsed().as_micros() as i64;
        
        let metrics = ExecutionMetrics {
            rule_name: self.rule_name.clone(),
            rule_version: self.rule_version.clone(),
            duration_us,
            success: true,
            error_message: None,
            facts_modified,
        };
        
        self.persist_metrics(metrics);
    }
    
    pub fn record_failure(&self, error: &str) {
        let duration_us = self.start_time.elapsed().as_micros() as i64;
        
        let metrics = ExecutionMetrics {
            rule_name: self.rule_name.clone(),
            rule_version: self.rule_version.clone(),
            duration_us,
            success: false,
            error_message: Some(error.to_string()),
            facts_modified: false,
        };
        
        self.persist_metrics(metrics);
    }
    
    fn persist_metrics(&self, metrics: ExecutionMetrics) {
        // Insert into rule_execution_log
        Spi::run(&format!(
            "INSERT INTO rule_execution_log 
             (rule_name, rule_version, duration_us, success, error_message)
             VALUES ($1, $2, $3, $4, $5)",
        )).unwrap();
        
        // Update aggregated stats
        self.update_aggregated_stats(&metrics);
    }
    
    fn update_aggregated_stats(&self, metrics: &ExecutionMetrics) {
        // Use INSERT ... ON CONFLICT UPDATE for atomic stats update
        Spi::run(&format!(
            "INSERT INTO rule_execution_stats 
             (rule_name, rule_version, window_start, window_end,
              execution_count, success_count, failure_count,
              total_duration_us, min_duration_us, max_duration_us)
             VALUES ($1, $2, date_trunc('hour', NOW()), 
                     date_trunc('hour', NOW()) + INTERVAL '1 hour',
                     1, $3, $4, $5, $5, $5)
             ON CONFLICT (rule_name, rule_version, window_start) 
             DO UPDATE SET
                 execution_count = rule_execution_stats.execution_count + 1,
                 success_count = rule_execution_stats.success_count + $3,
                 failure_count = rule_execution_stats.failure_count + $4,
                 total_duration_us = rule_execution_stats.total_duration_us + $5,
                 min_duration_us = LEAST(rule_execution_stats.min_duration_us, $5),
                 max_duration_us = GREATEST(rule_execution_stats.max_duration_us, $5),
                 last_executed_at = NOW()",
        )).unwrap();
    }
}

// Instrument existing functions
#[pg_extern]
pub fn run_rule_engine_instrumented(
    facts_json: String,
    rules_grl: String,
) -> Result<String, RuleEngineError> {
    let collector = StatsCollector::new("inline_rule".to_string(), None);
    
    match run_rule_engine_impl(&facts_json, &rules_grl) {
        Ok(result) => {
            let facts_modified = result != facts_json;
            collector.record_success(facts_modified);
            Ok(result)
        }
        Err(e) => {
            collector.record_failure(&e.to_string());
            Err(e)
        }
    }
}
```

### Performance Considerations

- **Async Stats Updates:** Don't block rule execution
- **Batching:** Aggregate stats in memory, flush periodically
- **Sampling:** For high-throughput systems, sample executions
- **Partitioning:** Partition stats table by time for faster queries
- **Retention:** Auto-cleanup old logs to prevent bloat

**Configuration:**
```sql
-- Set stats collection level
SET rule_engine.stats_level = 'full'; -- full, aggregated, minimal, off

-- Set sampling rate for high-volume rules
SET rule_engine.stats_sampling_rate = 0.1; -- 10% sampling
```

---

## Examples

### Example 1: Performance Debugging

```sql
-- Find slow rules
SELECT rule_name, avg_duration_ms, max_duration_ms
FROM rule_performance_summary
WHERE avg_duration_ms > 5.0
ORDER BY avg_duration_ms DESC;

-- Analyze error patterns
SELECT error_code, COUNT(*), MAX(executed_at)
FROM rule_execution_log
WHERE executed_at > NOW() - INTERVAL '1 hour'
  AND success = false
GROUP BY error_code;
```

### Example 2: A/B Testing Analysis

```sql
-- Compare two rule versions
SELECT rule_compare_performance(
    'pricing_rule',
    '1.0.0',
    '2.0.0',
    '24 hours'
);

-- Detailed comparison
SELECT 
    rule_version,
    AVG(duration_us / 1000.0) as avg_ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_us / 1000.0) as p95_ms,
    COUNT(CASE WHEN success THEN 1 END) * 100.0 / COUNT(*) as success_rate
FROM rule_execution_log
WHERE rule_name = 'pricing_rule'
  AND executed_at > NOW() - INTERVAL '24 hours'
GROUP BY rule_version;
```

### Example 3: Monitoring Dashboard

```sql
-- Real-time dashboard query
SELECT 
    rule_name,
    total_executions,
    success_rate,
    avg_duration_ms,
    last_execution
FROM rule_performance_summary
WHERE last_execution > NOW() - INTERVAL '5 minutes'
ORDER BY total_executions DESC
LIMIT 20;
```

---

## Success Metrics

- **Performance Overhead:** < 1% latency increase
- **Storage Growth:** < 1GB per million executions
- **Query Performance:** Dashboard queries < 100ms
- **Adoption:** 80% of production deployments enable stats

---

## Changelog

- **2025-12-06:** Initial draft
