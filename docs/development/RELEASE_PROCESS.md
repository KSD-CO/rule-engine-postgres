# Release Process Guide

This document describes how to create and publish releases for rule-engine-postgres.

## 📋 Pre-Release Checklist

- [ ] All tests passing (`make test`)
- [ ] Code formatted (`make fmt`)
- [ ] Documentation updated (README.md, CHANGELOG.md, docs/)
- [ ] Version bumped in:
  - [ ] `Cargo.toml`
  - [ ] `rule_engine_postgre_extensions.control` (default_version)
  - [ ] `Makefile` (VERSION)
  - [ ] All shell scripts (VERSION variable)
  - [ ] `CHANGELOG.md` (new version section)
- [ ] SQL migration file created if needed (e.g., `rule_engine_postgre_extensions--1.0.0--1.1.0.sql`)
- [ ] All new features documented in CHANGELOG.md

## 🚀 Release Methods

### Method 1: Local Build (Recommended for Testing)

Build and test locally before pushing to GitHub:

```bash
# 1. Build release packages
./release.sh

# 2. Test packages locally
sudo dpkg -i releases/download/v1.1.0/postgresql-17-rule-engine_1.1.0_amd64.deb
psql -d postgres -c "CREATE EXTENSION rule_engine_postgre_extensions;"
psql -d postgres -c "SELECT extversion FROM pg_extension WHERE extname = 'rule_engine_postgre_extensions';"

# 3. If tests pass, commit and tag
git add .
git commit -m "Release v1.1.0"
git tag -a v1.1.0 -m "Release v1.1.0 - Rule Repository"
git push origin main
git push origin v1.1.0
```

### Method 2: GitHub Actions (Automated)

GitHub Actions will automatically build and release when you push a tag:

```bash
# 1. Commit all changes
git add .
git commit -m "Prepare release v1.1.0"
git push origin main

# 2. Create and push tag
git tag -a v1.1.0 -m "Release v1.1.0 - Rule Repository"
git push origin v1.1.0

# GitHub Actions will automatically:
# - Build .deb packages for PostgreSQL 16 and 17
# - Generate checksums
# - Create GitHub release with all artifacts
```

### Method 3: Manual Trigger (GitHub UI)

1. Go to GitHub repository
2. Click "Actions" tab
3. Select "Release" workflow
4. Click "Run workflow"
5. Enter version (e.g., `1.1.0`)
6. Click "Run workflow" button

## 📦 What Gets Released

For each PostgreSQL version (16, 17):

1. **`.deb` package**: `postgresql-{version}-rule-engine_{version}_amd64.deb`
   - Shared library (`.so`)
   - Control file
   - SQL migration files
   - Documentation

2. **Checksums**: `SHA256SUMS` file for package verification

3. **Release Notes**: Extracted from CHANGELOG.md

## 🔄 Post-Release Tasks

After GitHub release is published:

1. **Update Documentation**:
   ```bash
   # Update installation instructions in README.md
   # Update website/blog if applicable
   ```

2. **Announce Release**:
   - Post on Twitter/LinkedIn
   - Update project homepage
   - Notify users via email/newsletter

3. **Monitor Issues**:
   - Watch for installation issues
   - Respond to user feedback
   - Fix critical bugs in hotfix release if needed

## 🏗️ Building Individual Packages

Build package for specific PostgreSQL version:

```bash
# PostgreSQL 17
make deb PG_VERSION=17

# PostgreSQL 16
make deb PG_VERSION=16

# Both versions
make deb-all
```

Packages will be in `releases/download/v{VERSION}/`

## 🧪 Testing Release Packages

### Test Installation

```bash
# Install package
sudo dpkg -i releases/download/v1.1.0/postgresql-17-rule-engine_1.1.0_amd64.deb

# If dependencies missing:
sudo apt-get install -f

# Verify files installed
ls -la /usr/lib/postgresql/17/lib/rule_engine*
ls -la /usr/share/postgresql/17/extension/rule_engine*
```

### Test Extension

```bash
# Create extension
psql -d postgres -c "DROP EXTENSION IF EXISTS rule_engine_postgre_extensions CASCADE;"
psql -d postgres -c "CREATE EXTENSION rule_engine_postgre_extensions;"

# Check version
psql -d postgres -c "SELECT extversion FROM pg_extension WHERE extname = 'rule_engine_postgre_extensions';"

# Test functions
psql -d postgres -c "\\df *rule*"

# Test Rule Repository
psql -d postgres -c "
SELECT rule_save(
    'test',
    'rule \"Test\" { when a == 1 then b = 2; }',
    '1.0.0',
    'Test',
    'Test'
);
"

# Test execution
psql -d postgres -c "
SELECT rule_execute_by_name('test', '{\"a\":1}', NULL);
"
```

### Test Upgrade

```bash
# Install old version
sudo dpkg -i releases/download/v1.0.0/postgresql-17-rule-engine_1.0.0_amd64.deb
psql -d postgres -c "CREATE EXTENSION rule_engine_postgre_extensions;"

# Upgrade to new version
sudo dpkg -i releases/download/v1.1.0/postgresql-17-rule-engine_1.1.0_amd64.deb
sudo systemctl restart postgresql@17
psql -d postgres -c "ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.1.0';"

# Verify upgrade
psql -d postgres -c "SELECT extversion FROM pg_extension WHERE extname = 'rule_engine_postgre_extensions';"
```

## 🐛 Hotfix Release Process

For critical bug fixes:

```bash
# 1. Create hotfix branch
git checkout -b hotfix/v1.1.1 v1.1.0

# 2. Fix bug and test
# ... make changes ...
make test

# 3. Update version
# Update Cargo.toml, control file, etc. to 1.1.1

# 4. Update CHANGELOG
# Add [1.1.1] section with bug fixes

# 5. Commit and tag
git add .
git commit -m "Hotfix v1.1.1: Fix critical bug"
git tag -a v1.1.1 -m "Hotfix v1.1.1"

# 6. Merge and push
git checkout main
git merge hotfix/v1.1.1
git push origin main
git push origin v1.1.1

# 7. Delete hotfix branch
git branch -d hotfix/v1.1.1
```

## 📝 Version Numbering

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR** (1.x.x): Breaking changes, major new features
- **MINOR** (x.1.x): New features, backward compatible
- **PATCH** (x.x.1): Bug fixes, backward compatible

Examples:
- `1.0.0` → `1.1.0`: Added Rule Repository (new feature)
- `1.1.0` → `1.1.1`: Bug fixes (patch)
- `1.1.0` → `2.0.0`: Breaking API changes (major)

## 🔧 Troubleshooting

### Build fails with "pg_config not found"
```bash
# Install PostgreSQL development files
sudo apt-get install postgresql-server-dev-17
```

### Package build fails
```bash
# Clean and rebuild
make clean
cargo clean
./build-deb.sh 17
```

### GitHub Actions fails
- Check workflow logs in Actions tab
- Verify all secrets are set (GITHUB_TOKEN should be automatic)
- Ensure tag follows pattern `v*` (e.g., `v1.1.0`)

## 📚 Resources

- [Semantic Versioning](https://semver.org/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Keep a Changelog](https://keepachangelog.com/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

---

**Last Updated**: 2025-12-06  
**Next Release**: v1.2.0 (planned features: Rule Sets, Execution Statistics)
