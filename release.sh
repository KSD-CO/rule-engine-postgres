#!/bin/bash
# Build release packages for distribution
# Usage: ./release.sh

set -e

# Extract version from Cargo.toml
VERSION=$(grep '^version = ' Cargo.toml | head -1 | sed 's/version = "\(.*\)"/\1/')

if [ -z "$VERSION" ]; then
    echo "❌ Error: Could not extract version from Cargo.toml"
    exit 1
fi

echo "🚀 Building release packages for v${VERSION}"
echo "   (extracted from Cargo.toml)"
echo ""

# Clean previous builds
echo "Cleaning previous builds..."
make clean
rm -rf releases/download/v${VERSION}
mkdir -p releases/download/v${VERSION}

# Build for PostgreSQL 16
echo ""
echo "📦 Building for PostgreSQL 16..."
make deb PG_VERSION=16

# Build for PostgreSQL 17
echo ""
echo "📦 Building for PostgreSQL 17..."
make deb PG_VERSION=17

# List built packages
echo ""
echo "✅ Release packages built successfully!"
echo ""
echo "📦 Packages:"
ls -lh releases/download/v${VERSION}/*.deb

# Generate checksums
echo ""
echo "Generating checksums..."
cd releases/download/v${VERSION}
sha256sum *.deb > SHA256SUMS
cd ../../..

echo ""
echo "📝 Checksums:"
cat releases/download/v${VERSION}/SHA256SUMS

# Create release notes
cat > releases/download/v${VERSION}/RELEASE_NOTES.md << 'EOF'
# Release v1.1.0

## 🎉 What's New

### Rule Repository (RFC-0001)
Complete rule management system with versioning, tagging, and execution.

**New Functions (7):**
- `rule_save()` - Save rules with semantic versioning
- `rule_get()` - Retrieve rules by name/version
- `rule_activate()` - Change active version
- `rule_delete()` - Soft delete with history
- `rule_tag_add()` - Add tags for organization
- `rule_tag_remove()` - Remove tags
- `rule_execute_by_name()` - Execute stored rules (forward chaining)

**Backward Chaining with Stored Rules (2):**
- `rule_query_by_name()` - Goal proving with proof trace
- `rule_can_prove_by_name()` - Fast boolean check

**Database Schema:**
- 4 tables: rule_definitions, rule_versions, rule_tags, rule_audit_log
- 1 view: rule_catalog (active rules)
- Automatic audit logging via triggers

## 📦 Installation

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

### Enable Extension

```sql
CREATE EXTENSION rule_engine_postgre_extensions;

-- Verify version
SELECT extversion FROM pg_extension WHERE extname = 'rule_engine_postgre_extensions';
-- Should show: 1.1.0
```

## 🔄 Upgrading from v1.0.0

```sql
-- Upgrade extension
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.1.0';

-- Verify upgrade
SELECT extversion FROM pg_extension WHERE extname = 'rule_engine_postgre_extensions';
```

The Rule Repository schema will be automatically created.

## 📚 Documentation

- [Complete Guide](https://github.com/KSD-CO/rule-engine-postgres/blob/main/README.md)
- [Rule Repository Quick Reference](https://github.com/KSD-CO/rule-engine-postgres/blob/main/docs/guides/rule-repository-quick-reference.md)
- [Use Cases & Examples](https://github.com/KSD-CO/rule-engine-postgres/blob/main/docs/examples/use-cases.md)
- [CHANGELOG](https://github.com/KSD-CO/rule-engine-postgres/blob/main/CHANGELOG.md)

## ⚡ Quick Example

```sql
-- Save a rule
SELECT rule_save(
    'discount_rules',
    'rule "VolumeDiscount" {
        when Customer.orderTotal > 1000
        then Customer.discountPercent = 10;
    }',
    '1.0.0',
    'Volume discount rules',
    'Initial version'
);

-- Execute it
SELECT rule_execute_by_name(
    'discount_rules',
    '{"Customer": {"orderTotal": 2500}}',
    NULL
);

-- Query with backward chaining
SELECT rule_can_prove_by_name(
    'eligibility_rules',
    '{"User": {"Age": 25}}',
    'User.CanVote == true',
    NULL
);
-- Returns: true
```

## 🐛 Bug Fixes

- Fixed macOS Apple Silicon build issues
- Improved error handling in validation
- Fixed memory leaks in rule execution

## 🔧 Technical Details

- **PostgreSQL**: 16, 17
- **Rust**: 1.70+
- **pgrx**: 0.16.1
- **Platform**: Linux (amd64), macOS (Apple Silicon via source)

## 📊 Checksums

See [SHA256SUMS](SHA256SUMS) file for package verification.

---

**Full Changelog**: https://github.com/KSD-CO/rule-engine-postgres/blob/main/CHANGELOG.md
EOF

echo ""
echo "📄 Release notes created: releases/download/v${VERSION}/RELEASE_NOTES.md"

echo ""
echo "🎯 Next steps:"
echo ""
echo "1. Test packages:"
echo "   sudo dpkg -i releases/download/v${VERSION}/postgresql-17-rule-engine_${VERSION}_amd64.deb"
echo ""
echo "2. Create GitHub release:"
echo "   gh release create v${VERSION} \\"
echo "     releases/download/v${VERSION}/*.deb \\"
echo "     releases/download/v${VERSION}/SHA256SUMS \\"
echo "     releases/download/v${VERSION}/RELEASE_NOTES.md \\"
echo "     --title 'v${VERSION} - Rule Repository' \\"
echo "     --notes-file releases/download/v${VERSION}/RELEASE_NOTES.md"
echo ""
echo "3. Update documentation:"
echo "   - Update README.md installation section"
echo "   - Update main website"
echo "   - Announce on Twitter/LinkedIn"
echo ""

