# rule-engine-postgres

[![CI](https://github.com/KSD-CO/rule-engine-postgres/actions/workflows/ci.yml/badge.svg)](https://github.com/KSD-CO/rule-engine-postgres/actions)
[![Version](https://img.shields.io/badge/version-1.2.0-blue.svg)](https://github.com/KSD-CO/rule-engine-postgres/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Production-ready** PostgreSQL extension written in Rust that brings rule engine capabilities directly into your database. Execute complex business logic using GRL (Grule Rule Language) syntax with **forward chaining**, **backward chaining**, and **rule versioning** support.

## Why Use This?

- **No Microservices Overhead**: Business rules run directly in PostgreSQL
- **Real-time Decisions**: Sub-millisecond rule execution (~1000 rules/sec)
- **Dual Reasoning Modes**: Forward chaining (data-driven) + Backward chaining (goal-driven)
- **Rule Repository**: Store, version, and manage rules with full audit trail ⭐ NEW
- **Dynamic Logic**: Change business rules without code deployment
- **Transaction Safety**: Rules execute within PostgreSQL transactions

## Features

- ⚡ **High Performance**: Compiled Rust code, optimized for speed
- 🎯 **Backward Chaining**: Goal queries with proof traces ("Can we prove X?")
- 🔀 **Forward Chaining**: Event-driven rule execution (traditional)
- 📦 **Rule Repository**: Version control, tagging, and activation management ⭐ NEW
- 🔔 **Event Triggers**: Automatic rule execution on table changes (INSERT/UPDATE/DELETE) ⭐ NEW
- 🔒 **Production Ready**: Error codes, health checks, Docker support, CI/CD
- 📦 **Easy Deploy**: One-liner install or pre-built packages
- 🔧 **Flexible**: JSON/JSONB support, triggers, nested objects
- 🛡️ **Type Safe**: Leverages Rust's type system for reliability
- 📊 **Observable**: Health checks, structured errors, monitoring-ready

## Quick Start

### Option 1: Quick Install (Recommended)

```bash
# One-liner install (Ubuntu/Debian)
curl -fsSL https://raw.githubusercontent.com/KSD-CO/rule-engine-postgres/main/quick-install.sh | bash

# Enable extension
sudo -u postgres psql -d your_database -c "CREATE EXTENSION rule_engine_postgre_extensions;"
sudo -u postgres psql -d your_database -c "SELECT rule_engine_version();"
```

### Option 2: Pre-built Package

**Ubuntu/Debian:**
```bash
wget https://github.com/KSD-CO/rule-engine-postgres/releases/download/v1.0.0/postgresql-16-rule-engine_1.0.0_amd64.deb
sudo dpkg -i postgresql-16-rule-engine_1.0.0_amd64.deb
```

**PGXN:**
```bash
pgxn install rule_engine_postgre_extensions
```

### Option 3: Docker

```bash
git clone https://github.com/KSD-CO/rule-engine-postgres.git
cd rule-engine-postgres
cp .env.example .env
docker-compose up -d

# Verify
docker-compose exec postgres psql -U postgres -d ruleengine \
  -c "SELECT rule_engine_health_check();"
```

### Option 4: Build from Source

```bash
# Prerequisites: Rust 1.75+, PostgreSQL 16-17
cargo install cargo-pgrx --version 0.16.1 --locked
git clone https://github.com/KSD-CO/rule-engine-postgres.git
cd rule-engine-postgres
./install.sh
```

---

## Usage

### Forward Chaining (Data-Driven)

Execute rules that modify facts based on conditions.

**Option 1: Using Stored Rules (v1.1.0+)** ⭐ RECOMMENDED

```sql
-- Save rule once
SELECT rule_save(
    'check_age_rule',
    'rule "CheckAge" salience 10 {
        when User.age > 18
        then User.status = "adult";
    }',
    '1.0.0',
    'Age verification rule',
    'Initial version'
);

-- Execute many times (clean, no GRL text)
SELECT rule_execute_by_name(
    'check_age_rule',
    '{"User": {"age": 30, "status": "active"}}',
    NULL
);
-- Returns: {"User": {"age": 30, "status": "adult"}}
```

**Option 2: Inline Rules (Legacy)**

```sql
SELECT run_rule_engine(
    '{"User": {"age": 30, "status": "active"}}',
    'rule "CheckAge" salience 10 {
        when User.age > 18
        then User.status = "adult";
    }'
);
-- Returns: {"User": {"age": 30, "status": "adult"}}
```

### Backward Chaining (Goal-Driven) ⭐ NEW

Query if a goal can be proven with full reasoning trace.

**Option 1: Using Stored Rules (v1.1.0+)** ⭐ RECOMMENDED

```sql
-- Save rule once
SELECT rule_save(
    'age_check_rules',
    'rule "AgeCheck" {
        when User.Age >= 18
        then User.IsAdult = true;
    }',
    '1.0.0',
    'Age verification rules',
    'Initial version'
);

-- Query goal with proof trace
SELECT rule_query_by_name(
    'age_check_rules',
    '{"User": {"Age": 25}}',
    'User.IsAdult == true',
    NULL
)::jsonb;
-- Returns: {"provable": true, "proof_trace": "AgeCheck", ...}

-- Fast boolean check (production)
SELECT rule_can_prove_by_name(
    'age_check_rules',
    '{"User": {"Age": 25}}',
    'User.IsAdult == true',
    NULL
);
-- Returns: true
```

**Option 2: Inline Rules (Legacy)**

```sql
-- Simple goal query
SELECT query_backward_chaining(
    '{"User": {"Age": 25}}',
    'rule "AgeCheck" {
        when User.Age >= 18
        then User.IsAdult = true;
    }',
    'User.IsAdult == true'
)::jsonb;

-- Returns:
-- {
--   "provable": true,
--   "proof_trace": "AgeCheck",
--   "goals_explored": 1,
--   "rules_evaluated": 1,
--   "query_time_ms": 0.85
-- }

-- Fast boolean check (production mode)
SELECT can_prove_goal(
    '{"Order": {"Total": 100}}',
    'rule "Valid" { when Order.Total > 0 then Order.Valid = true; }',
    'Order.Valid == true'
);
-- Returns: true

-- Multiple goals in one query
SELECT query_backward_chaining_multi(
    '{"User": {"Age": 25}}',
    'rule "Vote" { when User.Age >= 18 then User.CanVote = true; }
     rule "Retire" { when User.Age >= 65 then User.CanRetire = true; }',
    ARRAY['User.CanVote == true', 'User.CanRetire == true']
)::jsonb;

-- Returns array of results for each goal
```

### Event Triggers (Automatic Execution) ⭐ NEW

Automatically execute rules when database tables change.

```sql
-- 1. Create orders table
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INT,
    total_amount NUMERIC(10, 2),
    discount_amount NUMERIC(10, 2) DEFAULT 0,
    final_amount NUMERIC(10, 2)
);

-- 2. Save discount rule
SELECT rule_save(
    'order_discount',
    'rule "VIPDiscount" salience 10 {
        when Order.total_amount > 100
        then Order.discount_amount = Order.total_amount * 0.1;
             Order.final_amount = Order.total_amount - Order.discount_amount;
    }',
    '1.0.0',
    'VIP customer discount',
    'Initial version'
);

-- 3. Create trigger to auto-apply discounts on INSERT
SELECT rule_trigger_create(
    'order_discount_trigger',
    'orders',
    'order_discount',
    'INSERT'
);

-- 4. Insert orders - discount applied automatically!
INSERT INTO orders (customer_id, total_amount)
VALUES (1, 150.00);

SELECT * FROM orders;
-- Returns:
-- id | customer_id | total_amount | discount_amount | final_amount
--  1 |           1 |       150.00 |           15.00 |       135.00

-- 5. View execution history
SELECT * FROM rule_trigger_history(1);  -- trigger_id = 1

-- 6. View trigger statistics
SELECT * FROM rule_trigger_stats;

-- 7. Disable/enable trigger
SELECT rule_trigger_enable(1, FALSE);  -- Disable
SELECT rule_trigger_enable(1, TRUE);   -- Re-enable

-- 8. Clean up
SELECT rule_trigger_delete(1);
```
```

**When to use each mode:**
- **Forward Chaining**: Event processing, data enrichment, monitoring
- **Backward Chaining**: Eligibility checks, diagnosis, decision explanation

---

## Rule Repository & Versioning ⭐ NEW

Store and manage rules with semantic versioning, tags, and activation control.

### Save Rules with Versioning

```sql
-- Save a new rule (auto-versioned as 1.0.0)
SELECT rule_save(
    'discount_rules',                                    -- Rule name
    'rule HighValue "20% discount" {                     -- GRL content
        when Customer.orderTotal > 1000
        then Customer.discount = 0.20;
    }',
    NULL,                                                -- Auto version
    'Discount rules for high-value customers',          -- Description
    'Initial version'                                    -- Change notes
);
-- Returns: 1 (rule_id)

-- Save version 2.0.0 with updated logic
SELECT rule_save(
    'discount_rules',
    'rule HighValue "25% discount for premium" {
        when Customer.orderTotal > 2000
        then Customer.discount = 0.25;
    }',
    '2.0.0',                                             -- Explicit version
    'Increased discount threshold',
    'Raised to 2000 and 25% discount'
);
```

### Retrieve and Execute Rules

```sql
-- Get rule by name (uses default version)
SELECT rule_get('discount_rules', NULL);

-- Get specific version
SELECT rule_get('discount_rules', '1.0.0');

-- Execute stored rule by name (forward chaining)
SELECT rule_execute_by_name(
    'discount_rules',
    '{"Customer": {"orderTotal": 2500}}',
    NULL  -- Uses default version
);
-- Returns: {"Customer": {"discount": 0.25, "orderTotal": 2500}}

-- Query goal with backward chaining
SELECT rule_query_by_name(
    'eligibility_rules',
    '{"User": {"Age": 25}}',
    'User.CanVote == true',
    NULL
)::jsonb;
-- Returns: {"provable": true, "proof_trace": "VoteAge", ...}

-- Fast boolean check
SELECT rule_can_prove_by_name(
    'eligibility_rules',
    '{"User": {"Age": 25}}',
    'User.CanRetire == true',
    NULL
);
-- Returns: false
```

### Version Management

```sql
-- Activate a different version as default
SELECT rule_activate('discount_rules', '2.0.0');

-- Add tags for organization
SELECT rule_tag_add('discount_rules', 'production');
SELECT rule_tag_add('discount_rules', 'billing');

-- Remove tag
SELECT rule_tag_remove('discount_rules', 'billing');

-- Delete old version (cannot delete default)
SELECT rule_delete('discount_rules', '1.0.0');

-- View all versions
SELECT * FROM rule_versions WHERE rule_id = 
    (SELECT id FROM rule_definitions WHERE name = 'discount_rules');

-- View tags
SELECT * FROM rule_tags WHERE rule_id = 
    (SELECT id FROM rule_definitions WHERE name = 'discount_rules');
```

### Database Schema

The Rule Repository uses 4 tables:

- **`rule_definitions`**: Master rule records with metadata
- **`rule_versions`**: Version history with GRL content (semantic versioning)
- **`rule_tags`**: Tags for categorization and filtering
- **`rule_audit_log`**: Automatic audit trail of all changes

**Features:**
- ✅ Semantic versioning (MAJOR.MINOR.PATCH)
- ✅ Single default version enforcement (via trigger)
- ✅ Automatic audit logging
- ✅ Tag-based organization
- ✅ Protection against deleting default versions
- ✅ Created/updated timestamps and user tracking

```sql
-- Run migration to create schema
\i migrations/001_rule_repository.sql
```

---

## Real-World Examples

### Quick Examples

- **E-Commerce**: Dynamic pricing based on cart value, customer loyalty ([see full example](docs/examples/use-cases.md#1-e-commerce-dynamic-pricing-engine))
- **Banking**: Automated loan approval based on credit score ([see full example](docs/examples/use-cases.md#2-banking-loan-approval-automation))
- **SaaS**: Usage-based billing tier calculation ([see full example](docs/examples/use-cases.md#3-saas-usage-based-billing-tiers))
- **Insurance**: Auto-approve claims based on policy limits ([see full example](docs/examples/use-cases.md#4-insurance-claims-auto-approval))
- **Healthcare**: Patient risk assessment for early intervention ([see full example](docs/examples/use-cases.md#5-healthcare-patient-risk-assessment))
- **Backward Chaining**: Loan eligibility with proof trace ([see full example](docs/examples/use-cases.md#6-backward-chaining-loan-eligibility-verification))

📚 **[View all detailed examples →](docs/examples/use-cases.md)**

---

## API Reference

### Forward Chaining Functions

- **`run_rule_engine(facts_json TEXT, rules_grl TEXT) → TEXT`**
  Execute GRL rules on JSON facts. Max 1MB for both parameters.

### Backward Chaining Functions

- **`query_backward_chaining(facts_json TEXT, rules_grl TEXT, goal TEXT) → JSON`**
  Query if a goal can be proven with full details and proof trace.

- **`query_backward_chaining_multi(facts_json TEXT, rules_grl TEXT, goals TEXT[]) → JSON[]`**
  Query multiple goals in one call.

- **`can_prove_goal(facts_json TEXT, rules_grl TEXT, goal TEXT) → BOOLEAN`**
  Fast boolean check (2-3x faster, no proof trace).

### Rule Repository Functions ⭐ NEW

- **`rule_save(name TEXT, grl_content TEXT, version TEXT, description TEXT, change_notes TEXT) → INT`**
  Save rule with versioning. Pass NULL for version to auto-increment. Returns rule_id.

- **`rule_get(name TEXT, version TEXT) → TEXT`**
  Get GRL content. Pass NULL for version to get default version.

- **`rule_activate(name TEXT, version TEXT) → BOOLEAN`**
  Set a version as the default. Returns true on success.

- **`rule_delete(name TEXT, version TEXT) → BOOLEAN`**
  Delete a version (cannot delete default). Pass NULL to delete entire rule.

- **`rule_tag_add(name TEXT, tag TEXT) → BOOLEAN`**
  Add a tag to a rule for organization.

- **`rule_tag_remove(name TEXT, tag TEXT) → BOOLEAN`**
  Remove a tag from a rule.

- **`rule_execute_by_name(name TEXT, facts_json TEXT, version TEXT) → TEXT`**
  Execute a stored rule by name (forward chaining). Pass NULL for version to use default.

- **`rule_query_by_name(name TEXT, facts_json TEXT, goal TEXT, version TEXT) → JSON`**
  Query goal using stored rule (backward chaining with proof trace). Pass NULL for version to use default.

- **`rule_can_prove_by_name(name TEXT, facts_json TEXT, goal TEXT, version TEXT) → BOOLEAN`**
  Fast boolean check if goal is provable using stored rule. Pass NULL for version to use default.

### Utility Functions

- **`rule_engine_health_check() → TEXT`**
  Returns health status with version and timestamp.

- **`rule_engine_version() → TEXT`**
  Returns extension version ("1.1.0").

### Event Triggers Functions ⭐ NEW

- **`rule_trigger_create(name TEXT, table_name TEXT, rule_name TEXT, event_type TEXT) → INT`**
  Create trigger to execute rule automatically on INSERT/UPDATE/DELETE. Returns trigger_id.

- **`rule_trigger_enable(trigger_id INT, enabled BOOLEAN) → BOOLEAN`**
  Enable or disable a trigger. Returns true on success.

- **`rule_trigger_history(trigger_id INT, start_time TIMESTAMP, end_time TIMESTAMP) → JSON`**
  Get execution history as JSON array. Defaults to last 24 hours.

- **`rule_trigger_delete(trigger_id INT) → BOOLEAN`**
  Delete a trigger and clean up PostgreSQL trigger.

### Error Codes

| Code | Description |
|------|-------------|
| ERR001 | Empty facts JSON |
| ERR002 | Empty rules GRL |
| ERR003-004 | Input too large (max 1MB) |
| ERR005-006 | Invalid JSON format |
| ERR007-010 | Rule processing failed |
| ERR011-012 | Execution/serialization failed |

📚 **[Complete API Reference →](docs/api-reference.md)**

---

## GRL Syntax Quick Reference

```grl
rule "RuleName" [attributes] {
    when
        [conditions]
    then
        [actions];
}
```

**Operators**: `==`, `!=`, `>`, `>=`, `<`, `<=`, `&&`, `||`, `!`

**Attributes**: `salience N` (priority), `no-loop`, `lock-on-active`

**Example:**
```grl
rule "DiscountRule" salience 10 {
    when
        Order.total > 100 && Customer.tier == "Gold"
    then
        Order.discount = 0.15;
        Order.status = "approved";
}
```

📚 **[Full GRL Syntax Guide →](docs/api-reference.md#grl-syntax-reference)**

---

## Integration Patterns

### Database Triggers

```sql
CREATE OR REPLACE FUNCTION validate_with_rules()
RETURNS TRIGGER AS $$
BEGIN
    NEW.data := run_rule_engine(
        NEW.data::TEXT,
        (SELECT rules FROM rule_definitions WHERE active = TRUE)
    )::JSONB;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_order
    BEFORE INSERT OR UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION validate_with_rules();
```

### Store Rules in Database

Using the built-in Rule Repository (v1.1.0+):

```sql
-- Save rules with versioning
SELECT rule_save(
    'order_validation_rules',
    'rule "MinAmount" { when Order.amount < 10 then Order.valid = false; }
     rule "MaxAmount" { when Order.amount > 10000 then Order.needsApproval = true; }',
    '1.0.0',
    'Order validation rules',
    'Initial version'
);

-- Tag for organization
SELECT rule_tag_add('order_validation_rules', 'validation');
SELECT rule_tag_add('order_validation_rules', 'production');

-- Execute by name
SELECT rule_execute_by_name(
    'order_validation_rules',
    order_data::TEXT,
    NULL  -- Uses default version
) FROM orders WHERE status = 'pending';
```

Legacy approach (storing in your own table):

```sql
CREATE TABLE business_rules (
    rule_id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    grl_definition TEXT NOT NULL,
    priority INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Apply categorized rules
SELECT run_rule_engine(
    order_data::TEXT,
    (SELECT string_agg(grl_definition, E'\n' ORDER BY priority DESC)
     FROM business_rules WHERE is_active = TRUE)
) FROM orders WHERE status = 'pending';
```

📚 **[More Integration Patterns →](docs/integration-patterns.md)**

---

## Documentation

### 📚 GitHub Wiki (Recommended)
Complete user-friendly documentation:
- **[🏠 Wiki Home](https://github.com/KSD-CO/rule-engine-postgres/wiki)** - Start here!
- **[⚡ Quick Start](https://github.com/KSD-CO/rule-engine-postgres/wiki/Quick-Start)** - 5-minute tutorial
- **[📥 Installation Guide](https://github.com/KSD-CO/rule-engine-postgres/wiki/Installation-Guide)** - Step-by-step installation
- **[📦 Rule Repository](https://github.com/KSD-CO/rule-engine-postgres/wiki/Rule-Repository-Overview)** - Version control for rules
- **[🔍 API Reference](https://github.com/KSD-CO/rule-engine-postgres/wiki/Repository-Functions)** - Complete function docs
- **[💼 Use Cases](https://github.com/KSD-CO/rule-engine-postgres/wiki/Use-Case-ECommerce)** - Real-world examples

### 📂 Repository Docs
Technical documentation in this repo:
- **[📖 Documentation Index](docs/README.md)** - Complete documentation navigation
- **[🎯 Backward Chaining Guide](docs/guides/backward-chaining.md)** - Goal-driven reasoning guide
- **[📦 Rule Repository RFC](docs/rfcs/0001-rule-repository.md)** - Technical design for versioning ⭐ NEW
- **[💡 Use Case Examples](docs/examples/use-cases.md)** - Real-world production examples
- **[🔧 API Reference](docs/api-reference.md)** - Complete function reference
- **[🔗 Integration Patterns](docs/integration-patterns.md)** - Triggers, JSONB, performance tips
- **[🐳 Docker Deployment](docs/deployment/docker.md)** - Docker and Docker Compose
- **[🔨 Build from Source](docs/deployment/build-from-source.md)** - Manual build instructions
- **[🐛 Troubleshooting](docs/development/TROUBLESHOOTING.md)** - Common build issues and fixes
- **[📦 Distribution Guide](docs/deployment/distribution.md)** - Package distribution

---


### Forward Chaining

| Scenario | Avg Time | Throughput |
|----------|----------|------------|
| Simple rule (1 condition) | 0.8ms | 1250 rules/sec |
| Complex rule (5 conditions) | 2.1ms | 476 rules/sec |
| Nested objects (3 levels) | 1.5ms | 667 rules/sec |

### Backward Chaining ⭐ NEW

| Function | Mode | Avg Time | Use Case |
|----------|------|----------|----------|
| `query_backward_chaining` | Dev | 2-3ms | Debugging, explaining decisions |
| `query_backward_chaining_multi` | Dev | 5-8ms | Batch verification |
| `can_prove_goal` | Prod | 0.5-1ms | High-throughput checks |

---

## Contributing

Contributions welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Areas we'd love help with:**
- Additional GRL syntax examples
- Performance benchmarks
- Integration with popular frameworks (Django, Rails, etc.)
- Cloud deployment guides (AWS RDS, Google Cloud SQL, Azure)

### For Maintainers

**Pre-commit Checks:**
```bash
# Manual checks before committing
./check-before-commit.sh      # Full check (both PG 16 & 17)
./quick-check.sh               # Quick check (PG 17 only, uses cache)

# Quick fixes
cargo fmt --all                                                         # Auto-fix formatting
cargo clippy --no-default-features --features pg17 --fix -- -D warnings # Auto-fix some warnings
```

**Version Management:**
```bash
# Check current version
./version.sh

# Bump version (updates all files automatically)
./bump-version.sh 1.2.0

# Build release packages
./release.sh
```

All scripts automatically extract version from `Cargo.toml`, ensuring consistency across:
- Package names
- Release URLs
- SQL migration files
- Documentation

---

## Support

- 📖 **Documentation**: [docs/](docs/)
- 🐛 **Bug Reports**: [GitHub Issues](https://github.com/KSD-CO/rule-engine-postgres/issues)
- 💬 **Questions**: [GitHub Discussions](https://github.com/KSD-CO/rule-engine-postgres/discussions)

---

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

## Architecture

This extension is built with a clean, modular architecture:

```
src/
├── lib.rs                         # Entry point
├── api/
│   ├── health.rs                  # Health check & version
│   ├── engine.rs                  # Forward chaining API
│   └── backward.rs                # Backward chaining API
├── core/
│   ├── facts.rs                   # Facts/JSON conversion
│   ├── rules.rs                   # GRL parsing
│   ├── executor.rs                # Forward chaining logic
│   └── backward.rs                # Backward chaining logic
├── repository/                    # ⭐ NEW - Rule Repository
│   ├── queries.rs (375 lines)     # CRUD operations
│   ├── models.rs                  # Data structures
│   ├── validation.rs              # Input validation
│   └── version.rs                 # Semantic versioning
├── error/
│   ├── codes.rs                   # Error definitions
│   └── mod.rs                     # Error utilities
└── validation/
    ├── input.rs                   # Input validation
    └── limits.rs                  # Size constraints
```

**Key Features:**
- 7 Rule Repository functions (save, get, activate, delete, tag operations, execute)
- Semantic version parsing and comparison
- Database schema with 4 tables + triggers + views
- Automatic audit logging
- Production-ready error handling

---

## Acknowledgments

- Built with [pgrx](https://github.com/pgcentralfoundation/pgrx) - PostgreSQL extension framework
- Powered by [rust-rule-engine](https://crates.io/crates/rust-rule-engine) v1.7.0 (with backward-chaining feature)
- Inspired by business rule engines like Drools and Grule

---

**Version**: 1.2.0 | **Status**: Production Ready ✅ | **Maintainer**: Ton That Vu

---

## What's New in v1.2.0 ⭐

### Event Triggers Integration

Automatic rule execution when database tables change - no application code needed!

- **🔔 Auto-Execute Rules**: Trigger rules on INSERT/UPDATE/DELETE operations
- **📊 Full Audit Trail**: Track every execution with OLD/NEW data snapshots
- **⚡ High Performance**: ~1-5ms overhead per trigger execution
- **🎛️ Enable/Disable**: Control triggers without deleting them
- **📈 Real-time Stats**: Monitor performance with `rule_trigger_stats` view
- **🛡️ Error Handling**: Failures logged but don't break transactions

```sql
-- Complete workflow example
SELECT rule_trigger_create('order_discount', 'orders', 'discount_rule', 'INSERT');
-- Now every INSERT automatically applies discount rules!

SELECT * FROM rule_trigger_stats;  -- Monitor performance
SELECT rule_trigger_history(1);     -- View execution history
SELECT rule_trigger_enable(1, FALSE);  -- Disable during maintenance
```

**New Functions**: `rule_trigger_create`, `rule_trigger_enable`, `rule_trigger_history`, `rule_trigger_delete`

**Migration**: Run `migrations/002_rule_triggers.sql` or upgrade with `ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.2.0';`

---

## What's New in v1.1.0

### Rule Repository & Versioning System

Complete rule lifecycle management directly in PostgreSQL:

- **📦 Semantic Versioning**: MAJOR.MINOR.PATCH with automatic incrementing
- **🏷️ Tagging System**: Organize rules with custom tags
- **🔄 Version Control**: Store multiple versions, activate any as default
- **📝 Audit Trail**: Automatic logging of all changes
- **🛡️ Safe Operations**: Protection against deleting active versions
- **🚀 Execute by Name**: Run rules without passing GRL content

```sql
-- Complete workflow example
SELECT rule_save('pricing', 'rule "Discount" { ... }', '1.0.0', 'Initial', 'First');
SELECT rule_tag_add('pricing', 'production');
SELECT rule_execute_by_name('pricing', '{"Order": {"total": 100}}', NULL);
SELECT rule_activate('pricing', '2.0.0');  -- Switch versions
```

**Migration**: Run `migrations/001_rule_repository.sql` to enable.

---