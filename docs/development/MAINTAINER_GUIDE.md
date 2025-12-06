# Maintainer's Quick Reference

Quick commands for maintaining rule-engine-postgres extension.

## 📦 Version Management

All version information is stored in **`Cargo.toml`** as the single source of truth.

### Check Current Version

```bash
./version.sh
```

Output shows:
- Current version from Cargo.toml
- Consistency check across all files
- Location of release artifacts

### Bump Version

```bash
# Bump to new version (updates all files automatically)
./bump-version.sh 1.2.0
```

This updates:
- ✅ Cargo.toml
- ✅ rule_engine_postgre_extensions.control
- ✅ README.md badge
- ✅ CHANGELOG.md (adds new section)
- ✅ Creates migration SQL file if needed

**After bumping:**
1. Review changes: `git diff`
2. Update CHANGELOG.md with actual changes
3. Update migration SQL if needed
4. Run tests: `make test`
5. Build: `make build`

## 🏗️ Building

### Local Build

```bash
# PostgreSQL 17 (default)
make build

# PostgreSQL 16
make build PG_VERSION=16

# Both versions
make build PG_VERSION=16
make build PG_VERSION=17
```

### Build Release Packages

```bash
# Build .deb packages for both PG 16 and 17
./release.sh

# Output: releases/download/v{VERSION}/
# - postgresql-16-rule-engine_{VERSION}_amd64.deb
# - postgresql-17-rule-engine_{VERSION}_amd64.deb
# - SHA256SUMS
# - RELEASE_NOTES.md
```

### Single Platform Build

```bash
# Build .deb for PostgreSQL 17
make deb PG_VERSION=17

# Build .deb for PostgreSQL 16
make deb PG_VERSION=16
```

## 🚀 Releasing

### Method 1: Automated (GitHub Actions)

```bash
# 1. Bump version
./bump-version.sh 1.2.0

# 2. Update CHANGELOG.md with changes
vim CHANGELOG.md

# 3. Commit and push
git add .
git commit -m "Release v1.2.0"
git push origin main

# 4. Create and push tag
git tag -a v1.2.0 -m "Release v1.2.0"
git push origin v1.2.0

# GitHub Actions automatically:
# - Builds packages for PG 16 and 17
# - Creates GitHub release
# - Uploads artifacts
```

### Method 2: Manual

```bash
# 1. Build locally
./release.sh

# 2. Test package
sudo dpkg -i releases/download/v1.2.0/postgresql-17-rule-engine_1.2.0_amd64.deb
psql -c "CREATE EXTENSION rule_engine_postgre_extensions;"

# 3. Upload to GitHub
gh release create v1.2.0 \
  releases/download/v1.2.0/*.deb \
  releases/download/v1.2.0/SHA256SUMS \
  --title "v1.2.0" \
  --notes-file releases/download/v1.2.0/RELEASE_NOTES.md
```

## 🧪 Testing

```bash
# Run all tests
make test

# Format code
make fmt

# Run CI checks (format + clippy + build)
make ci

# Test specific PostgreSQL version
make test PG_VERSION=16
```

## 📝 Documentation Updates

After version bump, update these if needed:

```bash
# Main documentation
vim README.md
vim CHANGELOG.md

# API documentation
vim docs/api-reference.md

# Guides
vim docs/guides/*.md

# Examples
vim docs/examples/*.md
```

## 🔍 Common Tasks

### Add New Function

1. **Add Rust function** in `src/api/` or `src/repository/`
2. **Export in** `src/lib.rs`
3. **Add SQL wrapper** in `rule_engine_postgre_extensions--{VERSION}.sql`
4. **Update migration** if needed
5. **Add tests** in `tests/`
6. **Update docs**:
   - README.md API Reference section
   - docs/api-reference.md
   - CHANGELOG.md

### Create Migration

```bash
# Bump minor/major version first
./bump-version.sh 1.2.0

# Migration file created automatically at:
# rule_engine_postgre_extensions--1.1.0--1.2.0.sql

# Edit migration file with schema changes
vim rule_engine_postgre_extensions--1.1.0--1.2.0.sql
```

### Update Dependencies

```bash
# Update Cargo.toml
vim Cargo.toml

# Update lockfile
cargo update

# Test
make test

# Update CHANGELOG.md
vim CHANGELOG.md
```

## 📊 Version Numbering

Follow [Semantic Versioning](https://semver.org/):

- **MAJOR** (2.0.0): Breaking changes, incompatible API changes
- **MINOR** (1.2.0): New features, backward compatible
- **PATCH** (1.1.1): Bug fixes, backward compatible

Examples:
- Add new function → MINOR bump (1.1.0 → 1.2.0)
- Fix bug → PATCH bump (1.1.0 → 1.1.1)
- Change function signature → MAJOR bump (1.1.0 → 2.0.0)

## 🔧 Troubleshooting

### Build fails

```bash
# Clean and rebuild
make clean
cargo clean
make build
```

### Version mismatch

```bash
# Check all version references
./version.sh

# If mismatched, manually fix or re-run bump-version
./bump-version.sh $(grep '^version = ' Cargo.toml | head -1 | sed 's/version = "\(.*\)"/\1/')
```

### Test fails

```bash
# Run specific test
cargo test test_name

# Run with output
cargo test -- --nocapture

# Run integration tests only
cargo test --test integration_tests
```

## 📂 Key Files

| File | Purpose |
|------|---------|
| `Cargo.toml` | **Source of truth** for version |
| `rule_engine_postgre_extensions.control` | Extension metadata |
| `rule_engine_postgre_extensions--{VERSION}.sql` | Full SQL definition |
| `rule_engine_postgre_extensions--{OLD}--{NEW}.sql` | Migration script |
| `CHANGELOG.md` | User-facing changes |
| `version.sh` | Check version consistency |
| `bump-version.sh` | Automated version bump |
| `release.sh` | Build release packages |
| `build-deb.sh` | Build single .deb package |

## 🎯 Pre-Release Checklist

- [ ] Version bumped: `./bump-version.sh X.Y.Z`
- [ ] CHANGELOG.md updated with changes
- [ ] Migration SQL created/updated (if needed)
- [ ] All tests pass: `make test`
- [ ] Code formatted: `make fmt`
- [ ] CI checks pass: `make ci`
- [ ] Documentation updated
- [ ] Local build tested: `./release.sh`
- [ ] Package installation tested
- [ ] Extension loads and functions work
- [ ] Upgrade from previous version tested
- [ ] Tag created: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`

## 📚 Resources

- [Release Process](RELEASE_PROCESS.md) - Detailed release guide
- [Build System](BUILD_SYSTEM.md) - Build system overview
- [Build and Install](BUILD_AND_INSTALL.md) - Installation guide

---

**Quick Start for New Maintainers:**
1. Clone repo
2. Check version: `./version.sh`
3. Build: `make build`
4. Test: `make test`
5. Read: [RELEASE_PROCESS.md](RELEASE_PROCESS.md)
