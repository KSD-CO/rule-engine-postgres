# rule-engine-postgres

[![CI](https://github.com/KSD-CO/rule-engine-postgres/actions/workflows/ci.yml/badge.svg)](https://github.com/KSD-CO/rule-engine-postgres/actions)
[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/KSD-CO/rule-engine-postgres/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Performance](https://img.shields.io/badge/Performance-103k_orders/sec-brightgreen.svg)](tests/PERFORMANCE_RESULTS.md)
[![RETE](https://img.shields.io/badge/RETE-44k_evals/sec-success.svg)](tests/benchmark_rete.sql)

High-performance PostgreSQL rule engine with **RETE algorithm** (2-24x faster), **time-travel debugging**, **24 built-in functions**, and **flexible execution modes**. Execute complex business logic using GRL (Grule Rule Language) with incremental evaluation, pattern sharing, and full observability.

> **🚀 NEW in v2.0.0: RETE Engine + Time-Travel Debugging!**
> **103,734 orders/sec** (E-commerce) | **44,286 evals/sec** (High-throughput) | **66 orders/sec** (Batch processing)
> 📊 [Performance Results](tests/PERFORMANCE_RESULTS.md) | [Engine Selection Guide](docs/ENGINE_SELECTION.md) | [Release Summary](docs/V2_RELEASE_SUMMARY.md)

---

## 🚀 Quick Start (5 Minutes)

### 1. Install (Choose One)

<details>
<summary><b>🐳 Docker (Easiest - No Installation)</b></summary>

```bash
docker run -d --name rule-engine-postgres \
  -p 5432:5432 -e POSTGRES_PASSWORD=postgres \
  jamesvu/rule-engine-postgres:latest

# Connect
psql -h localhost -U postgres -d postgres
```
</details>

<details>
<summary><b>📦 Ubuntu/Debian One-Liner</b></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/KSD-CO/rule-engine-postgres/main/quick-install.sh | bash
```
</details>

<details>
<summary><b>🔧 Pre-built Package</b></summary>

**Ubuntu/Debian:**
```bash
wget https://github.com/KSD-CO/rule-engine-postgres/releases/download/v1.7.0/postgresql-16-rule-engine_1.7.0_amd64.deb
sudo dpkg -i postgresql-16-rule-engine_1.7.0_amd64.deb
```

**RHEL/Rocky/AlmaLinux:**
```bash
wget https://github.com/KSD-CO/rule-engine-postgres/releases/download/v1.7.0/postgresql16-rule-engine-1.7.0-1.x86_64.rpm
sudo rpm -i postgresql16-rule-engine-1.7.0-1.x86_64.rpm
```
</details>

<details>
<summary><b>⚙️ Build from Source</b></summary>

```bash
# Prerequisites: Rust 1.75+, PostgreSQL 16-18
cargo install cargo-pgrx --version 0.16.1 --locked
git clone https://github.com/KSD-CO/rule-engine-postgres.git
cd rule-engine-postgres
./install.sh
```
</details>

**📚 Detailed instructions:** [Installation Guide](docs/INSTALLATION.md)

---

### 2. Enable Extension

```sql
-- Connect to your database
psql -U postgres -d your_database

-- IMPORTANT: Install pgcrypto first (required for v1.6.0+)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create rule engine extension
CREATE EXTENSION rule_engine_postgre_extensions;

-- Verify
SELECT rule_engine_version();  -- Returns: 2.0.0
```

**Note:** The `pgcrypto` extension is required for credential encryption in External Data Sources (v1.6.0+).

---

### 3. Run Your First Rule (RETE Engine - High Performance!)

```sql
-- Simple discount rule - Uses RETE algorithm by default (2-24x faster!)
SELECT run_rule_engine(
    '{"Order": {"total": 150, "discount": 0}}',
    'rule "Discount" {
        when Order.total > 100
        then Order.discount = Order.total * 0.10;
    }'
)::jsonb;

-- Result: {"Order": {"total": 150, "discount": 15.0}}

-- Batch processing - RETE really shines here! (66 orders/sec)
DO $$
DECLARE i INT;
BEGIN
    FOR i IN 1..100 LOOP
        PERFORM run_rule_engine(
            format('{"Order": {"id": %s, "total": %s}}', i, 1000 + i*10)::text,
            'rule "VIP" { when Order.total > 1500 then Order.vip = true; }'
        );
    END LOOP;
END $$;
-- RETE: ~1.5 seconds | Forward Chaining: ~15 seconds | Speedup: 10x!

-- Or use flat JSON (also supported)
SELECT run_rule_engine(
    '{"total": 150, "discount": 0}',
    'rule "Discount" {
        when total > 100
        then discount = total * 0.10;
    }'
)::jsonb;
-- Result: {"total": 150, "discount": 15.0}
```

✅ **Done!** You just executed your first business rule.

**Engine Selection (v2.0.0):**
```sql
-- Default: RETE algorithm (recommended for production)
SELECT run_rule_engine(facts, rules);           -- 2-24x faster

-- Explicit: RETE for high-performance scenarios
SELECT run_rule_engine_rete(facts, rules);      -- Same as default

-- Forward Chaining: For simple rules (1-3 rules, single eval)
SELECT run_rule_engine_fc(facts, rules);        -- Traditional approach
```

**When to use which:**
- ✅ **RETE** (`run_rule_engine`): Batch processing, complex rules, production workloads
- ✅ **Forward Chaining** (`run_rule_engine_fc`): Simple validation, 1-3 rules, debugging

📊 **[Engine Selection Guide](docs/ENGINE_SELECTION.md)** | [Performance Comparison](tests/PERFORMANCE_RESULTS.md)

**Note:** Both flat and nested JSON structures are supported. The extension automatically converts nested objects to the dotted key format used internally.

**📚 More examples:** [Quick Start Guide](docs/QUICKSTART.md)

---

## ⭐ Why Use This?

| Feature | Benefit |
|---------|---------|
| **🚀 RETE Algorithm** | 2-24x faster with incremental evaluation & pattern sharing |
| **⚡ Extreme Performance** | 103K orders/sec (e-commerce), 44K evals/sec (high-throughput) |
| **🎯 Flexible Engines** | RETE (fast) + Forward Chaining (predictable) - choose per use case |
| **🐛 Time-Travel Debug** | Event sourcing for complete execution replay & analysis |
| **📦 Rule Repository** | Version control, tagging, and activation management |
| **🔄 Dynamic Logic** | Change business rules without code deployment |
| **🔒 Transaction Safe** | Rules execute within PostgreSQL transactions |
| **🚀 NATS Integration** | 100K+ msg/sec throughput with JetStream persistence (NEW in v1.8.0) |

---

## 🎯 Core Features

### 🚀 v2.0.0: RETE Engine + Time-Travel Debugging

#### High-Performance RETE Algorithm

**3 execution modes** for optimal performance:

```sql
-- 1. Default (RETE) - Recommended for production
SELECT run_rule_engine(facts, rules);  -- 2-24x faster!

-- 2. Explicit RETE - For batch processing
SELECT run_rule_engine_rete(facts, rules);  -- 103K orders/sec

-- 3. Forward Chaining - For simple cases
SELECT run_rule_engine_fc(facts, rules);  -- Predictable order
```

**Performance comparison** (measured):
```
Scenario              | RETE        | Forward Chaining | Speedup
---------------------|-------------|------------------|--------
Batch 50 orders      | 755 ms      | ~4000 ms        | 5.3x
High-throughput 100  | 2.3 ms      | ~8000 ms        | 3478x
E-commerce (25)      | 0.2 ms      | ~3000 ms        | 15000x
```

**When to use each:**
- ✅ **RETE**: Batch processing, complex rules, high-throughput (>50/sec)
- ✅ **FC**: Simple rules (1-3), single evaluations, debugging

📊 **[Full Performance Results](tests/PERFORMANCE_RESULTS.md)** | **[Engine Selection Guide](docs/ENGINE_SELECTION.md)**

#### Time-Travel Debugging

Complete execution replay with event sourcing:

```sql
-- Execute with debugging enabled
SELECT * FROM run_rule_engine_debug(
    '{"Order": {"total": 1500}}',
    'rule "Discount" { when Order.total > 1000 then Order.discount = 150; }'
);
-- Returns: session_id, total_steps, total_events, result

-- Replay execution step-by-step
SELECT * FROM debug_get_events('session_<uuid>');

-- List all debug sessions
SELECT * FROM debug_list_sessions();

-- Analyze why a rule fired/didn't fire
SELECT event_type, step, event_data
FROM debug_get_events('session_<uuid>')
WHERE event_type IN ('RuleFired', 'RuleSkipped');
```

**Persistence:** Events stored in PostgreSQL for long-term analysis
- `rule_execution_events` - Immutable event log
- `rule_execution_sessions` - Session metadata

**Debug Configuration:**
```sql
-- Runtime control (no code changes needed!)
SELECT debug_enable();   -- Enable debug mode (5-15% overhead)
SELECT debug_disable();  -- Disable debug mode (0% overhead)

-- PostgreSQL persistence control
SELECT debug_enable_persistence();   -- Store events in database tables
SELECT debug_disable_persistence();  -- In-memory only (faster)

-- Check current configuration
SELECT debug_status();
-- Returns: {"debug_enabled": false, "persistence_enabled": false}

-- Clean up debug sessions
SELECT debug_delete_session('session-id');
SELECT debug_clear_all_sessions();  -- ⚠️ Deletes all debug data
```

**Use Cases:**

1. **Production Troubleshooting** (no code deploy needed):
```sql
-- Enable debug mode
SELECT debug_enable();

-- Run SAME function - automatically captures debug events!
SELECT run_rule_engine(
    '{"Order": {"total": 500}}',
    'rule "Discount" { when Order.total > 1000 then Order.discount = 150; }'
);
-- Returns: {"Order": {"total": 500}}
-- NOTICE: Debug session: session_abc123... (use debug_get_events() to view)

-- Check all debug sessions
SELECT * FROM debug_list_sessions();

-- Analyze what happened
SELECT * FROM debug_get_events('session_abc123...');
-- Shows: RuleEvaluated matched=false, reason="Order.total = 500 < 1000"

-- Disable debug when done
SELECT debug_disable();

-- Same function now runs at full speed (0% overhead)
SELECT run_rule_engine(...);
```

2. **Development** - Always-on debug with in-memory storage:
```sql
SELECT debug_enable();
SELECT debug_disable_persistence();  -- Fast in-memory only

-- All run_rule_engine() calls now capture debug events
SELECT run_rule_engine(...);
```

3. **Compliance/Audit** - Persistent debug trail:
```sql
SELECT debug_enable();
SELECT debug_enable_persistence();  -- Store to PostgreSQL tables

-- All executions stored in rule_execution_events table
SELECT run_rule_engine(...);
```

4. **Explicit Debug** - Use separate function (backwards compatible):
```sql
-- Always captures debug, regardless of debug_enable() setting
SELECT * FROM run_rule_engine_debug(...);
-- Returns: session_id | total_steps | total_events | result
```

**Best Practices:**
- **Default**: Debug disabled in production (0% overhead)
- **Troubleshooting**: `SELECT debug_enable()` → same code captures events
- **No code changes**: Production code doesn't need modification
- **Memory**: Use in-memory mode unless audit trail required
- **Cleanup**: Clear old sessions regularly with `debug_clear_all_sessions()`

📚 **[Full Debug Guide](https://github.com/KSD-CO/rule-engine-postgres/wiki/Time-Travel-Debugging)**

---

### 🆕 Built-in Functions Library (v1.7.0)

**24 built-in functions** for data transformation and validation in GRL rules:

```sql
-- Email validation with built-in function
SELECT run_rule_engine(
    '{"Customer": {"email": "user@example.com", "approved": false}}',
    'rule "ValidEmail" {
        when IsValidEmail(Customer.email) == true
        then Customer.approved = true;
    }'
);

-- Date-based rules
SELECT run_rule_engine(
    '{"Order": {"createdAt": "2024-01-01", "isExpired": false}}',
    'rule "CheckAge" {
        when DaysSince(Order.createdAt) > 90
        then Order.isExpired = true;
    }'
);

-- Math operations
SELECT run_rule_engine(
    '{"Order": {"price1": 10.5, "price2": 99.99, "hasLowPrice": false}}',
    'rule "CheckPrice" {
        when Min(Order.price1, Order.price2) < 15.0
        then Order.hasLowPrice = true;
    }'
);
```

**Available Functions:**
- **Date/Time (5):** `DaysSince`, `AddDays`, `FormatDate`, `Now`, `Today`
- **String (8):** `IsValidEmail`, `Contains`, `RegexMatch`, `ToUpper`, `ToLower`, `Trim`, `Length`, `Substring`
- **Math (7):** `Round`, `Abs`, `Min`, `Max`, `Floor`, `Ceil`, `Sqrt`
- **JSON (4):** `JsonParse`, `JsonStringify`, `JsonGet`, `JsonSet`

**List all functions:**
```sql
SELECT * FROM rule_function_list();

```

---

### Rule Execution Modes

#### Forward Chaining (Traditional Rules)
Execute rules that modify facts based on conditions:
```sql
-- Save rule for reuse
SELECT rule_save(
    'vip_discount',
    'rule "VIP" { when Customer.tier == "VIP" && Order.total > 100
                  then Order.discount = 0.20; }',
    '1.0.0', 'VIP discount rule', 'Initial'
);

-- Execute by name (clean, no GRL text)
SELECT rule_execute_by_name(
    'vip_discount',
    '{"Customer": {"tier": "VIP"}, "Order": {"total": 200, "discount": 0}}'
)::jsonb;
```

#### Backward Chaining (Goal Queries)
Check if a goal can be proven with full reasoning trace:
```sql
-- Can this user vote?
SELECT query_backward_chaining(
    '{"User": {"age": 25}}',
    'rule "Vote" { when User.age >= 18 then User.canVote = true; }',
    'User.canVote == true'
)::jsonb;

-- Returns: {"provable": true, "proof_trace": "Vote", ...}
```

---

### Rule Repository & Versioning

Manage rules like code with semantic versioning:

```sql
-- Save with auto-versioning (1.0.0)
SELECT rule_save('pricing', 'rule "Discount" { when Order.total > 50 then Order.discount = 0.10; }', NULL, 'Pricing rules', 'Initial');

-- Update to version 2.0.0
SELECT rule_save('pricing', 'rule "NewDiscount" { when Order.total > 100 then Order.discount = 0.20; }', '2.0.0', 'Updated pricing', 'Raised limits');

-- Activate version 2.0.0
SELECT rule_activate('pricing', '2.0.0');

-- Tag for organization
SELECT rule_tag_add('pricing', 'production');

-- Execute (uses active version)
SELECT rule_execute_by_name('pricing', '{"Order": {"total": 150, "discount": 0}}');
```

**Features:**
- ✅ Semantic versioning (MAJOR.MINOR.PATCH)
- ✅ Auto-increment version with NULL
- ✅ Tagging system for organization
- ✅ Audit trail of all changes
- ✅ Safe deletion (can't delete active version)

---

### Event Triggers (Auto-Execute Rules)

Automatically execute rules when tables change:

```sql
-- Create trigger
SELECT rule_trigger_create(
    'order_discount',      -- Trigger name
    'orders',              -- Table name
    'discount_rule',       -- Rule name
    'INSERT'               -- Event type
);

-- Now every INSERT to 'orders' automatically applies discount_rule!

-- Monitor performance
SELECT * FROM rule_trigger_stats;

-- View execution history
SELECT * FROM rule_trigger_history(1);  -- trigger_id = 1
```

---

### Webhook Support (HTTP Callouts)

Send data to external APIs from rules:

```sql
-- Register webhook
SELECT rule_webhook_register(
    'slack_notify',
    'https://hooks.slack.example.com/webhook',
    'POST',
    '{"Content-Type": "application/json"}'::JSONB,
    'Slack notifications',
    10000,  -- 10s timeout
    5       -- max retries
);

-- Call it
SELECT rule_webhook_call(
    1,
    '{"text": "High CPU alert", "severity": "warning"}'::JSONB
);

-- Monitor
SELECT * FROM webhook_status_summary;
```

---

### 🆕 NATS Message Queue Integration (v1.8.0)

**High-performance message streaming** with NATS JetStream for webhook event distribution:

```sql
-- Step 1: Configure NATS connection
SELECT rule_nats_configure(
    'production',                -- config_name
    'nats://nats-cluster:4222',  -- nats_url
    'none',                      -- auth_type (none, token, nkey, credentials)
    true,                        -- jetstream_enabled
    'WEBHOOKS',                  -- stream_name
    'webhooks.events'            -- subject_prefix
);

-- Step 2: Test connection
SELECT rule_nats_test_connection('production');

-- Step 3: Enable NATS for webhook (hybrid mode)
SELECT rule_webhook_enable_nats(
    1,                          -- webhook_id
    'webhooks.events.orders',   -- nats_subject
    'both',                     -- publish_mode: queue | nats | both
    'production'                -- config_name
);

-- Step 4: Monitor NATS stats
SELECT * FROM rule_nats_stats();
SELECT * FROM rule_nats_webhooks_list();
```

**Features:**
- 🚀 **100K+ msg/sec** throughput vs 1K msg/sec with PostgreSQL queue
- 🔄 **Three publishing modes**: queue-only (legacy), NATS-only (fast), hybrid (both)
- ⚡ **Connection pooling** with round-robin load balancing (10 connections default)
- 📦 **JetStream persistence** with message acknowledgments and deduplication
- 🎯 **Queue groups** for automatic load balancing across workers
- 📊 **Real-time monitoring** with performance dashboards
- 🔒 **Enterprise security** with TLS, authentication (Token, NKey, Credentials)
- 🐳 **Production-ready** with Docker Compose and Kubernetes deployment guides

**Worker Examples:**
- [Node.js Worker](examples/nats-workers/nodejs/) - Production-ready with auto-reconnect
- [Go Worker](examples/nats-workers/go/) - High-performance concurrent processing
- [Integration Examples](examples/nats-integration/) - Fan-out, load balancing, hybrid mode

**📚 Complete NATS Documentation:**
- **[🚀 NATS Integration Guide](docs/NATS_INTEGRATION.md)** - Complete setup and usage guide
- **[📦 Migration Guide](docs/MIGRATION_GUIDE.md)** - Migrate from queue to NATS (zero-downtime)
- **[🐳 Production Deployment](docs/PRODUCTION.md)** - Docker, Kubernetes, HA setup

---

### External Data Sources (API Integration)

Fetch data from external REST APIs in your rules with automatic encryption:

```sql
-- Register external API
SELECT rule_datasource_register(
    'fraud_api',
    'https://api.fraud-check.example.com',
    'api_key',
    '{"Content-Type": "application/json"}'::JSONB,
    'Fraud detection API',
    5000,   -- 5s timeout
    300     -- 5min cache TTL
);

-- Set API credentials (automatically encrypted with AES-256)
SELECT rule_datasource_auth_set(1, 'api_key', 'your-secret-key');
-- ✅ Credential stored encrypted using pgcrypto

-- Verify encryption
SELECT * FROM datasource_encryption_audit;
-- Shows: encrypted_preview: "ww0EBwMC..." (encrypted blob)

-- Fetch data (credentials auto-decrypted, with caching)
SELECT rule_datasource_fetch(
    1,
    '/v1/score/customer123',
    '{}'::JSONB
);

-- Monitor performance
SELECT * FROM datasource_status_summary;
SELECT * FROM datasource_cache_stats;
```

**Features:**
- 🔐 **AES-256 Encryption** - Credentials encrypted at rest with pgcrypto
- 🚀 Built-in LRU caching (85%+ hit rate)
- 🔄 Automatic retry with exponential backoff
- 📊 Performance monitoring views
- ⚡ Connection pooling (10 idle/host)
- 🔑 Transparent encryption/decryption

---

## 📚 Documentation

### Getting Started
- **[📖 Quick Start (5 min)](docs/QUICKSTART.md)** - Your first rule in 5 minutes
- **[📦 Installation Guide](docs/INSTALLATION.md)** - Step-by-step for all platforms
- **[⬆️ Upgrade Guide](docs/UPGRADE.md)** - Upgrade from older versions
- **[🔧 Troubleshooting](docs/TROUBLESHOOTING.md)** - Fix common issues

### User Guides
- **[📘 Usage Guide](docs/USAGE_GUIDE.md)** - Complete feature walkthrough
- **[🎯 Backward Chaining](docs/guides/backward-chaining.md)** - Goal-driven reasoning
- **[📡 Webhooks](docs/WEBHOOKS.md)** - HTTP callouts and retry logic
- **[🚀 NATS Integration Guide](docs/NATS_INTEGRATION.md)** - High-performance message streaming
- **[📦 NATS Migration Guide](docs/MIGRATION_GUIDE.md)** - Migrate from queue to NATS (zero-downtime)
- **[🐳 NATS Production Deployment](docs/PRODUCTION.md)** - Docker, Kubernetes, HA setup
- **[🔌 External Data Sources](docs/EXTERNAL_DATASOURCES.md)** - Fetch data from REST APIs
- **[🔐 Credential Encryption](docs/CREDENTIAL_ENCRYPTION_GUIDE.md)** - AES-256 encryption guide
- **[⚡ Data Sources Quick Reference](DATASOURCE_QUICK_REFERENCE.md)** - 5-minute cheat sheet
- **[💼 Use Case: Fraud Detection](docs/USE_CASE_WEBHOOKS_DATASOURCES.md)** - Real-world example
- **[🧪 Testing Framework](docs/PHASE2_DEVELOPER_EXPERIENCE.md)** - Test rules with assertions

### Reference
- **[🔍 API Reference](docs/api-reference.md)** - All functions and syntax
- **[💡 Use Cases](docs/examples/use-cases.md)** - Real-world examples
- **[🔗 Integration Patterns](docs/integration-patterns.md)** - Triggers, JSONB, performance
- **[📊 Data Source Functions](docs/EXTERNAL_DATASOURCES.md#functions)** - Complete datasource API

### Performance & Testing
- **[⚡ Load Test Results](load-tests/QUICK_RESULTS.md)** - Performance benchmarks (NEW!)
- **[📊 Detailed Benchmark Report](load-tests/BENCHMARK_RESULTS.md)** - Complete analysis
- **[🧪 Load Testing Suite](load-tests/)** - Run your own tests

### Development
- **[🏗️ Build from Source](docs/deployment/build-from-source.md)** - Manual build instructions
- **[🐳 Docker Deployment](docs/deployment/docker.md)** - Docker and Compose
- **[🗺️ Roadmap](docs/ROADMAP.md)** - Future plans

---

## 💼 Real-World Examples

### E-Commerce Dynamic Pricing
```sql
SELECT rule_save('ecommerce', '
    rule "Gold" salience 10 {
        when Customer.tier == "Gold" && Order.items >= 10
        then Order.discount = 0.15;
    }
    rule "Bulk" salience 5 {
        when Order.items >= 20
        then Order.discount = 0.20;
    }
', '1.0.0', 'E-commerce pricing', 'Tiered discounts');

SELECT rule_execute_by_name('ecommerce',
    '{"Customer": {"tier": "Gold"}, "Order": {"items": 12, "discount": 0}}'
)::jsonb;
-- Returns: {"Customer": {"tier": "Gold"}, "Order": {"items": 12, "discount": 0.15}}
```

**More examples:**
- [Banking: Loan Approval](docs/examples/use-cases.md#2-banking-loan-approval-automation)
- [SaaS: Usage-Based Billing](docs/examples/use-cases.md#3-saas-usage-based-billing-tiers)
- [Insurance: Claims Auto-Approval](docs/examples/use-cases.md#4-insurance-claims-auto-approval)
- [Healthcare: Risk Assessment](docs/examples/use-cases.md#5-healthcare-patient-risk-assessment)

---

## 🎨 GRL Syntax Quick Reference

```grl
rule "RuleName" [salience N] [no-loop] [lock-on-active] {
    when
        [conditions with &&, ||, !, ==, !=, >, >=, <, <=]
    then
        [actions];
}
```

**Example:**
```grl
rule "VIPDiscount" salience 10 {
    when
        Order.total > 100 && Customer.tier == "Gold"
    then
        Order.discount = 0.15;
        Order.status = "approved";
}
```

**Usage:**
```sql
SELECT run_rule_engine(
    '{"Order": {"total": 200, "discount": 0, "status": "pending"}, "Customer": {"tier": "Gold"}}',
    'rule "VIPDiscount" salience 10 {
        when Order.total > 100 && Customer.tier == "Gold"
        then Order.discount = 0.15; Order.status = "approved";
    }'
)::jsonb;
```

**📚 Full syntax guide:** [GRL Reference](docs/api-reference.md#grl-syntax-reference)

---

## ⚡ Performance

**Latest Benchmark Results** (PostgreSQL 17.7 on Apple Silicon)

| Scenario | Rules | Latency | Throughput | Status |
|----------|-------|---------|------------|--------|
| Simple rule (1 condition) | 1 | **0.1ms** | **48,589 TPS** | ⭐⭐⭐⭐⭐ |
| Complex rules (multiple conditions) | 4 | **5.5ms** | **1,802 TPS** | ⭐⭐⭐⭐⭐ |
| Enterprise ruleset | 100 | **162ms** | **62 TPS** | ⭐⭐⭐⭐ |
| Extreme batch processing | 500 | **420ms** | **12 TPS** | ⭐⭐⭐⭐ |
| Backward chaining query | 1-5 | 2-3ms | 333-500 TPS | ⭐⭐⭐⭐⭐ |

**Key Findings:**
- ✅ **48,589 TPS** for simple rules - **38x faster** than expected
- ✅ **Sub-linear scaling** - 500 rules = only 0.84ms per rule
- ✅ **0% failure rate** across 505,559 test transactions
- ✅ **Production-ready** for all use cases

📊 **[View Full Benchmark Report →](load-tests/BENCHMARK_RESULTS.md)**

---

## 🚀 What's New

### 🆕 PostgreSQL 18 Support

**✅ Fully tested and production-ready on PostgreSQL 18!**

All features and performance benchmarks have been validated on PostgreSQL 18.1:
- **Simple Rules**: 1,463 TPS (17-83% above target)
- **Complex Rules**: 564 TPS (19-61% above target)
- **Repository Execute**: 34,359 TPS (extremely high performance!)
- **Datasource Fetch**: 28,568 TPS (27-56x above target!)

Supports PostgreSQL **16, 17, and 18** with identical performance characteristics.

---

### 🆕 v1.8.0 - NATS Message Queue Integration

**High-performance message streaming** for webhook event distribution with NATS JetStream!

- **🚀 100x Performance Boost**: 100K+ msg/sec vs 1K msg/sec with PostgreSQL queue
- **🔄 Three Publishing Modes**: queue-only (legacy), NATS-only (fast), hybrid (both)
- **⚡ Connection Pooling**: Round-robin load balancing across 10 connections (default)
- **📦 JetStream Persistence**: Message acknowledgments, deduplication, 7-day retention
- **🎯 Queue Groups**: Automatic load balancing across multiple workers
- **📊 Real-time Monitoring**: Performance dashboards and health checks
- **🔒 Enterprise Security**: TLS, authentication (Token, NKey, Credentials)
- **🐳 Production Ready**: Docker Compose + Kubernetes deployment guides

```sql
-- Quick start
SELECT rule_nats_configure('production', 'nats://localhost:4222', 'none', true, 'WEBHOOKS', 'webhooks.events');
SELECT rule_webhook_enable_nats(1, 'webhooks.events.orders', 'both', 'production');
```

**📚 Documentation:**
- [NATS Integration Guide](docs/NATS_INTEGRATION.md) - Complete setup and usage
- [Migration Guide](docs/MIGRATION_GUIDE.md) - Zero-downtime migration from queue
- [Production Deployment](docs/PRODUCTION.md) - Docker, Kubernetes, HA setup

**Worker Examples:**
- [Node.js Worker](examples/nats-workers/nodejs/) - Production-ready with auto-reconnect
- [Go Worker](examples/nats-workers/go/) - High-performance concurrent processing

---

### v1.6.0 - External Data Sources

**🔌 Fetch Data from REST APIs**

**NEW:** Integrate external APIs directly in your rules with built-in caching and retry logic!

- **🚀 LRU Caching**: Automatic 85%+ cache hit rate reduces API costs
- **🔄 Auto Retry**: Exponential backoff for failed requests
- **🔐 Auth Management**: Support for API Key, Bearer, Basic, OAuth2
- **⚡ Connection Pooling**: Reuse HTTP connections (10 idle/host)
- **📊 Monitoring**: Performance stats, cache analytics, failure tracking

```sql
-- Register external API
SELECT rule_datasource_register(
    'fraud_api', 'https://api.fraud-check.example.com',
    'api_key', '{"Content-Type": "application/json"}'::JSONB
);

-- Fetch data (cached automatically)
SELECT rule_datasource_fetch(1, '/v1/score/customer123', '{}'::JSONB);

-- Monitor
SELECT * FROM datasource_status_summary;
SELECT * FROM datasource_cache_stats;
```

**📚 Documentation:**
- [External Data Sources Guide](docs/EXTERNAL_DATASOURCES.md)
- [Use Case: Fraud Detection](docs/USE_CASE_WEBHOOKS_DATASOURCES.md)

### 📡 Webhook Support (v1.5.0)

Send HTTP callouts from rules:
- HTTP endpoints with retry logic and secret management
- [Webhooks Guide](docs/WEBHOOKS.md)

---

## 🛠️ API Reference (Quick)

### Forward Chaining
- `run_rule_engine(facts TEXT, rules TEXT) → TEXT` - Execute rules inline
- `rule_execute_by_name(name TEXT, facts TEXT, version TEXT) → TEXT` - Execute saved rule

### Backward Chaining
- `query_backward_chaining(facts TEXT, rules TEXT, goal TEXT) → JSON` - Query with proof trace
- `can_prove_goal(facts TEXT, rules TEXT, goal TEXT) → BOOLEAN` - Fast boolean check

### Rule Repository
- `rule_save(name, grl, version, desc, notes) → INT` - Save rule (NULL for auto-version)
- `rule_get(name, version) → TEXT` - Get GRL content
- `rule_activate(name, version) → BOOLEAN` - Set default version
- `rule_delete(name, version) → BOOLEAN` - Delete version
- `rule_tag_add/remove(name, tag) → BOOLEAN` - Manage tags

### Utilities
- `rule_engine_version() → TEXT` - Get extension version
- `rule_engine_health_check() → TEXT` - Health status

**📚 Complete API:** [API Reference](docs/api-reference.md)

---

## 🐛 Troubleshooting

**Common issues:**

| Error | Solution |
|-------|----------|
| Extension not found | `sudo dpkg -i postgresql-16-rule-engine_*.deb && sudo systemctl restart postgresql` |
| Permission denied | `sudo chmod 755 /usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so` |
| Invalid JSON | Validate with `'{"key":"value"}'::jsonb` |
| Version exists | Use different version or NULL for auto-increment |

**📚 Full guide:** [Troubleshooting](docs/TROUBLESHOOTING.md)

---

## 🤝 Contributing

Contributions welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md).


## 📞 Support

- **📖 Documentation**: [docs/](docs/)
- **🐛 Bug Reports**: [GitHub Issues](https://github.com/KSD-CO/rule-engine-postgres/issues)
- **💬 Questions**: [GitHub Discussions](https://github.com/KSD-CO/rule-engine-postgres/discussions)
- **📧 Security**: Email maintainer (see below)

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Built with [pgrx](https://github.com/pgcentralfoundation/pgrx) v0.16.1 - PostgreSQL extension framework
- Powered by [rust-rule-engine](https://crates.io/crates/rust-rule-engine) v1.8 with backward-chaining
- Inspired by Drools and Grule

---

## 🏗️ Architecture

```
src/
├── api/                       # Public API functions
│   ├── engine.rs              # Forward chaining execution
│   ├── backward.rs            # Backward chaining queries
│   ├── triggers.rs            # Event triggers
│   ├── rulesets.rs            # Rule sets
│   ├── datasources.rs         # External data source API
│   ├── nats.rs                # NATS integration API (v1.8.0)
│   ├── stats.rs               # Performance statistics
│   └── health.rs              # Health check endpoints
├── repository/                # Rule repository & versioning
│   ├── queries.rs             # CRUD operations
│   ├── models.rs              # Data structures
│   ├── version.rs             # Semantic versioning
│   ├── validation.rs          # Repository validation
│   └── test_spi.rs            # Testing framework
├── core/                      # Rule engine core
│   ├── executor.rs            # Forward chaining execution
│   ├── backward.rs            # Backward chaining logic
│   ├── rules.rs               # GRL parsing & compilation
│   └── facts.rs               # Fact management
├── nats/                      # NATS JetStream integration (v1.8.0)
│   ├── config.rs              # NATS configuration & auth
│   ├── publisher.rs           # JetStream publisher
│   ├── pool.rs                # Connection pooling
│   ├── models.rs              # NATS data models
│   ├── error.rs               # NATS error types
│   └── tests/                 # Unit tests
│       ├── config_tests.rs    # Configuration tests
│       ├── error_tests.rs     # Error handling tests
│       └── pool_tests.rs      # Connection pool tests
├── datasources/               # External API integration (v1.6.0)
│   ├── client.rs              # HTTP client & connection pooling
│   └── models.rs              # Data source models
├── validation/                # Input validation & limits
│   ├── input.rs               # JSON/GRL validation
│   └── limits.rs              # Resource limits
└── error/                     # Error handling
    └── codes.rs               # Error codes & messages
```

---

**Version**: 1.8.0 | **Status**: Production Ready ✅ | **Maintainer**: Ton That Vu

---

**Made with ❤️ using Rust and PostgreSQL**
