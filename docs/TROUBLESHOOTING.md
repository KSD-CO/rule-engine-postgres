# 🔧 Troubleshooting Guide

Common issues and solutions for rule-engine-postgres.

---

## Table of Contents

- [Installation Issues](#installation-issues)
- [Extension Loading Issues](#extension-loading-issues)
- [Runtime Errors](#runtime-errors)
- [Performance Issues](#performance-issues)
- [Docker Issues](#docker-issues)
- [Build from Source Issues](#build-from-source-issues)
- [Getting Help](#getting-help)

---

## Installation Issues

### ❌ "Extension not found" after installation

**Error:**
```sql
ERROR:  extension "rule_engine_postgre_extensions" is not available
DETAIL:  Could not open extension control file "/usr/share/postgresql/16/extension/rule_engine_postgre_extensions.control": No such file or directory
```

**Cause:** Extension files not installed correctly.

**Solution 1: Verify installation**
```bash
# Check if files exist
ls -l /usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so
ls -l /usr/share/postgresql/16/extension/rule_engine_postgre_extensions*

# If files are missing, reinstall
sudo dpkg -i postgresql-16-rule-engine_1.5.0_amd64.deb

# Or for RPM:
sudo rpm -i postgresql16-rule-engine-1.5.0-1.x86_64.rpm
```

**Solution 2: Check PostgreSQL version**
```bash
# Your package must match PostgreSQL version
psql --version
# PostgreSQL 16.x → use postgresql-16-rule-engine package
# PostgreSQL 17.x → use postgresql-17-rule-engine package
```

**Solution 3: Restart PostgreSQL**
```bash
sudo systemctl restart postgresql
# or
sudo systemctl restart postgresql-16
```

---

### ❌ "Permission denied" when installing

**Error:**
```bash
ERROR:  could not load library "/usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so": Permission denied
```

**Cause:** File permissions are incorrect.

**Solution:**
```bash
# Fix permissions
sudo chmod 755 /usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so
sudo chown postgres:postgres /usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so

# Restart PostgreSQL
sudo systemctl restart postgresql
```

---

### ❌ Package dependency errors (Ubuntu/Debian)

**Error:**
```bash
dpkg: dependency problems prevent configuration of postgresql-16-rule-engine:
 postgresql-16-rule-engine depends on postgresql-16
```

**Solution:**
```bash
# Install dependencies
sudo apt-get install -f

# Or install PostgreSQL 16 first
sudo apt-get install postgresql-16
sudo dpkg -i postgresql-16-rule-engine_1.5.0_amd64.deb
```

---

### ❌ Wrong architecture error

**Error:**
```bash
postgresql-16-rule-engine_1.5.0_amd64.deb: wrong architecture 'amd64'
```

**Cause:** Trying to install amd64 package on ARM system.

**Solution:**
```bash
# Check your architecture
uname -m
# x86_64 → use amd64 package
# aarch64/arm64 → need to build from source

# For ARM, build from source:
# See "Build from Source" in INSTALLATION.md
```

---

## Extension Loading Issues

### ❌ "Could not load library"

**Error:**
```sql
ERROR:  could not load library "/usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so":
  /usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so: undefined symbol: ...
```

**Cause:** Library compiled for different PostgreSQL version.

**Solution:**
```bash
# Check PostgreSQL version
psql --version

# Reinstall matching version
# For PostgreSQL 16:
sudo dpkg -i postgresql-16-rule-engine_1.5.0_amd64.deb

# For PostgreSQL 17:
sudo dpkg -i postgresql-17-rule-engine_1.5.0_amd64.deb

# Restart
sudo systemctl restart postgresql
```

---

### ❌ Extension already exists in different database

**Error:**
```sql
ERROR:  extension "rule_engine_postgre_extensions" already exists
```

**This is normal!** Extensions can be created in multiple databases.

**Solution:** If you want to reinstall:
```sql
-- Drop from current database
DROP EXTENSION IF EXISTS rule_engine_postgre_extensions CASCADE;

-- Create again
CREATE EXTENSION rule_engine_postgre_extensions;
```

---

### ❌ CREATE EXTENSION hangs or takes too long

**Cause:** Loading large extension for first time.

**Solution:** Be patient, first load can take 5-10 seconds. If it hangs for >30 seconds:

```sql
-- Cancel the query (Ctrl+C in psql)
-- Check PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-16-main.log

-- Try in a simpler database
CREATE DATABASE test_db;
\c test_db
CREATE EXTENSION rule_engine_postgre_extensions;
```

---

## Runtime Errors

### ❌ "Database error: InvalidPosition"

**Error:**
```sql
ERROR:  Database error: Database error: InvalidPosition
```

**Cause:** Bug in version 1.5.0 when using `rule_save()` with `NULL` version on new rules.

**Solution 1: Provide explicit version**
```sql
-- Instead of NULL, provide a version
SELECT rule_save(
    'my_rule',
    'rule "Test" { when true then Result = 1; }',
    '1.0.0',  -- ✅ Explicit version
    'Description',
    'Notes'
);
```

**Solution 2: Apply bug fix**

This bug has been fixed! Update your extension:
```bash
# Update the extension files
sudo ./update-extension.sh  # If you built from source

# Or download latest release
wget https://github.com/KSD-CO/rule-engine-postgres/releases/download/v1.5.1/postgresql-16-rule-engine_1.5.1_amd64.deb
sudo dpkg -i postgresql-16-rule-engine_1.5.1_amd64.deb
sudo systemctl restart postgresql
```

---

### ❌ "Invalid JSON format" errors

**Error:**
```sql
ERROR:  ERR006: Invalid JSON format in facts
```

**Cause:** Malformed JSON in facts parameter.

**Solution:**
```sql
-- ❌ WRONG: Unquoted keys, trailing comma
SELECT run_rule_engine(
    '{Order: {total: 100,}}',
    '...'
);

-- ✅ CORRECT: Proper JSON
SELECT run_rule_engine(
    '{"Order": {"total": 100}}',
    '...'
);

-- Tip: Use jsonb type to validate
SELECT '{"Order": {"total": 100}}'::jsonb;  -- Will error if invalid
```

---

### ❌ "Input too large" errors

**Error:**
```sql
ERROR:  ERR003: Facts JSON exceeds maximum size (1MB)
ERROR:  ERR004: Rules GRL exceeds maximum size (1MB)
```

**Cause:** Input data exceeds 1MB limit.

**Solution 1: Split into smaller chunks**
```sql
-- Instead of one huge rule, split into multiple rules
SELECT rule_save('rule_part_1', '...', '1.0.0', '...', '...');
SELECT rule_save('rule_part_2', '...', '1.0.0', '...', '...');

-- Execute them separately or use rule sets
```

**Solution 2: Optimize JSON**
```sql
-- Remove unnecessary whitespace
-- ❌ Large:
'{"Order": { "total": 100,  "items": [ ... ] }}'

-- ✅ Compact:
'{"Order":{"total":100,"items":[...]}}'
```

---

### ❌ "Version already exists" error

**Error:**
```sql
ERROR:  Invalid input: Version 1.0.0 already exists for rule. Use a different version number.
```

**Cause:** Trying to save same version twice.

**Solution:**
```sql
-- Use a different version number
SELECT rule_save(
    'my_rule',
    'rule "Updated" { ... }',
    '1.0.1',  -- ✅ Increment version
    'Updated rule',
    'Changes made'
);

-- Or use NULL to auto-increment
SELECT rule_save(
    'my_rule',
    'rule "Updated" { ... }',
    NULL,  -- ✅ Auto-increments to 1.0.1
    'Updated rule',
    'Changes made'
);
```

---

### ❌ "Cannot delete default version" error

**Error:**
```sql
ERROR:  Cannot delete default version. Activate another version first.
```

**Cause:** Trying to delete the currently active version.

**Solution:**
```sql
-- First, activate a different version
SELECT rule_activate('my_rule', '2.0.0');

-- Then delete old version
SELECT rule_delete('my_rule', '1.0.0');
```

---

## Performance Issues

### ⚠️ Rules executing slowly

**Symptom:** Rules that used to take 1-2ms now take 100ms+.

**Diagnosis:**
```sql
-- Check execution stats
SELECT * FROM rule_execution_stats
WHERE rule_name = 'slow_rule'
ORDER BY executed_at DESC LIMIT 10;

-- Look for:
-- - Increasing execution_time_ms
-- - Error messages
-- - Large facts_modified counts
```

**Common causes and solutions:**

#### 1. Complex nested rules

```sql
-- ❌ BAD: Too many nested conditions
rule "Complex" {
    when
        Order.items[0].product.category.parent.name == "Electronics" &&
        Order.items[0].product.price > 100 &&
        Customer.history.orders[0].total > 1000 &&
        ...
    then ...
}

-- ✅ BETTER: Flatten the data first
-- Pre-compute values in application:
{
  "Order": {
    "hasElectronics": true,
    "highValueItem": true
  },
  "Customer": {
    "highValueHistory": true
  }
}
```

#### 2. Too many rules firing

```sql
-- Use salience to control order
rule "HighPriority" salience 100 { ... }
rule "MediumPriority" salience 50 { ... }
rule "LowPriority" salience 1 { ... }

-- Use no-loop to prevent infinite loops
rule "NoLoop" no-loop { ... }
```

#### 3. Large JSON objects

```sql
-- ❌ BAD: Passing entire 10MB customer object
SELECT run_rule_engine(
    (SELECT row_to_json(customer.*) FROM customers WHERE id = 123),
    '...'
);

-- ✅ BETTER: Pass only needed fields
SELECT run_rule_engine(
    json_build_object(
        'Customer', json_build_object(
            'tier', c.tier,
            'totalSpent', c.total_spent
        )
    )::text,
    '...'
) FROM customers c WHERE id = 123;
```

---

### ⚠️ High memory usage

**Symptom:** PostgreSQL using excessive memory.

**Solution:**
```sql
-- Check for memory leaks in rules
-- Use smaller fact objects
-- Avoid infinite rule loops

-- Monitor memory
SELECT
    pg_size_pretty(pg_database_size(current_database())) as db_size,
    pg_size_pretty(pg_total_relation_size('rule_execution_stats')) as stats_size;

-- Clean up old stats
DELETE FROM rule_execution_stats WHERE executed_at < NOW() - INTERVAL '30 days';
VACUUM rule_execution_stats;
```

---

## Docker Issues

### ❌ Container won't start

**Error:**
```bash
docker: Error response from daemon: Conflict. The container name "/rule-engine-postgres" is already in use.
```

**Solution:**
```bash
# Remove old container
docker rm -f rule-engine-postgres

# Or use a different name
docker run -d --name rule-engine-pg2 ...
```

---

### ❌ "Connection refused" from host

**Error:**
```bash
psql: error: connection to server at "localhost" (127.0.0.1), port 5432 failed: Connection refused
```

**Cause:** Port not published or container not running.

**Solution:**
```bash
# Check if container is running
docker ps | grep rule-engine-postgres

# Check if port is mapped
docker port rule-engine-postgres
# Should show: 5432/tcp -> 0.0.0.0:5432

# If not running, start it
docker start rule-engine-postgres

# If port not mapped, recreate with -p flag
docker rm -f rule-engine-postgres
docker run -d --name rule-engine-postgres -p 5432:5432 ...
```

---

### ❌ Data lost after container restart

**Cause:** No volume mounted.

**Solution:**
```bash
# Use a named volume
docker run -d \
  --name rule-engine-postgres \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=postgres \
  -v pgdata:/var/lib/postgresql/data \  # ✅ Add this
  jamesvu/rule-engine-postgres:latest

# Or use a bind mount
docker run -d \
  --name rule-engine-postgres \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=postgres \
  -v /home/user/pgdata:/var/lib/postgresql/data \  # ✅ Add this
  jamesvu/rule-engine-postgres:latest
```

---

## Build from Source Issues

### ❌ "cargo-pgrx not found"

**Error:**
```bash
cargo: 'pgrx' is not a cargo command
```

**Solution:**
```bash
# Install cargo-pgrx
cargo install cargo-pgrx --version 0.16.1 --locked

# Add to PATH if needed
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify
cargo pgrx --version
```

---

### ❌ Rust version too old

**Error:**
```bash
error: package `pgrx v0.16.1` cannot be built because it requires rustc 1.75.0 or newer
```

**Solution:**
```bash
# Update Rust
rustup update stable

# Verify version
rustc --version
# Should show 1.75.0 or higher

# If still old, install newer version
rustup install stable
rustup default stable
```

---

### ❌ "pg_config not found"

**Error:**
```bash
error: could not execute process `pg_config --version`
```

**Solution:**
```bash
# Ubuntu/Debian
sudo apt-get install postgresql-server-dev-16

# RHEL/Rocky
sudo dnf install postgresql16-devel

# macOS
brew install postgresql@16

# Verify
pg_config --version
```

---

### ❌ Linker errors during build

**Error:**
```bash
error: linking with `cc` failed: exit status: 1
  = note: /usr/bin/ld: cannot find -lpq
```

**Solution:**
```bash
# Ubuntu/Debian
sudo apt-get install libpq-dev

# RHEL/Rocky
sudo dnf install postgresql-devel

# macOS
brew install postgresql@16
export LDFLAGS="-L/opt/homebrew/opt/postgresql@16/lib"
export CPPFLAGS="-I/opt/homebrew/opt/postgresql@16/include"
```

---

### ❌ "Permission denied" during cargo pgrx install

**Error:**
```bash
Error: failed writing file to `/usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so`
Permission denied (os error 13)
```

**Solution:**
```bash
# Use sudo for install
sudo -E cargo pgrx install --release

# Or install to custom location
cargo pgrx install --release --pg-config ~/.pgconfig

# Then manually copy files
sudo cp target/release/librule_engine_postgres.so /usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so
```

---

## Common Error Codes

| Code | Error | Solution |
|------|-------|----------|
| **ERR001** | Empty facts JSON | Provide valid JSON: `'{"key":"value"}'` |
| **ERR002** | Empty rules GRL | Provide valid GRL: `'rule "Name" { ... }'` |
| **ERR003** | Facts too large (>1MB) | Split data or optimize JSON |
| **ERR004** | Rules too large (>1MB) | Split into multiple rule files |
| **ERR005** | Invalid facts JSON | Fix JSON syntax, validate with `::jsonb` cast |
| **ERR006** | Invalid GRL syntax | Check rule syntax, missing braces/quotes |
| **ERR007** | Rule parsing failed | Verify GRL syntax (when/then blocks) |
| **ERR008** | Rule compilation failed | Check rule conditions and actions |
| **ERR009** | Engine initialization failed | Restart PostgreSQL, check logs |
| **ERR010** | Rule processing failed | Check for infinite loops, memory issues |
| **ERR011** | Execution failed | Review rule logic, check fact values |
| **ERR012** | Serialization failed | Verify output JSON is valid |

---

## Getting More Details

### Enable Detailed Logging

```sql
-- Check current log level
SHOW log_min_messages;

-- Enable debug logging
SET log_min_messages = DEBUG1;

-- Run your query
SELECT run_rule_engine(...);

-- Check logs
-- Ubuntu/Debian:
sudo tail -f /var/log/postgresql/postgresql-16-main.log

-- RHEL/Rocky:
sudo tail -f /var/lib/pgsql/16/data/log/postgresql-*.log
```

### Collect Diagnostic Information

```bash
# System information
uname -a
lsb_release -a

# PostgreSQL version
psql --version
pg_config --version

# Extension information
psql -U postgres -d postgres -c "
SELECT * FROM pg_extension WHERE extname = 'rule_engine_postgre_extensions';
"

# File locations
ls -l /usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so
ls -l /usr/share/postgresql/16/extension/rule_engine_postgre_extensions*

# Recent errors
sudo tail -100 /var/log/postgresql/postgresql-16-main.log
```

---

## Getting Help

### Before Asking for Help

1. **Check this guide** for your specific error
2. **Search existing issues** on [GitHub Issues](https://github.com/KSD-CO/rule-engine-postgres/issues)
3. **Collect diagnostic information** (see above)

### Where to Get Help

- **🐛 Bug Reports**: [GitHub Issues](https://github.com/KSD-CO/rule-engine-postgres/issues/new)
  - Include: OS, PostgreSQL version, error message, steps to reproduce

- **💬 Questions**: [GitHub Discussions](https://github.com/KSD-CO/rule-engine-postgres/discussions)
  - General questions, use cases, best practices

- **📧 Security Issues**: Email maintainer (see README)
  - Do NOT post security vulnerabilities publicly

### Issue Template

When reporting a bug, include:

```markdown
**Environment:**
- OS: Ubuntu 24.04
- PostgreSQL Version: 16.3
- Extension Version: 1.5.0
- Installation Method: Pre-built package / Docker / Source

**Error:**
```
[Paste full error message]
```

**Steps to Reproduce:**
1. Install extension
2. Run this SQL: `SELECT ...`
3. See error

**Expected Behavior:**
Should return ...

**Actual Behavior:**
Returns error ...

**Additional Context:**
- Works on PostgreSQL 16
- Fails on PostgreSQL 17
```

---

## Still Stuck?

If you've tried everything and still can't resolve the issue:

1. **Reinstall from scratch:**
   ```bash
   # Remove everything
   DROP EXTENSION rule_engine_postgre_extensions CASCADE;
   sudo dpkg -r postgresql-16-rule-engine

   # Reinstall
   curl -fsSL https://raw.githubusercontent.com/KSD-CO/rule-engine-postgres/main/quick-install.sh | bash
   ```

2. **Try Docker** (isolates environment issues):
   ```bash
   docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=postgres jamesvu/rule-engine-postgres:latest
   ```

3. **Open a GitHub issue** with full diagnostic information

---

**Last Updated:** 2025-12-11 | **Version:** 1.5.0
