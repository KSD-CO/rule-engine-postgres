# rule-engine-postgres

[![CI](https://github.com/KSD-CO/rule-engine-postgres/actions/workflows/ci.yml/badge.svg)](https://github.com/KSD-CO/rule-engine-postgres/actions)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/KSD-CO/rule-engine-postgres/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Production-ready** PostgreSQL extension written in Rust that brings rule engine capabilities directly into your database. Execute complex business logic using GRL (Grule Rule Language) syntax with both **forward** and **backward chaining** support.

## Why Use This?

- **No Microservices Overhead**: Business rules run directly in PostgreSQL
- **Real-time Decisions**: Sub-millisecond rule execution (~1000 rules/sec)
- **Dual Reasoning Modes**: Forward chaining (data-driven) + Backward chaining (goal-driven)
- **Version Control Rules**: Store rules in database with full audit trail
- **Dynamic Logic**: Change business rules without code deployment
- **Transaction Safety**: Rules execute within PostgreSQL transactions

## Features

- ⚡ **High Performance**: Compiled Rust code, optimized for speed
- 🎯 **Backward Chaining**: Goal queries with proof traces ("Can we prove X?")
- 🔀 **Forward Chaining**: Event-driven rule execution (traditional)
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

Execute rules that modify facts based on conditions:

```sql
SELECT run_rule_engine(
    '{"User": {"age": 30, "status": "active"}}',
    'rule "CheckAge" salience 10 {
        when
            User.age > 18
        then
            User.status = "adult";
    }'
);
-- Returns: {"User": {"age": 30, "status": "adult"}}
```

### Backward Chaining (Goal-Driven) ⭐ NEW

Query if a goal can be proven with full reasoning trace:

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

**When to use each mode:**
- **Forward Chaining**: Event processing, data enrichment, monitoring
- **Backward Chaining**: Eligibility checks, diagnosis, decision explanation

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

### Backward Chaining Functions ⭐ NEW

- **`query_backward_chaining(facts_json TEXT, rules_grl TEXT, goal TEXT) → JSON`**
  Query if a goal can be proven with full details and proof trace.

- **`query_backward_chaining_multi(facts_json TEXT, rules_grl TEXT, goals TEXT[]) → JSON[]`**
  Query multiple goals in one call.

- **`can_prove_goal(facts_json TEXT, rules_grl TEXT, goal TEXT) → BOOLEAN`**
  Fast boolean check (2-3x faster, no proof trace).

### Utility Functions

- **`rule_engine_health_check() → TEXT`**
  Returns health status with version and timestamp.

- **`rule_engine_version() → TEXT`**
  Returns extension version ("1.0.0").

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

- **[📖 Documentation Index](docs/README.md)** - Complete documentation navigation
- **[🎯 Backward Chaining Guide](docs/guides/backward-chaining.md)** - Goal-driven reasoning guide
- **[💡 Use Case Examples](docs/examples/use-cases.md)** - Real-world production examples
- **[🔧 API Reference](docs/api-reference.md)** - Complete function reference
- **[🔗 Integration Patterns](docs/integration-patterns.md)** - Triggers, JSONB, performance tips
- **[🐳 Docker Deployment](docs/deployment/docker.md)** - Docker and Docker Compose
- **[🔨 Build from Source](docs/deployment/build-from-source.md)** - Manual build instructions
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
├── lib.rs (15 lines)              # Minimal entry point
├── api/
│   ├── health.rs                  # Health check & version
│   ├── engine.rs                  # Forward chaining API
│   └── backward.rs (134 lines)    # ⭐ Backward chaining API
├── core/
│   ├── facts.rs                   # Facts/JSON conversion
│   ├── rules.rs                   # GRL parsing
│   ├── executor.rs                # Forward chaining logic
│   └── backward.rs (152 lines)    # ⭐ Backward chaining logic
├── error/
│   ├── codes.rs                   # Error definitions (12 codes)
│   └── mod.rs                     # Error utilities
└── validation/
    ├── input.rs                   # Input validation
    └── limits.rs                  # Size constraints
```

**Total**: 15 modules, ~400 lines of clean, maintainable code

---

## Acknowledgments

- Built with [pgrx](https://github.com/pgcentralfoundation/pgrx) - PostgreSQL extension framework
- Powered by [rust-rule-engine](https://crates.io/crates/rust-rule-engine) v1.7.0 (with backward-chaining feature)
- Inspired by business rule engines like Drools and Grule

---

**Version**: 1.0.0 | **Status**: Production Ready ✅ | **Maintainer**: Ton That Vu
