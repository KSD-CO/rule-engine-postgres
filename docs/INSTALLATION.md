# 📦 Installation Guide

Complete installation instructions for all platforms and methods.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Method 1: Docker (Recommended for Testing)](#method-1-docker-recommended-for-testing)
- [Method 2: One-Liner Install Script](#method-2-one-liner-install-script)
- [Method 3: Pre-built Packages](#method-3-pre-built-packages)
- [Method 4: Build from Source](#method-4-build-from-source)
- [Verification](#verification)
- [Upgrading](#upgrading)
- [Uninstallation](#uninstallation)

---

## Prerequisites

### Required

| Component | Version | Check Command |
|-----------|---------|---------------|
| **PostgreSQL** | 16.x or 17.x | `psql --version` |
| **Operating System** | Linux, macOS, WSL2 | `uname -a` |

### Optional (for building from source)

| Component | Version | Check Command |
|-----------|---------|---------------|
| **Rust** | 1.75+ | `rustc --version` |
| **cargo-pgrx** | 0.16.1 | `cargo pgrx --version` |
| **Build tools** | gcc, make, pkg-config | `gcc --version` |

---

## Method 1: Docker (Recommended for Testing)

Perfect for:
- ✅ Quick testing and evaluation
- ✅ Development and CI/CD
- ✅ No system modifications
- ✅ Works on any platform

### Option A: Using Pre-built Image

```bash
# Pull the latest image
docker pull jamesvu/rule-engine-postgres:latest

# Run the container
docker run -d \
  --name rule-engine-postgres \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=postgres \
  jamesvu/rule-engine-postgres:latest

# Wait for startup
sleep 5

# Connect and verify
docker exec -it rule-engine-postgres psql -U postgres -d postgres -c "SELECT rule_engine_version();"
```

**Expected output:**
```
 rule_engine_version
---------------------
 1.5.0
(1 row)
```

### Option B: Using Docker Compose

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  postgres:
    image: jamesvu/rule-engine-postgres:latest
    container_name: rule-engine-postgres
    environment:
      POSTGRES_PASSWORD: postgres
      POSTGRES_USER: postgres
      POSTGRES_DB: ruleengine
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
```

**Start the service:**

```bash
docker-compose up -d

# Connect
docker-compose exec postgres psql -U postgres -d ruleengine
```

### Option C: Build Your Own Docker Image

```bash
# Clone the repository
git clone https://github.com/KSD-CO/rule-engine-postgres.git
cd rule-engine-postgres

# Build the image
docker build -t my-rule-engine-postgres .

# Run it
docker run -d \
  --name rule-engine-postgres \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=postgres \
  my-rule-engine-postgres
```

### Docker Tips

**Persist data:**
```bash
docker run -d \
  --name rule-engine-postgres \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=postgres \
  -v pgdata:/var/lib/postgresql/data \
  jamesvu/rule-engine-postgres:latest
```

**Access logs:**
```bash
docker logs rule-engine-postgres
```

**Stop and remove:**
```bash
docker stop rule-engine-postgres
docker rm rule-engine-postgres
```

---

## Method 2: One-Liner Install Script

Best for:
- ✅ Ubuntu/Debian systems
- ✅ Quick production setup
- ✅ Automatic version detection

### Ubuntu/Debian

```bash
curl -fsSL https://raw.githubusercontent.com/KSD-CO/rule-engine-postgres/main/quick-install.sh | bash
```

**What it does:**
1. Detects your OS (Ubuntu 20.04, 22.04, 24.04, Debian 11, 12)
2. Detects PostgreSQL version (16 or 17)
3. Downloads the correct `.deb` package
4. Installs the extension
5. Verifies installation

**Supported OS:**
- Ubuntu 20.04 LTS (Focal)
- Ubuntu 22.04 LTS (Jammy)
- Ubuntu 24.04 LTS (Noble)
- Debian 11 (Bullseye)
- Debian 12 (Bookworm)

### Manual Install Script Download

If you prefer to review before running:

```bash
# Download the script
curl -fsSL https://raw.githubusercontent.com/KSD-CO/rule-engine-postgres/main/quick-install.sh -o install.sh

# Review it
cat install.sh

# Make it executable
chmod +x install.sh

# Run it
./install.sh
```

---

## Method 3: Pre-built Packages

Best for:
- ✅ Production environments
- ✅ Air-gapped systems
- ✅ Specific version requirements

### Step 1: Download the Package

Go to [Releases](https://github.com/KSD-CO/rule-engine-postgres/releases/latest) and download the package for your system.

**Available packages:**
- `postgresql-16-rule-engine_1.5.0_amd64.deb` (Ubuntu/Debian, PostgreSQL 16)
- `postgresql-17-rule-engine_1.5.0_amd64.deb` (Ubuntu/Debian, PostgreSQL 17)
- `postgresql16-rule-engine-1.5.0-1.x86_64.rpm` (RHEL/Rocky/AlmaLinux 8, PostgreSQL 16)
- `postgresql16-rule-engine-1.5.0-1.el9.x86_64.rpm` (RHEL/Rocky/AlmaLinux 9, PostgreSQL 16)

### Step 2: Install the Package

#### Ubuntu/Debian (.deb)

```bash
# Install the package
sudo dpkg -i postgresql-16-rule-engine_1.5.0_amd64.deb

# If dependencies are missing:
sudo apt-get install -f
```

**Installation locations:**
- Extension library: `/usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so`
- SQL files: `/usr/share/postgresql/16/extension/rule_engine_postgre_extensions--*.sql`
- Control file: `/usr/share/postgresql/16/extension/rule_engine_postgre_extensions.control`

#### RHEL/CentOS/Rocky Linux (.rpm)

```bash
# Install the package
sudo rpm -i postgresql16-rule-engine-1.5.0-1.x86_64.rpm

# Or using yum/dnf:
sudo dnf install postgresql16-rule-engine-1.5.0-1.x86_64.rpm
```

**Installation locations:**
- Extension library: `/usr/pgsql-16/lib/rule_engine_postgre_extensions.so`
- SQL files: `/usr/pgsql-16/share/extension/rule_engine_postgre_extensions--*.sql`
- Control file: `/usr/pgsql-16/share/extension/rule_engine_postgre_extensions.control`

#### Arch Linux (AUR)

```bash
# Using yay
yay -S postgresql-rule-engine

# Using paru
paru -S postgresql-rule-engine
```

### Step 3: Restart PostgreSQL

```bash
# Ubuntu/Debian
sudo systemctl restart postgresql

# RHEL/CentOS/Rocky
sudo systemctl restart postgresql-16
```

### Step 4: Enable the Extension

```sql
-- Connect to your database
sudo -u postgres psql -d your_database

-- Create the extension
CREATE EXTENSION IF NOT EXISTS rule_engine_postgre_extensions;

-- Verify
SELECT rule_engine_version();
```

---

## Method 4: Build from Source

Best for:
- ✅ Development and testing
- ✅ Custom modifications
- ✅ Unsupported platforms

### Step 1: Install Prerequisites

#### Ubuntu/Debian

```bash
# Install PostgreSQL development files
sudo apt-get update
sudo apt-get install -y \
    postgresql-server-dev-16 \
    build-essential \
    libssl-dev \
    pkg-config \
    curl

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Verify Rust version (must be 1.75+)
rustc --version
```

#### RHEL/CentOS/Rocky Linux

```bash
# Install PostgreSQL development files
sudo dnf install -y \
    postgresql16-devel \
    gcc \
    openssl-devel \
    pkg-config \
    curl

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

#### macOS

```bash
# Install PostgreSQL
brew install postgresql@16

# Install Rust (if not already installed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

### Step 2: Install cargo-pgrx

```bash
cargo install cargo-pgrx --version 0.16.1 --locked
```

**Note:** This may take 5-10 minutes on first install.

### Step 3: Clone and Build

```bash
# Clone the repository
git clone https://github.com/KSD-CO/rule-engine-postgres.git
cd rule-engine-postgres

# Initialize pgrx (only needed once)
cargo pgrx init --pg16 /usr/bin/pg_config

# Build and install
cargo pgrx install --release
```

**Expected output:**
```
Building extension with features pg16
Finished release [optimized] target(s) in 45.23s
Installing extension
Copying shared library to /usr/lib/postgresql/16/lib/
Copying SQL files to /usr/share/postgresql/16/extension/
✅ Installation complete!
```

### Step 4: Restart PostgreSQL

```bash
sudo systemctl restart postgresql
```

### Step 5: Enable the Extension

```sql
CREATE EXTENSION IF NOT EXISTS rule_engine_postgre_extensions;
SELECT rule_engine_version();
```

### Alternative Build Script

We provide a helper script that handles all the steps:

```bash
# Clone the repo
git clone https://github.com/KSD-CO/rule-engine-postgres.git
cd rule-engine-postgres

# Run the install script
sudo ./install.sh
```

**What it does:**
1. Checks prerequisites
2. Installs cargo-pgrx if needed
3. Builds the extension
4. Installs it to PostgreSQL
5. Restarts PostgreSQL
6. Verifies the installation

---

## Verification

After installation, verify the extension works:

### Basic Health Check

```sql
-- Connect to PostgreSQL
psql -U postgres -d postgres

-- Check version
SELECT rule_engine_version();
```

**Expected:** `1.5.0`

```sql
-- Run health check
SELECT rule_engine_health_check();
```

**Expected:** `{"status":"healthy","version":"1.5.0","timestamp":"2024-12-11T10:30:00Z"}`

### Test a Simple Rule

```sql
-- Execute a basic rule
SELECT run_rule_engine(
    '{"Order": {"total": 100}}',
    'rule "Test" { when Order.total > 50 then Order.valid = true; }'
)::jsonb;
```

**Expected:**
```json
{
  "Order": {
    "total": 100,
    "valid": true
  }
}
```

✅ **If all tests pass, installation is successful!**

---

## Upgrading

### From v1.4.x to v1.5.0

```sql
-- Connect to your database
psql -U postgres -d your_database

-- Upgrade the extension
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.5.0';

-- Verify new version
SELECT rule_engine_version();
```

### Upgrade Process for Pre-built Packages

#### Ubuntu/Debian

```bash
# Download new version
wget https://github.com/KSD-CO/rule-engine-postgres/releases/download/v1.5.0/postgresql-16-rule-engine_1.5.0_amd64.deb

# Install (will upgrade existing)
sudo dpkg -i postgresql-16-rule-engine_1.5.0_amd64.deb

# Restart PostgreSQL
sudo systemctl restart postgresql

# Upgrade in database
psql -U postgres -d your_database -c "ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.5.0';"
```

#### Docker

```bash
# Pull new image
docker pull jamesvu/rule-engine-postgres:latest

# Stop old container
docker stop rule-engine-postgres
docker rm rule-engine-postgres

# Run new container with same data volume
docker run -d \
  --name rule-engine-postgres \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=postgres \
  -v pgdata:/var/lib/postgresql/data \
  jamesvu/rule-engine-postgres:latest

# Upgrade in database
docker exec -it rule-engine-postgres psql -U postgres -d postgres -c "ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.5.0';"
```

### Upgrade Process for Source Build

```bash
# Pull latest code
cd rule-engine-postgres
git pull origin main

# Rebuild and install
cargo pgrx install --release

# Restart PostgreSQL
sudo systemctl restart postgresql

# Upgrade in database
psql -U postgres -d your_database -c "ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.5.0';"
```

---

## Uninstallation

### Remove from Database

```sql
-- Drop the extension from your database
DROP EXTENSION IF EXISTS rule_engine_postgre_extensions CASCADE;
```

### Remove Package

#### Ubuntu/Debian

```bash
sudo dpkg -r postgresql-16-rule-engine
```

#### RHEL/CentOS/Rocky

```bash
sudo rpm -e postgresql16-rule-engine
```

#### Source Build

```bash
# Remove files manually
sudo rm /usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so
sudo rm /usr/share/postgresql/16/extension/rule_engine_postgre_extensions*
```

#### Docker

```bash
docker stop rule-engine-postgres
docker rm rule-engine-postgres
docker rmi jamesvu/rule-engine-postgres:latest
```

---

## Platform-Specific Notes

### PostgreSQL from Different Sources

#### Official PostgreSQL APT Repository

```bash
# Add PostgreSQL repository
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get install postgresql-16

# Then install rule-engine-postgres using Method 2 or 3
```

#### PostgreSQL from Ubuntu Default Repos

```bash
# Check which version is available
apt-cache policy postgresql

# Install default PostgreSQL
sudo apt-get install postgresql

# Then install rule-engine-postgres using Method 2 or 3
```

### AWS RDS / Google Cloud SQL / Azure

**Note:** You cannot install custom extensions on managed PostgreSQL services (RDS, Cloud SQL, Azure Database).

**Alternatives:**
1. Use Docker on EC2/GCE/VM
2. Self-host PostgreSQL on VM
3. Use AWS RDS Custom (allows some extensions)

### macOS Specific

```bash
# If using Homebrew PostgreSQL
brew install postgresql@16
brew services start postgresql@16

# Find pg_config
which pg_config

# Use that path when building:
cargo pgrx install --pg-config /opt/homebrew/bin/pg_config --release
```

---

## Troubleshooting Installation

See [Troubleshooting Guide](TROUBLESHOOTING.md) for common installation issues.

**Quick fixes:**

### "Extension not found" after install

```bash
# Check if files exist
ls /usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so
ls /usr/share/postgresql/16/extension/rule_engine_postgre_extensions*

# If missing, reinstall
sudo dpkg -i postgresql-16-rule-engine_1.5.0_amd64.deb
```

### "Permission denied" errors

```bash
# Ensure correct permissions
sudo chmod 755 /usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so
sudo chmod 644 /usr/share/postgresql/16/extension/rule_engine_postgre_extensions*
```

### PostgreSQL won't start after install

```bash
# Check PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-16-main.log

# Common issue: wrong PostgreSQL version
# Uninstall and reinstall correct version
```

---

## Next Steps

- **[Quick Start](QUICKSTART.md)** - Run your first rule in 5 minutes
- **[Usage Guide](USAGE_GUIDE.md)** - Learn all features
- **[API Reference](api-reference.md)** - Function documentation
- **[Troubleshooting](TROUBLESHOOTING.md)** - Fix common issues

---

**Need help?** Open an issue on [GitHub](https://github.com/KSD-CO/rule-engine-postgres/issues)
