# Scripts and Build System Summary

## 📁 Build Scripts Overview

### Core Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| **release.sh** | Build complete release packages | `./release.sh` |
| **build-deb.sh** | Build .deb package for one PG version | `./build-deb.sh 17` |
| **install.sh** | Local installation script | `PG_VERSION=17 ./install.sh` |
| **quick-install.sh** | One-line remote install | `curl -fsSL url \| bash` |

### Makefile Targets

```bash
make build           # Build extension (default PG 17)
make build PG_VERSION=16  # Build for PG 16
make install         # Build and install locally
make test            # Run tests
make deb             # Build .deb package
make deb-all         # Build for all PG versions (16, 17)
make clean           # Clean build artifacts
make fmt             # Format code
make ci              # Run CI checks
```

## 🔄 Build Process Flow

### 1. Local Development Build

```bash
# Build for PostgreSQL 17 (default)
make build

# Or specify version
make build PG_VERSION=16

# Uses: cargo pgrx package --pg-config /path/to/pg_config
# Output: target/release/rule_engine_postgre_extensions-pg{version}/
```

### 2. Local Installation

```bash
# Install to local PostgreSQL
PG_VERSION=17 ./install.sh

# What it does:
# 1. Detects OS (Linux/macOS)
# 2. Builds with cargo pgrx package
# 3. Copies files to correct locations:
#    - Linux: /usr/lib/postgresql/{version}/lib/
#    - macOS: /opt/homebrew/opt/postgresql@{version}/lib/
# 4. Restarts PostgreSQL
```

### 3. Release Package Build

```bash
# Build release packages for distribution
./release.sh

# What it does:
# 1. Cleans previous builds
# 2. Builds .deb for PostgreSQL 16
# 3. Builds .deb for PostgreSQL 17
# 4. Generates SHA256SUMS
# 5. Creates RELEASE_NOTES.md
# 6. Outputs to: releases/download/v{VERSION}/
```

### 4. Single Platform Package

```bash
# Build .deb for specific PostgreSQL version
./build-deb.sh 17

# Output:
# releases/download/v1.1.0/postgresql-17-rule-engine_1.1.0_amd64.deb
```

## 🏗️ Directory Structure After Build

```
rule-engine-postgres/
├── target/
│   └── release/
│       ├── rule_engine_postgre_extensions-pg16/    # PG16 build output
│       │   └── usr/
│       │       ├── lib/postgresql/16/lib/
│       │       │   └── rule_engine_postgre_extensions.so
│       │       └── share/postgresql/16/extension/
│       │           ├── rule_engine_postgre_extensions.control
│       │           └── rule_engine_postgre_extensions--*.sql
│       └── rule_engine_postgre_extensions-pg17/    # PG17 build output
│           └── usr/
│               └── (same structure)
└── releases/
    └── download/
        └── v1.1.0/
            ├── postgresql-16-rule-engine_1.1.0_amd64.deb
            ├── postgresql-17-rule-engine_1.1.0_amd64.deb
            ├── SHA256SUMS
            └── RELEASE_NOTES.md
```

## 🎯 Key Changes in v1.1.0

### What Was Fixed

1. **Version Updates**:
   - All scripts: 1.0.0 → 1.1.0
   - Default PostgreSQL: 16 → 17
   - Updated all URLs and paths

2. **Build System**:
   - ✅ Use `cargo pgrx package` instead of `cargo build`
   - ✅ Correct output path handling
   - ✅ Support both Linux and macOS
   - ✅ Proper file permissions

3. **Scripts Updated**:
   - ✅ `quick-install.sh` - Remote installation
   - ✅ `install.sh` - Local installation with OS detection
   - ✅ `build-deb.sh` - Debian package builder
   - ✅ `Makefile` - Build automation
   - 🆕 `release.sh` - Complete release workflow

4. **GitHub Actions**:
   - ✅ `.github/workflows/release.yml` updated
   - Builds .deb for PG 16 and 17
   - Generates checksums automatically
   - Creates GitHub release with artifacts

## 📦 Package Contents

Each `.deb` package includes:

```
postgresql-{VERSION}-rule-engine_{VERSION}_amd64.deb
├── usr/
│   ├── lib/
│   │   └── postgresql/{PG_VERSION}/
│   │       └── lib/
│   │           └── rule_engine_postgre_extensions.so
│   └── share/
│       ├── postgresql/{PG_VERSION}/
│       │   └── extension/
│       │       ├── rule_engine_postgre_extensions.control
│       │       ├── rule_engine_postgre_extensions--0.1.0.sql
│       │       ├── rule_engine_postgre_extensions--1.0.0.sql
│       │       ├── rule_engine_postgre_extensions--1.1.0.sql
│       │       ├── rule_engine_postgre_extensions--0.1.0--1.0.0.sql
│       │       └── rule_engine_postgre_extensions--1.0.0--1.1.0.sql
│       └── doc/
│           └── postgresql-{PG_VERSION}-rule-engine/
│               ├── README.md
│               ├── LICENSE
│               └── (other docs)
└── DEBIAN/
    └── control (package metadata)
```

## 🚀 Release Workflow

### Automated (GitHub Actions)

```bash
# 1. Update version everywhere
# 2. Commit changes
git add .
git commit -m "Release v1.1.0"
git push origin main

# 3. Create and push tag
git tag -a v1.1.0 -m "Release v1.1.0 - Rule Repository"
git push origin v1.1.0

# GitHub Actions automatically:
# - Builds packages for PG 16 and 17
# - Generates checksums
# - Creates GitHub release
# - Uploads all artifacts
```

### Manual (Local Build)

```bash
# 1. Build release packages
./release.sh

# 2. Test packages
sudo dpkg -i releases/download/v1.1.0/postgresql-17-rule-engine_1.1.0_amd64.deb
psql -c "CREATE EXTENSION rule_engine_postgre_extensions;"

# 3. Upload to GitHub Releases
gh release create v1.1.0 \
  releases/download/v1.1.0/*.deb \
  releases/download/v1.1.0/SHA256SUMS \
  --title "v1.1.0 - Rule Repository" \
  --notes-file releases/download/v1.1.0/RELEASE_NOTES.md
```

## 🧪 Testing Built Packages

```bash
# Test installation
sudo dpkg -i postgresql-17-rule-engine_1.1.0_amd64.deb
sudo apt-get install -f  # Fix dependencies

# Test extension
psql -d postgres << 'EOF'
DROP EXTENSION IF EXISTS rule_engine_postgre_extensions CASCADE;
CREATE EXTENSION rule_engine_postgre_extensions;

-- Verify version
SELECT extversion FROM pg_extension 
WHERE extname = 'rule_engine_postgre_extensions';

-- Test functions
SELECT rule_save('test', 'rule "T" { when a == 1 then b = 2; }', '1.0.0', 'Test', 'Test');
SELECT rule_execute_by_name('test', '{"a":1}', NULL);
EOF

# Verify checksum
cd releases/download/v1.1.0
sha256sum -c SHA256SUMS
```

## 🔧 Platform-Specific Notes

### Linux (Ubuntu/Debian)

```bash
# Build command
cargo pgrx package --pg-config /usr/lib/postgresql/17/bin/pg_config

# Install paths
/usr/lib/postgresql/17/lib/rule_engine_postgre_extensions.so
/usr/share/postgresql/17/extension/rule_engine_postgre_extensions*

# Restart
sudo systemctl restart postgresql@17
```

### macOS (Apple Silicon)

```bash
# Build command (requires MACOSX_DEPLOYMENT_TARGET)
export MACOSX_DEPLOYMENT_TARGET=15.0
cargo pgrx package --pg-config /opt/homebrew/opt/postgresql@17/bin/pg_config

# Install paths
/opt/homebrew/opt/postgresql@17/lib/postgresql/rule_engine_postgre_extensions.dylib
/opt/homebrew/opt/postgresql@17/share/postgresql@17/extension/rule_engine_postgre_extensions*

# Restart
brew services restart postgresql@17
```

## 📚 Documentation

- **[BUILD_AND_INSTALL.md](BUILD_AND_INSTALL.md)** - Complete build and installation guide
- **[RELEASE_PROCESS.md](RELEASE_PROCESS.md)** - Release workflow and checklist
- **[../../README.md](../../README.md)** - User documentation

## ✅ Verification Checklist

Before releasing:

- [ ] All scripts have correct version (1.1.0)
- [ ] `cargo pgrx package` used (not `cargo build`)
- [ ] Both PG 16 and 17 build successfully
- [ ] Packages install correctly on Ubuntu
- [ ] Extension loads and functions work
- [ ] Upgrade from v1.0.0 works
- [ ] Checksums are correct
- [ ] Release notes are complete
- [ ] GitHub Actions workflow succeeds

---

**Current Version**: v1.1.0  
**Supported PostgreSQL**: 16, 17  
**Platforms**: Linux (amd64), macOS (Apple Silicon via source)
