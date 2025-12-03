# rule-engine-postgres

[![CI](https://github.com/KSD-CO/rule-engine-postgres/actions/workflows/ci.yml/badge.svg)](https://github.com/KSD-CO/rule-engine-postgres/actions)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/KSD-CO/rule-engine-postgres/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Production-ready** PostgreSQL extension written in Rust that brings rule engine capabilities directly into your database. Execute complex business logic using GRL (Grule Rule Language) syntax.

## Features

- ⚡ **High Performance**: Compiled Rust code (~1000 rules/sec)
- 🔒 **Production Ready**: Error codes, health checks, Docker support, CI/CD
- 📦 **Easy Deploy**: Docker or manual installation
- 🔧 **Flexible**: JSON/JSONB support, triggers, nested objects
- 🛡️ **Type Safe**: Leverages Rust's type system
- 📊 **Observable**: Health checks, structured errors, monitoring-ready

## Quick Start

### Option 1: Quick Install (Recommended)

```bash
# One-liner install (Ubuntu/Debian)
curl -fsSL https://raw.githubusercontent.com/KSD-CO/rule-engine-postgres/main/quick-install.sh | bash

# Enable extension
sudo -u postgres psql -d postgres -c "CREATE EXTENSION rule_engine_postgre_extensions;"
sudo -u postgres psql -d postgres -c "SELECT rule_engine_version();"
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
# Prerequisites: Rust 1.75+, PostgreSQL 13-17
cargo install cargo-pgrx --version 0.16.1 --locked
git clone https://github.com/KSD-CO/rule-engine-postgres.git
cd rule-engine-postgres
./install.sh
```

## Usage

### Basic Example

```sql
SELECT run_rule_engine(
    '{"User": {"age": 30, "status": "active"}}',
    'rule "CheckAge" { when User.age > 18 then User.status = "adult" }'
);
-- Returns: {"User": {"age": 30, "status": "adult"}}
```

### Real-World Examples

**Customer Tier Classification:**
```sql
SELECT run_rule_engine(
    '{"Customer": {"points": 1500, "years": 3}}',
    'rule "PlatinumTier" {
        when Customer.points > 1000 and Customer.years > 2
        then Customer.tier = "Platinum"
    }'
);
```

**Fraud Detection:**
```sql
SELECT run_rule_engine(
    '{"Transaction": {"amount": 5000, "time": "23:30"}}',
    'rule "HighValue" { when Transaction.amount > 3000 then Transaction.flag = "review" }'
);
```

**Dynamic Pricing:**
```sql
SELECT run_rule_engine(
    '{"Order": {"items": 5, "total": 500}}',
    'rule "Discount" { when Order.items > 3 then Order.discount = 0.1 }'
);
```

## API Reference

### Functions

#### `run_rule_engine(facts_json TEXT, rules_grl TEXT) → TEXT`
Execute GRL rules on JSON facts. Max 1MB for both parameters.

#### `rule_engine_health_check() → TEXT`
Returns health status with version and timestamp.

#### `rule_engine_version() → TEXT`
Returns extension version ("1.0.0").

### Error Codes

Errors return JSON with `error`, `error_code`, and `timestamp`:

| Code | Description |
|------|-------------|
| ERR001 | Empty facts JSON |
| ERR002 | Empty rules GRL |
| ERR003-004 | Input too large (max 1MB) |
| ERR005-006 | Invalid JSON |
| ERR007-010 | Rule processing failed |
| ERR011-012 | Execution/serialization failed |

## Integration Patterns

### With Triggers

```sql
CREATE TRIGGER validate_order BEFORE INSERT ON orders
FOR EACH ROW EXECUTE FUNCTION validate_with_rules();
```

### With JSONB Columns

```sql
UPDATE products SET data = run_rule_engine(data::TEXT, 'rule...')::JSONB
WHERE category = 'electronics';
```

### Store Rules in Database

```sql
CREATE TABLE business_rules (
    name TEXT PRIMARY KEY,
    grl_definition TEXT,
    is_active BOOLEAN DEFAULT TRUE
);

SELECT run_rule_engine(
    order_data::TEXT,
    (SELECT grl_definition FROM business_rules WHERE name = 'validate_order')
) FROM orders;
```

## Production Deployment

### Docker Compose

```bash
# Production mode
docker-compose up -d postgres

# With monitoring (Prometheus)
docker-compose --profile monitoring up -d

# With PgAdmin
docker-compose --profile tools up -d
```

### Health Monitoring

```sql
-- Add to your monitoring system
SELECT rule_engine_health_check();
```

**Expected output:**
```json
{"status":"healthy","extension":"rule_engine_postgre_extensions","version":"1.0.0","timestamp":"2025-01-18T10:00:00Z"}
```

### Performance Tips

- Use connection pooling (PgBouncer) for high concurrency
- Cache frequently-used rules in database tables
- Index fact columns for trigger performance
- Use AFTER triggers for background processing

### Security

- All inputs validated (1MB limit)
- SQL injection protected
- Structured error codes (no internal exposure)
- Integrates with PostgreSQL RBAC
- Supports audit logging

## Documentation

- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Production deployment guide
- **[EXAMPLES.md](EXAMPLES.md)** - More SQL examples
- **[CHANGELOG.md](CHANGELOG.md)** - Version history

## Upgrading

From 0.1.0 to 1.0.0 (backward compatible):

```sql
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.0.0';
SELECT rule_engine_version();  -- Verify: "1.0.0"
```

## Development

```bash
# Run tests
cargo test
cargo pgrx test pg16

# Local development
cargo pgrx run pg16

# Build for specific PostgreSQL version
cargo build --release --features pg16
```

## Use Cases

- Business rule validation
- Dynamic pricing & promotions
- Fraud detection & risk scoring
- Workflow automation
- Policy enforcement
- Data classification
- Compliance rules

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Add tests for your changes
4. Submit a Pull Request

## Support

- **Issues**: [GitHub Issues](https://github.com/KSD-CO/rule-engine-postgres/issues)
- **Documentation**: See files in this repository

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [pgrx](https://github.com/pgcentralfoundation/pgrx)
- Powered by [rust-rule-engine](https://crates.io/crates/rust-rule-engine)

---

**Version**: 1.0.0 | **Status**: Production Ready ✅
