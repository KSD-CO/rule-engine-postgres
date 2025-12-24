# rule-engine-postgres

[![CI](https://github.com/KSD-CO/rule-engine-postgres/actions/workflows/ci.yml/badge.svg)](https://github.com/KSD-CO/rule-engine-postgres/actions)
[![Version](https://img.shields.io/badge/version-1.8.0-blue.svg)](https://github.com/KSD-CO/rule-engine-postgres/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Performance](https://img.shields.io/badge/Performance-48.5k_TPS-brightgreen.svg)](load-tests/BENCHMARK_RESULTS.md)
[![Benchmark](https://img.shields.io/badge/Benchmark-0.1ms_latency-success.svg)](load-tests/QUICK_RESULTS.md)

PostgreSQL extension that brings rule engine capabilities with **24 built-in functions** and **NATS JetStream integration** directly into your database. Execute complex business logic using GRL (Grule Rule Language) with forward chaining, backward chaining, and full rule versioning support.

> **⚡ NEW: Benchmark Results Available!**
> **48,589 TPS** (0.1ms latency) for simple rules | **1,802 TPS** for complex rules | **12 TPS** for 500-rule batch processing
> 📊 [View Full Benchmark Report](load-tests/BENCHMARK_RESULTS.md) | [Quick Results](load-tests/QUICK_RESULTS.md)

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
# Prerequisites: Rust 1.75+, PostgreSQL 16-17
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
SELECT rule_engine_version();  -- Returns: 1.7.0
```

**Note:** The `pgcrypto` extension is required for credential encryption in External Data Sources (v1.6.0+).

---

### 3. Run Your First Rule

```sql
-- Simple discount rule
SELECT run_rule_engine(
    '{"Order": {"total": 150, "discount": 0}}',
    'rule "Discount" {
        when Order.total > 100
        then Order.discount = Order.total * 0.10;
    }'
)::jsonb;

-- Result: {"Order": {"total": 150, "discount": 15}}
```

✅ **Done!** You just executed your first business rule.

**📚 More examples:** [Quick Start Guide](docs/QUICKSTART.md)

---

## ⭐ Why Use This?

| Feature | Benefit |
|---------|---------|
| **🚀 No Microservices** | Business rules run directly in PostgreSQL - no external services |
| **⚡ High Performance** | Sub-millisecond execution (48,589 TPS for simple rules) |
| **🎯 Dual Reasoning** | Forward chaining (data-driven) + Backward chaining (goal-driven) |
| **📦 Rule Repository** | Version control, tagging, and activation management |
| **🔄 Dynamic Logic** | Change business rules without code deployment |
| **🔒 Transaction Safe** | Rules execute within PostgreSQL transactions |
| **🚀 NATS Integration** | 100K+ msg/sec throughput with JetStream persistence (NEW in v1.8.0) |

---

## 🎯 Core Features

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
    '{"Customer": {"tier": "VIP"}, "Order": {"total": 200}}'
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
SELECT rule_save('pricing', 'rule "Discount" { ... }', NULL, 'Pricing rules', 'Initial');

-- Update to version 2.0.0
SELECT rule_save('pricing', 'rule "NewDiscount" { ... }', '2.0.0', 'Updated pricing', 'Raised limits');

-- Activate version 2.0.0
SELECT rule_activate('pricing', '2.0.0');

-- Tag for organization
SELECT rule_tag_add('pricing', 'production');

-- Execute (uses active version)
SELECT rule_execute_by_name('pricing', '{"Order": {"total": 100}}');
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
-- Configure NATS connection
SELECT rule_nats_config_create(
    'production',
    'nats://nats-cluster:4222',
    '{"jetstream_enabled": true, "max_connections": 10}'::JSONB,
    'Production NATS cluster'
);

-- Initialize NATS publisher
SELECT rule_nats_init('production');

-- Enable NATS for webhook (hybrid mode)
SELECT rule_webhook_enable_nats(
    1,                          -- webhook_id
    'production',               -- config_name
    'webhooks.events.orders',   -- subject
    'both'                      -- publish_mode: queue | nats | both
);

-- Publish to NATS
SELECT rule_webhook_publish_nats(
    1,
    '{"event": "order.created", "order_id": 12345}'::JSONB
);

-- Monitor NATS health
SELECT * FROM nats_monitoring_dashboard;
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
    '{"Customer": {"tier": "Gold"}, "Order": {"items": 12}}'
)::jsonb;
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
SELECT rule_nats_init('production');
SELECT rule_webhook_enable_nats(1, 'production', 'webhooks.events', 'both');
SELECT rule_webhook_publish_nats(1, '{"event": "order.created"}'::JSONB);
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
