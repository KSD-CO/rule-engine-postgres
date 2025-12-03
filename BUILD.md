# Building rule-engine-postgres

This guide explains how to build `.deb` packages and other distribution formats.

## Prerequisites

### System Requirements
- Ubuntu/Debian Linux
- Rust 1.75+ (install via [rustup](https://rustup.rs/))
- PostgreSQL development files (13, 14, 15, 16, or 17)
- Build tools: `build-essential`, `pkg-config`, `libssl-dev`

### Install Dependencies

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Install PostgreSQL and build dependencies
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    postgresql-server-dev-16 \
    postgresql-server-dev-17

# Install cargo-pgrx
cargo install cargo-pgrx --version 0.16.1 --locked

# Initialize pgrx for your PostgreSQL versions
cargo pgrx init --pg16 /usr/bin/pg_config
cargo pgrx init --pg17 /usr/bin/pg_config
```

## Building Methods

### Method 1: Using Makefile (Recommended)

```bash
# Show available commands
make help

# Build for PostgreSQL 16 (default)
make build

# Build for PostgreSQL 17
make build PG_VERSION=17

# Build .deb package for PostgreSQL 16
make deb

# Build .deb package for PostgreSQL 17
make deb PG_VERSION=17

# Build .deb for all supported versions
make deb-all

# Run tests
make test

# Clean build artifacts
make clean
```

### Method 2: Using build-deb.sh Script

```bash
# Make script executable
chmod +x build-deb.sh

# Build for PostgreSQL 16 (default)
./build-deb.sh

# Build for PostgreSQL 17
./build-deb.sh 17

# Build for PostgreSQL 16
./build-deb.sh 16
```

### Method 3: Using Cargo Directly

```bash
# Build extension
cargo build --release --features pg16

# Or for PostgreSQL 17
cargo build --release --features pg17

# Install to system
cargo pgrx install --release
```

## Output Files

After building, you'll get:

### .deb Package
```
postgresql-16-rule-engine_1.0.0_amd64.deb
postgresql-17-rule-engine_1.0.0_amd64.deb
```

### Shared Library
```
target/release/librule_engine_postgre_extensions.so
```

## Installing the .deb Package

```bash
# Install the package
sudo dpkg -i postgresql-16-rule-engine_1.0.0_amd64.deb

# Fix dependencies if needed
sudo apt-get install -f

# Verify installation
psql -c "CREATE EXTENSION rule_engine_postgre_extensions;"
psql -c "SELECT rule_engine_version();"
```

## Building for Multiple Architectures

### For AMD64 (x86_64) - Default
```bash
make deb
```

### For ARM64 (aarch64)
```bash
# Install cross-compilation tools
rustup target add aarch64-unknown-linux-gnu
sudo apt-get install gcc-aarch64-linux-gnu

# Build
cargo build --release --target aarch64-unknown-linux-gnu --features pg16
```

## Building Docker Image

```bash
# Build image
make docker-build

# Or manually
docker build -t rule-engine-postgres:1.0.0 .

# Run container
make docker-run

# Or manually
docker-compose up -d
```

## Continuous Integration Build

The project includes GitHub Actions workflows for automated builds:

- **CI**: `.github/workflows/ci.yml` - Tests on every push
- **Release**: `.github/workflows/release.yml` - Builds packages on tag push

To trigger a release build:
```bash
git tag v1.0.0
git push origin v1.0.0
```

## Package Structure

The `.deb` package contains:

```
/usr/lib/postgresql/16/lib/
  └── rule_engine_postgre_extensions.so

/usr/share/postgresql/16/extension/
  ├── rule_engine_postgre_extensions.control
  ├── rule_engine_postgre_extensions--0.1.0.sql
  └── rule_engine_postgre_extensions--1.0.0.sql

/usr/share/doc/postgresql-16-rule-engine/
  ├── README.md
  ├── DEPLOYMENT.md
  └── LICENSE
```

## Uploading to GitHub Releases

After building packages:

```bash
# Create release on GitHub
gh release create v1.0.0 \
  postgresql-16-rule-engine_1.0.0_amd64.deb \
  postgresql-17-rule-engine_1.0.0_amd64.deb \
  --title "v1.0.0" \
  --notes "Production release with PostgreSQL 16 and 17 support"
```

## Publishing to PGXN

```bash
# Create PGXN distribution
make clean
cargo build --release
zip -r rule_engine_postgre_extensions-1.0.0.zip \
  src/ \
  Cargo.toml \
  META.json \
  rule_engine_postgre_extensions.control \
  rule_engine_postgre_extensions--*.sql \
  README.md \
  LICENSE

# Upload to PGXN
# https://manager.pgxn.org/upload
```

## Troubleshooting

### Error: "cannot find -lpq"
```bash
sudo apt-get install postgresql-server-dev-16
```

### Error: "cargo-pgrx not found"
```bash
cargo install cargo-pgrx --version 0.16.1 --locked
```

### Error: "pg_config not found"
```bash
export PATH="/usr/lib/postgresql/16/bin:$PATH"
cargo pgrx init --pg16 /usr/lib/postgresql/16/bin/pg_config
```

### Permission Denied
```bash
chmod +x build-deb.sh
chmod +x install.sh
```

### Missing Dependencies in .deb
Edit `build-deb.sh` and add to `Depends:` field:
```bash
Depends: postgresql-16, libc6, libssl3
```

## Version Management

To update version number:

1. Update `Cargo.toml`:
   ```toml
   version = "1.0.1"
   ```

2. Update `build-deb.sh`:
   ```bash
   VERSION="1.0.1"
   ```

3. Update `META.json`:
   ```json
   "version": "1.0.1"
   ```

4. Create new SQL file:
   ```bash
   cp rule_engine_postgre_extensions--1.0.0.sql \
      rule_engine_postgre_extensions--1.0.1.sql
   ```

5. Rebuild:
   ```bash
   make clean
   make deb-all
   ```

## Next Steps

- [Installation Guide](README.md#quick-start)
- [Deployment Guide](DEPLOYMENT.md)
- [Distribution Guide](DISTRIBUTION.md)
- [Docker Guide](DOCKER.md)
