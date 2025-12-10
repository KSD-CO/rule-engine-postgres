# Upgrade Instructions - Complete Guide

Complete guide for upgrading Rule Engine PostgreSQL Extension between versions.

---

## 📊 Version Matrix

| From Version | To Version | Method | Migration File | Breaking Changes |
|--------------|------------|--------|----------------|------------------|
| 1.3.0 | 1.4.0 | ALTER EXTENSION | 004_developer_experience.sql | ❌ None |
| 1.4.0 | 1.5.0 | ALTER EXTENSION | 005_webhooks.sql | ❌ None |
| Any | Latest | Fresh install | --1.5.0.sql | N/A |

---

## 🎯 Quick Reference

### Check Current Version

```sql
-- Extension version
SELECT extversion FROM pg_extension
WHERE extname = 'rule_engine_postgre_extensions';

-- Available versions
SELECT * FROM pg_available_extension_versions
WHERE name = 'rule_engine_postgre_extensions';
```

### Latest Version
**Current:** `1.5.0` (December 10, 2025)

### Upgrade Process
```bash
# 1. Install new extension files
cd /path/to/rule-engine-postgre-extensions
./install.sh

# 2. Run upgrade in PostgreSQL
psql -d your_database
```
```sql
-- 3. Upgrade extension
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.5.0';
```

---

## 📖 Upgrade Methods

### Method 1: ALTER EXTENSION (Recommended)

**Pros:**
- ✅ Automatic dependency handling
- ✅ Transaction-safe
- ✅ PostgreSQL managed
- ✅ Fastest method
- ✅ Official PostgreSQL extension upgrade mechanism

**Cons:**
- ❌ Requires extension installed
- ❌ Must have upgrade script available

**Usage:**
```bash
# Step 1: Install new files first
cd /path/to/rule-engine-postgre-extensions
./install.sh
```

```sql
-- Step 2: Then upgrade extension
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO 'X.Y.Z';
```

**Important:** You must run `./install.sh` first to copy the new shared library (.so) and upgrade SQL scripts to the PostgreSQL extension directory.

---

### Method 2: Fresh Install

**Pros:**
- ✅ Clean slate
- ✅ Latest version guaranteed
- ✅ No migration issues

**Cons:**
- ❌ Loses existing data
- ❌ Requires backup/restore
- ❌ Downtime required

**Usage:**
```sql
DROP EXTENSION rule_engine_postgre_extensions CASCADE;
CREATE EXTENSION rule_engine_postgre_extensions VERSION '1.5.0';
```

---

## 🔄 Step-by-Step Upgrade Guides

### Upgrade: v1.3.0 → v1.4.0

**What's New:**
- Phase 2: Developer Experience
- Testing Framework (test cases, assertions, coverage)
- Validation & Linting (syntax checking, best practices)
- Debugging Tools (execution traces, variable inspection)
- Rule Templates (reusable patterns with parameters)

**Prerequisites:**
- ✅ PostgreSQL 12+
- ✅ Current version: 1.3.0
- ✅ Backup completed
- ✅ ~5 MB free disk space

**Step 1: Backup**
```bash
pg_dump -Fc your_database > backup_before_1.4.0.dump
```

**Step 2: Verify Current Version**
```sql
SELECT extversion FROM pg_extension
WHERE extname = 'rule_engine_postgre_extensions';
-- Should return: 1.3.0
```

**Step 3: Install New Extension Files**
```bash
# Run install script to copy new .so and SQL files
cd /path/to/rule-engine-postgre-extensions
./install.sh
```

**Step 4: Run Upgrade**
```sql
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.4.0';
```

**Step 5: Verify Upgrade**
```sql
-- Check version
SELECT extversion FROM pg_extension
WHERE extname = 'rule_engine_postgre_extensions';
-- Should return: 1.4.0

-- Check new tables
\dt rule_test* rule_debug* rule_template*

-- Check new functions
\df rule_test* rule_validate rule_lint rule_debug* rule_template*

-- Check new views
\dv test_suite_summary recent_test_failures template_usage_stats
```

**Step 6: Test New Features**
```sql
-- Test validation
SELECT rule_validate('rule Test { when x > 10 then y = 20; }');

-- List templates
SELECT * FROM rule_template_list();

-- Create a test case
SELECT rule_test_create(
    'my_first_test',
    'my_rule',
    '{"input": "data"}'::JSONB
);
```

**Time Required:** ~2-5 minutes
**Downtime:** ~30 seconds

---

### Upgrade: v1.4.0 → v1.5.0

**What's New:**
- Phase 4.2: Webhook Support
- HTTP callouts from rules
- Webhook registration & management
- Secret storage
- Retry logic with exponential backoff
- Monitoring & analytics

**Prerequisites:**
- ✅ PostgreSQL 12+
- ✅ Current version: 1.4.0
- ✅ Backup completed
- ✅ ~5 MB free disk space
- 🟡 Optional: HTTP extension for actual HTTP calls

**Step 1: Backup**
```bash
pg_dump -Fc your_database > backup_before_1.5.0.dump
```

**Step 2: Verify Current Version**
```sql
SELECT extversion FROM pg_extension
WHERE extname = 'rule_engine_postgre_extensions';
-- Should return: 1.4.0
```

**Step 3: Install New Extension Files**
```bash
# Run install script to copy new .so and SQL files
cd /path/to/rule-engine-postgre-extensions
./install.sh
```

**Step 4: (Optional) Install HTTP Extension**
```sql
-- For actual HTTP calls (optional)
CREATE EXTENSION IF NOT EXISTS http;
```

**Step 5: Run Upgrade**
```sql
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.5.0';
```

**Step 6: Verify Upgrade**
```sql
-- Check version
SELECT extversion FROM pg_extension
WHERE extname = 'rule_engine_postgre_extensions';
-- Should return: 1.5.0

-- Check new tables
\dt rule_webhook*

-- Check new functions
\df rule_webhook*

-- Check new views
\dv webhook*
```

**Step 7: Test New Features**
```sql
-- Register a test webhook
SELECT rule_webhook_register(
    'test_webhook',
    'https://webhook.site/unique-url',
    'POST',
    '{"Content-Type": "application/json"}'::JSONB,
    'Test webhook'
);

-- View registered webhooks
SELECT * FROM rule_webhook_list();

-- Enqueue a test call
SELECT rule_webhook_call(
    1,
    '{"message": "Test from rule engine"}'::JSONB
);

-- Check status
SELECT * FROM webhook_status_summary;
```

**Time Required:** ~2-5 minutes
**Downtime:** ~30 seconds

---

### Upgrade: v1.3.0 → v1.5.0 (Multi-step)

If you want to jump from 1.3.0 directly to 1.5.0:

```bash
# Step 1: Install new extension files
cd /path/to/rule-engine-postgre-extensions
./install.sh
```

```sql
-- Step 2: Run sequential upgrades
-- 1.3.0 → 1.4.0
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.4.0';

-- 1.4.0 → 1.5.0
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.5.0';
```

**Note:**
- You must run `./install.sh` first to copy all necessary files (both 1.4.0 and 1.5.0 upgrade scripts)
- PostgreSQL will automatically apply all intermediate upgrade scripts in sequence

---

## 🔍 Verification Checklist

After any upgrade, verify:

### ✅ Version Check
```sql
SELECT extversion FROM pg_extension
WHERE extname = 'rule_engine_postgre_extensions';
```

### ✅ Object Count
```sql
-- Count tables
SELECT COUNT(*) FROM information_schema.tables
WHERE table_schema = 'public' AND table_name LIKE 'rule_%';

-- Count functions
SELECT COUNT(*) FROM information_schema.routines
WHERE routine_schema = 'public' AND routine_name LIKE 'rule_%';

-- Count views
SELECT COUNT(*) FROM information_schema.views
WHERE table_schema = 'public' AND (
    table_name LIKE '%test%' OR
    table_name LIKE '%webhook%' OR
    table_name LIKE '%template%'
);
```

### ✅ Feature Test
```sql
-- Test each major feature
SELECT rule_engine_version();           -- Core
SELECT * FROM rule_definitions LIMIT 1; -- Repository
SELECT * FROM rule_test_list() LIMIT 1; -- Phase 2
SELECT * FROM rule_webhook_list();      -- Phase 4.2
```

---

## 🚨 Troubleshooting

### Error: "extension does not exist"

**Problem:** Extension not installed

**Solution:**
```sql
CREATE EXTENSION rule_engine_postgre_extensions VERSION '1.5.0';
```

---

### Error: "version X.Y.Z is not available"

**Problem:** Upgrade script not found

**Solution:**
```bash
# Check available files
ls -la /usr/share/postgresql/*/extension/rule_engine_postgre_extensions--*.sql

# If missing, copy from repo
sudo cp rule_engine_postgre_extensions--*.sql /usr/share/postgresql/16/extension/

# Retry upgrade
psql -d your_database -c "ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.5.0';"
```

---

### Error: "function run_rule_engine does not exist"

**Problem:** Rust shared library not installed

**Solution:**
```bash
# Rebuild and install
cd /path/to/repo
cargo pgrx install --pg-config=/usr/bin/pg_config

# Restart PostgreSQL
sudo systemctl restart postgresql
```

---

### Error: Permission denied

**Problem:** Insufficient privileges

**Solution:**
```sql
-- Run as superuser
sudo -u postgres psql -d your_database

-- Or grant privileges
GRANT ALL ON DATABASE your_database TO your_user;
```

---

## 🔄 Rollback Procedures

### Rollback: 1.5.0 → 1.4.0

**⚠️ Warning:** PostgreSQL doesn't support automatic downgrade.

**Option 1: Restore from Backup**
```bash
# Drop current database
dropdb your_database

# Restore backup
pg_restore -C -d postgres backup_before_1.5.0.dump
```

**Option 2: Manual Removal (Risky)**
```sql
-- Drop Phase 4.2 objects
DROP TABLE IF EXISTS rule_webhooks CASCADE;
DROP TABLE IF EXISTS rule_webhook_secrets CASCADE;
DROP TABLE IF EXISTS rule_webhook_calls CASCADE;
DROP TABLE IF EXISTS rule_webhook_call_history CASCADE;

DROP VIEW IF EXISTS webhook_status_summary;
DROP VIEW IF EXISTS webhook_recent_failures;
DROP VIEW IF EXISTS webhook_performance_stats;

DROP FUNCTION IF EXISTS rule_webhook_register CASCADE;
DROP FUNCTION IF EXISTS rule_webhook_call CASCADE;
-- ... (drop all webhook functions)

-- Update extension version
UPDATE pg_extension
SET extversion = '1.4.0'
WHERE extname = 'rule_engine_postgre_extensions';
```

**Recommendation:** Always backup before upgrading!

---

## 📊 Performance Impact

### v1.3.0 → v1.4.0
- **Database Size:** +100 KB (6 tables, 3 views, 12 functions)
- **Memory:** No significant impact
- **Query Performance:** No impact on existing queries

### v1.4.0 → v1.5.0
- **Database Size:** +150 KB (4 tables, 3 views, 15 functions)
- **Memory:** No significant impact
- **Query Performance:** No impact on existing queries
- **Network:** Potential egress for webhook calls

---

## 🎯 Best Practices

### Before Upgrade

1. **✅ Backup Everything**
   ```bash
   pg_dump -Fc your_database > backup_$(date +%Y%m%d_%H%M%S).dump
   ```

2. **✅ Test in Staging**
   - Create staging copy
   - Run upgrade
   - Verify all features
   - Test your application

3. **✅ Read Release Notes**
   - Check CHANGELOG.md
   - Review breaking changes
   - Note new features

4. **✅ Plan Downtime**
   - Typically 30-60 seconds
   - Inform stakeholders
   - Schedule during low traffic

### During Upgrade

1. **✅ Monitor Progress**
   ```sql
   -- Watch for errors in logs
   tail -f /var/log/postgresql/postgresql-*.log
   ```

2. **✅ Verify Each Step**
   - Check version after upgrade
   - Count objects
   - Test features

**Note:** ALTER EXTENSION is automatically transaction-safe. If the upgrade fails, PostgreSQL will rollback all changes.

### After Upgrade

1. **✅ Run Tests**
   ```bash
   psql -d your_database -f tests/test_phase2_developer_experience.sql
   psql -d your_database -f tests/test_webhooks.sql
   ```

2. **✅ Monitor Performance**
   ```sql
   SELECT * FROM pg_stat_user_tables WHERE schemaname = 'public';
   ```

3. **✅ Update Documentation**
   - Note version in your docs
   - Update deployment guides
   - Train team on new features

4. **✅ Clean Up**
   ```sql
   -- Remove old backups after verification
   -- Keep at least one pre-upgrade backup!
   ```

---

## 📞 Support

### Get Help

- 📖 [Full Documentation](README.md)
- 🐛 [Report Issues](https://github.com/yourusername/rule-engine-postgre-extensions/issues)
- 💬 [Discussions](https://github.com/yourusername/rule-engine-postgre-extensions/discussions)
- 📧 Email: support@example.com

### Additional Resources

- [CHANGELOG.md](../CHANGELOG.md) - Complete version history
- [ROADMAP.md](ROADMAP.md) - Future features
- [Phase 2 Documentation](PHASE2_DEVELOPER_EXPERIENCE.md)
- [Webhook Documentation](WEBHOOKS.md)

---

## 📝 Upgrade Log Template

Keep track of your upgrades:

```
Date: _______________
Database: _______________
From Version: _______________
To Version: _______________
Method: [ ] ALTER EXTENSION  [ ] Fresh Install
Backup Location: _______________
Duration: _______________
Issues Encountered: _______________
Notes: _______________
```

---

**Last Updated:** December 10, 2025
**Supported Versions:** 1.3.0, 1.4.0, 1.5.0
**PostgreSQL Versions:** 12, 13, 14, 15, 16
