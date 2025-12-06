#!/bin/bash
# Sync documentation to GitHub Wiki
# Usage: ./sync-wiki.sh

set -e

WIKI_DIR="../rule-engine-postgres.wiki"

if [ ! -d "$WIKI_DIR" ]; then
    echo "❌ Wiki directory not found: $WIKI_DIR"
    echo "Clone wiki first:"
    echo "  cd .. && git clone https://github.com/KSD-CO/rule-engine-postgres.wiki.git"
    exit 1
fi

echo "📚 Syncing documentation to wiki..."
echo ""

# Get current version
VERSION=$(grep '^version = ' Cargo.toml | head -1 | sed 's/version = "\(.*\)"/\1/')

# Update Sidebar
echo "Creating _Sidebar.md..."
cat > "$WIKI_DIR/_Sidebar.md" << 'EOFDOC'
# 📚 Navigation

## Getting Started
- [Home](Home)
- [Installation Guide](Installation-Guide)
- [Quick Start](Quick-Start)
- [Configuration](Configuration)

## Core Concepts
- [Forward Chaining](Forward-Chaining)
- [Backward Chaining](Backward-Chaining)
- [GRL Syntax](GRL-Syntax)

## Rule Repository
- [Overview](Rule-Repository-Overview)
- [Versioning](Rule-Versioning)
- [Tagging](Rule-Tagging)
- [Audit Trail](Audit-Trail)

## API Reference
- [Core Functions](Core-Functions)
- [Repository Functions](Repository-Functions)
- [Health & Monitoring](Health-and-Monitoring)

## Use Cases
- [E-Commerce](Use-Case-ECommerce)
- [Banking](Use-Case-Banking)
- [Healthcare](Use-Case-Healthcare)
- [SaaS Billing](Use-Case-SaaS)

## Advanced
- [Performance Tuning](Performance-Tuning)
- [Multi-Environment](Multi-Environment-Deployment)
- [A/B Testing](AB-Testing)
- [Integration](Integration-Patterns)

## Operations
- [Deployment](Deployment)
- [Backup & Recovery](Backup-Recovery)
- [Monitoring](Monitoring)
- [Troubleshooting](Troubleshooting)

## Development
- [Building from Source](Building-from-Source)
- [Contributing](Contributing)
- [Release Process](Release-Process)

---

**v${VERSION}** | [GitHub](https://github.com/KSD-CO/rule-engine-postgres)
EOFDOC

# Update Footer
echo "Creating _Footer.md..."
cat > "$WIKI_DIR/_Footer.md" << EOFDOC
---

**Rule Engine PostgreSQL v${VERSION}** | [GitHub](https://github.com/KSD-CO/rule-engine-postgres) | [Issues](https://github.com/KSD-CO/rule-engine-postgres/issues) | [Discussions](https://github.com/KSD-CO/rule-engine-postgres/discussions) | [Releases](https://github.com/KSD-CO/rule-engine-postgres/releases)

💡 Found an issue with the docs? [Edit this page](https://github.com/KSD-CO/rule-engine-postgres.wiki.git)
EOFDOC

# Installation Guide
echo "Creating Installation-Guide.md..."
cat > "$WIKI_DIR/Installation-Guide.md" << 'EOFDOC'
# Installation Guide

## Prerequisites

- PostgreSQL 16 or 17
- Ubuntu/Debian or macOS
- `sudo` access for installation

## Quick Install (Ubuntu/Debian)

```bash
# One-liner install
curl -fsSL https://raw.githubusercontent.com/KSD-CO/rule-engine-postgres/main/quick-install.sh | bash
```

This script will:
1. Detect your PostgreSQL version
2. Download pre-built .deb package
3. Install the extension
4. Restart PostgreSQL

## Manual Installation

### Ubuntu/Debian

**PostgreSQL 17:**
```bash
wget https://github.com/KSD-CO/rule-engine-postgres/releases/download/v1.1.0/postgresql-17-rule-engine_1.1.0_amd64.deb
sudo dpkg -i postgresql-17-rule-engine_1.1.0_amd64.deb
sudo apt-get install -f
```

**PostgreSQL 16:**
```bash
wget https://github.com/KSD-CO/rule-engine-postgres/releases/download/v1.1.0/postgresql-16-rule-engine_1.1.0_amd64.deb
sudo dpkg -i postgresql-16-rule-engine_1.1.0_amd64.deb
sudo apt-get install -f
```

### macOS

Build from source (see [Building from Source](Building-from-Source)).

## Enable Extension

After installation:

```sql
-- Connect to your database
psql -d your_database

-- Create extension
CREATE EXTENSION rule_engine_postgre_extensions;

-- Verify installation
SELECT extversion FROM pg_extension WHERE extname = 'rule_engine_postgre_extensions';
-- Should return: 1.1.0

-- Test with simple rule
SELECT run_rule_engine(
    '{"value": 10}',
    'rule "test" { when value > 5 then result = "OK"; }'
);
```

## Upgrading from v1.0.0

```sql
-- Upgrade extension
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.1.0';

-- Verify upgrade
SELECT extversion FROM pg_extension WHERE extname = 'rule_engine_postgre_extensions';
```

The Rule Repository schema will be created automatically.

## Troubleshooting

### Extension not found

```bash
# Verify files exist (PostgreSQL 17)
ls /usr/lib/postgresql/17/lib/rule_engine*
ls /usr/share/postgresql/17/extension/rule_engine*

# Restart PostgreSQL
sudo systemctl restart postgresql@17
```

### Permission denied

```sql
-- Run as postgres user
sudo -u postgres psql -d your_database -c "CREATE EXTENSION rule_engine_postgre_extensions;"
```

### Version mismatch

```bash
# Reinstall package
sudo dpkg -r postgresql-17-rule-engine
sudo dpkg -i postgresql-17-rule-engine_1.1.0_amd64.deb
```

---

**Next**: [Quick Start](Quick-Start) →
EOFDOC

# Quick Start
echo "Creating Quick-Start.md..."
cat > "$WIKI_DIR/Quick-Start.md" << 'EOFDOC'
# Quick Start - 5 Minutes

Get started with rule-engine-postgres in 5 minutes.

## Step 1: Install Extension

See [Installation Guide](Installation-Guide) for detailed instructions.

```bash
# Quick install
curl -fsSL https://raw.githubusercontent.com/KSD-CO/rule-engine-postgres/main/quick-install.sh | bash
```

## Step 2: Enable Extension

```sql
CREATE EXTENSION rule_engine_postgre_extensions;
```

## Step 3: Save Your First Rule

```sql
SELECT rule_save(
    'discount_rules',
    'rule "VolumeDiscount" {
        salience 10;
        when
            Customer.orderTotal > 1000
        then
            Customer.discountPercent = 10;
            Customer.discountReason = "Volume discount applied";
    }',
    '1.0.0',
    'Customer discount rules',
    'Initial version'
);
```

## Step 4: Execute the Rule

```sql
SELECT rule_execute_by_name(
    'discount_rules',
    '{"Customer": {"orderTotal": 2500}}',
    NULL
);
```

Result:
```json
{
  "Customer": {
    "orderTotal": 2500,
    "discountPercent": 10,
    "discountReason": "Volume discount applied"
  }
}
```

## Step 5: Query with Backward Chaining

```sql
-- Save eligibility rule
SELECT rule_save(
    'eligibility_rules',
    'rule "CanVote" {
        when User.Age >= 18
        then User.CanVote = true;
    }',
    '1.0.0',
    'Eligibility rules',
    'Initial version'
);

-- Query: Can user vote?
SELECT rule_can_prove_by_name(
    'eligibility_rules',
    '{"User": {"Age": 25}}',
    'User.CanVote == true',
    NULL
);
-- Returns: true
```

## What's Next?

- [Rule Repository Overview](Rule-Repository-Overview) - Learn about versioning
- [Forward Chaining](Forward-Chaining) - Deep dive into forward chaining
- [Backward Chaining](Backward-Chaining) - Goal-driven reasoning
- [Use Cases](Use-Case-ECommerce) - Real-world examples

---

**Previous**: [Installation Guide](Installation-Guide) | **Next**: [Rule Repository Overview](Rule-Repository-Overview) →
EOFDOC

echo ""
echo "✅ Wiki pages created in $WIKI_DIR"
echo ""
echo "📤 To publish to GitHub Wiki:"
echo "  cd $WIKI_DIR"
echo "  git add ."
echo "  git commit -m 'Add installation and quick start guides'"
echo "  git push origin master"
