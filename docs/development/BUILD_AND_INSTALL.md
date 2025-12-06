# Guide to Build and Install Rust Extension for Postgres

## Prerequisites

- **Rust toolchain**: `rustc 1.70+`
- **cargo-pgrx**: `cargo install cargo-pgrx`
- **PostgreSQL**: 16 or 17 installed
- **System**: Linux or macOS (Apple Silicon supported)

## 1. Build the extension

Choose your PostgreSQL version:

### PostgreSQL 17

**Linux:**
```bash
cargo pgrx package --pg-config /usr/lib/postgresql/17/bin/pg_config
```

**macOS (Apple Silicon):**
```bash
export MACOSX_DEPLOYMENT_TARGET=15.0
cargo pgrx package --pg-config /opt/homebrew/opt/postgresql@17/bin/pg_config
```

### PostgreSQL 16

**Linux:**
```bash
cargo pgrx package --pg-config /usr/lib/postgresql/16/bin/pg_config
```

**macOS (Apple Silicon):**
```bash
export MACOSX_DEPLOYMENT_TARGET=15.0
cargo pgrx package --pg-config /opt/homebrew/opt/postgresql@16/bin/pg_config
```

> **Note**: For macOS Apple Silicon, always set `MACOSX_DEPLOYMENT_TARGET=15.0` to avoid linker errors.

## 2. Copy required files to Postgres system directories

After building, copy the files for your PostgreSQL version:

### PostgreSQL 17

**Linux:**
```bash
# Shared library
sudo cp target/release/rule_engine_postgre_extensions-pg17/usr/lib/postgresql/17/lib/rule_engine_postgre_extensions.so \
  /usr/lib/postgresql/17/lib/

# Control file
sudo cp rule_engine_postgre_extensions.control /usr/share/postgresql/17/extension/

# SQL migration files (all versions)
sudo cp rule_engine_postgre_extensions--*.sql /usr/share/postgresql/17/extension/
```

**macOS:**
```bash
# Shared library
sudo cp target/release/rule_engine_postgre_extensions-pg17/opt/homebrew/opt/postgresql@17/lib/postgresql/rule_engine_postgre_extensions.dylib \
  /opt/homebrew/opt/postgresql@17/lib/postgresql/

# Control file
sudo cp rule_engine_postgre_extensions.control /opt/homebrew/opt/postgresql@17/share/postgresql@17/extension/

# SQL migration files (all versions)
sudo cp rule_engine_postgre_extensions--*.sql /opt/homebrew/opt/postgresql@17/share/postgresql@17/extension/
```

### PostgreSQL 16

**Linux:**
```bash
# Shared library
sudo cp target/release/rule_engine_postgre_extensions-pg16/usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so \
  /usr/lib/postgresql/16/lib/

# Control file
sudo cp rule_engine_postgre_extensions.control /usr/share/postgresql/16/extension/

# SQL migration files (all versions)
sudo cp rule_engine_postgre_extensions--*.sql /usr/share/postgresql/16/extension/
```

**macOS:**
```bash
# Shared library
sudo cp target/release/rule_engine_postgre_extensions-pg16/opt/homebrew/opt/postgresql@16/lib/postgresql/rule_engine_postgre_extensions.dylib \
  /opt/homebrew/opt/postgresql@16/lib/postgresql/

# Control file
sudo cp rule_engine_postgre_extensions.control /opt/homebrew/opt/postgresql@16/share/postgresql@16/extension/

# SQL migration files (all versions)
sudo cp rule_engine_postgre_extensions--*.sql /opt/homebrew/opt/postgresql@16/share/postgresql@16/extension/
```

## 3. Restart Postgres (if needed)

**Linux:**
```bash
# PostgreSQL 17
sudo systemctl restart postgresql@17

# PostgreSQL 16
sudo systemctl restart postgresql@16
```

**macOS:**
```bash
# PostgreSQL 17
brew services restart postgresql@17

# PostgreSQL 16
brew services restart postgresql@16
```

## 4. Create the extension in psql

Connect to your database:

**Linux:**
```bash
# PostgreSQL 17
sudo -u postgres psql

# PostgreSQL 16
sudo -u postgres psql
```

**macOS:**
```bash
# PostgreSQL 17
psql -d postgres

# PostgreSQL 16
psql -d postgres
```

Then create the extension:
```sql
-- Drop existing version if upgrading
DROP EXTENSION IF EXISTS rule_engine_postgre_extensions CASCADE;

-- Create extension
CREATE EXTENSION rule_engine_postgre_extensions;

-- Verify installation
SELECT extname, extversion FROM pg_extension WHERE extname = 'rule_engine_postgre_extensions';
-- Should show: rule_engine_postgre_extensions | 1.1.0

-- List available functions
\df *rule*
```

## 5. Test the extension

Verify all functions are available:
```sql
-- List all extension functions
\df *rule*

-- Should show 13 functions including:
-- Core functions (6): run_rule_engine, query_backward_chaining, etc.
-- Rule Repository (7): rule_save, rule_get, rule_execute_by_name, etc.
```

## 6. Initialize Rule Repository (v1.1.0+)

Set up the Rule Repository schema:
```sql
-- The schema is automatically created when extension is installed
-- Verify tables exist:
\dt rule_*

-- Should show:
-- rule_definitions, rule_versions, rule_tags, rule_audit_log

-- Check catalog view:
SELECT * FROM rule_catalog;
```

## 7. Test basic functionality

**Legacy inline rules:**
```sql
SELECT run_rule_engine(
    '{"a":1}',
    'rule "Test" { when a == 1 then print("OK") }'
);
```

**Recommended: Stored rules (v1.1.0+):**
```sql
-- Save a rule
SELECT rule_save(
    'test_rule',
    'rule "Test" { when a == 1 then b = "OK"; }',
    '1.0.0',
    'Test rule',
    'Initial version'
);

-- Execute the stored rule
SELECT rule_execute_by_name('test_rule', '{"a":1}', NULL);

-- Test backward chaining
SELECT rule_can_prove_by_name(
    'test_rule',
    '{"a":1}',
    'b == "OK"',
    NULL
);
-- Should return: true
```

---

## Troubleshooting

### macOS: Linker errors during build
If you see `ld: unknown options: --export-dynamic`:
```bash
export MACOSX_DEPLOYMENT_TARGET=15.0
# Then rebuild with cargo pgrx package
```

### Extension not found after installation

**Check extension files exist:**

PostgreSQL 17:
```bash
# macOS
ls -la /opt/homebrew/opt/postgresql@17/share/postgresql@17/extension/rule_engine*
ls -la /opt/homebrew/opt/postgresql@17/lib/postgresql/rule_engine*

# Linux
ls -la /usr/share/postgresql/17/extension/rule_engine*
ls -la /usr/lib/postgresql/17/lib/rule_engine*
```

PostgreSQL 16:
```bash
# macOS
ls -la /opt/homebrew/opt/postgresql@16/share/postgresql@16/extension/rule_engine*
ls -la /opt/homebrew/opt/postgresql@16/lib/postgresql/rule_engine*

# Linux
ls -la /usr/share/postgresql/16/extension/rule_engine*
ls -la /usr/lib/postgresql/16/lib/rule_engine*
```

**Restart PostgreSQL:**
```bash
# macOS
brew services restart postgresql@17  # or postgresql@16

# Linux
sudo systemctl restart postgresql@17  # or postgresql@16
```

### Version mismatch or upgrade issues
```sql
-- Check current version
SELECT extversion FROM pg_extension WHERE extname = 'rule_engine_postgre_extensions';

-- If version is old (e.g., 0.1.0 or 1.0.0), upgrade:
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.1.0';

-- If upgrade fails, recreate:
DROP EXTENSION IF EXISTS rule_engine_postgre_extensions CASCADE;
CREATE EXTENSION rule_engine_postgre_extensions;

-- Verify new version
SELECT extversion FROM pg_extension WHERE extname = 'rule_engine_postgre_extensions';
-- Should show: 1.1.0
```

### PostgreSQL version detection
```sql
-- Check your PostgreSQL version
SELECT version();

-- Should show:
-- PostgreSQL 17.x ... or PostgreSQL 16.x ...
```

### Build for multiple PostgreSQL versions
If you want to support both PG16 and PG17, build separately:
```bash
# Build for PG17
export MACOSX_DEPLOYMENT_TARGET=15.0  # macOS only
cargo pgrx package --pg-config /path/to/pg17/bin/pg_config

# Build for PG16
export MACOSX_DEPLOYMENT_TARGET=15.0  # macOS only
cargo pgrx package --pg-config /path/to/pg16/bin/pg_config

# Install both versions to their respective directories
```

### Permission denied errors
If you get permission errors during installation:
```bash
# Ensure you have sudo access
sudo -v

# Or install to user directory (not recommended for production)
# Check PostgreSQL extension directory ownership:
ls -ld /usr/share/postgresql/*/extension/
```

---

For more help, check the main [README.md](../../README.md) or open an issue on GitHub.
