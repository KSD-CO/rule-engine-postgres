# Upgrade Guide

This guide helps you upgrade your rule-engine-postgres extension to newer versions.

---

## Quick Upgrade (Recommended)

If you're on **any version** and want to upgrade to the latest:

```sql
-- Connect to your database
psql -U postgres -d your_database

-- Check current version
SELECT rule_engine_version();

-- Upgrade to latest version
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.6.0';

-- Verify upgrade
SELECT rule_engine_version();
-- Should return: 1.6.0
```

PostgreSQL will automatically apply all intermediate migrations for you!

---

## Upgrade Paths

### From 1.5.0 → 1.6.0 (Current Latest)

**What's New:**
- 🔌 External Data Sources (fetch data from REST APIs)
- 🚀 Built-in LRU caching (85%+ hit rate)
- 🔄 Automatic retry with exponential backoff
- 📊 Performance monitoring views

**Steps:**

```sql
-- 1. Backup your database (IMPORTANT!)
pg_dump -U postgres -d your_database > backup_before_1.6.0.sql

-- 2. Upgrade extension
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.6.0';

-- 3. Verify new tables exist
SELECT tablename FROM pg_tables
WHERE schemaname = 'public'
AND tablename LIKE 'rule_datasource%'
ORDER BY tablename;

-- Expected output:
-- rule_datasource_auth
-- rule_datasource_cache
-- rule_datasource_rate_limits
-- rule_datasource_requests
-- rule_datasources

-- 4. Test new features (optional)
SELECT rule_datasource_register(
    'test_api',
    'https://api.example.com',
    'none',
    '{}'::JSONB,
    'Test API'
);
```

**Breaking Changes:** None

---

### From 1.4.0 → 1.6.0

This will upgrade through 1.5.0 (webhooks) and 1.6.0 (data sources) automatically.

```sql
-- PostgreSQL applies migrations in order: 1.4.0 → 1.5.0 → 1.6.0
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.6.0';
```

**What's New:**
- All features from 1.5.0 (Webhooks)
- All features from 1.6.0 (External Data Sources)

**Breaking Changes:** None

---

### From 1.3.0 → 1.6.0

This will upgrade through 1.4.0, 1.5.0, and 1.6.0 automatically.

```sql
-- PostgreSQL applies migrations: 1.3.0 → 1.4.0 → 1.5.0 → 1.6.0
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.6.0';
```

**What's New:**
- Event Triggers (1.4.0)
- Webhooks (1.5.0)
- External Data Sources (1.6.0)

**Breaking Changes:** None

---

### From 1.2.0 or earlier → 1.6.0

```sql
-- PostgreSQL will apply all migrations in sequence
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.6.0';
```

**Note:** If you're on a very old version (< 1.2.0), consider reviewing the [CHANGELOG](../CHANGELOG.md) for all changes.

---

## Rollback / Downgrade

PostgreSQL extensions **do not support automatic downgrades**. To rollback:

### Option 1: Restore from Backup

```bash
# Drop current database
dropdb your_database

# Restore from backup
psql -U postgres -d postgres -c "CREATE DATABASE your_database"
psql -U postgres -d your_database < backup_before_upgrade.sql
```

### Option 2: Manual Downgrade (Advanced)

Only do this if you understand SQL and have no data in the new tables.

```sql
-- Example: Downgrade from 1.6.0 to 1.5.0
-- WARNING: This will lose all data in datasource tables!

DROP TABLE IF EXISTS rule_datasource_requests CASCADE;
DROP TABLE IF EXISTS rule_datasource_cache CASCADE;
DROP TABLE IF EXISTS rule_datasource_auth CASCADE;
DROP TABLE IF EXISTS rule_datasource_rate_limits CASCADE;
DROP TABLE IF EXISTS rule_datasources CASCADE;

DROP VIEW IF EXISTS datasource_status_summary CASCADE;
DROP VIEW IF EXISTS datasource_recent_failures CASCADE;
DROP VIEW IF EXISTS datasource_performance_stats CASCADE;
DROP VIEW IF EXISTS datasource_cache_stats CASCADE;

DROP FUNCTION IF EXISTS rule_datasource_register CASCADE;
DROP FUNCTION IF EXISTS rule_datasource_update CASCADE;
DROP FUNCTION IF EXISTS rule_datasource_delete CASCADE;
DROP FUNCTION IF EXISTS rule_datasource_list CASCADE;
DROP FUNCTION IF EXISTS rule_datasource_get CASCADE;
DROP FUNCTION IF EXISTS rule_datasource_auth_set CASCADE;
DROP FUNCTION IF EXISTS rule_datasource_auth_get CASCADE;
DROP FUNCTION IF EXISTS rule_datasource_auth_delete CASCADE;
DROP FUNCTION IF EXISTS rule_datasource_cache_get CASCADE;
DROP FUNCTION IF EXISTS rule_datasource_cache_set CASCADE;
DROP FUNCTION IF EXISTS rule_datasource_cache_clear CASCADE;
DROP FUNCTION IF EXISTS rule_datasource_cache_cleanup CASCADE;
DROP FUNCTION IF EXISTS rule_datasource_fetch CASCADE;
DROP FUNCTION IF EXISTS rule_datasource_cleanup_old_requests CASCADE;

-- Update extension version in metadata
UPDATE pg_extension
SET extversion = '1.5.0'
WHERE extname = 'rule_engine_postgre_extensions';
```

---

## Verification After Upgrade

Run these checks to ensure the upgrade was successful:

```sql
-- 1. Check version
SELECT rule_engine_version();

-- 2. Check all tables exist
SELECT schemaname, tablename
FROM pg_tables
WHERE schemaname = 'public'
AND tablename LIKE 'rule_%'
ORDER BY tablename;

-- 3. Check functions exist (1.6.0 specific)
SELECT proname
FROM pg_proc
WHERE proname LIKE '%datasource%'
ORDER BY proname;

-- Expected functions:
-- rule_datasource_auth_delete
-- rule_datasource_auth_get
-- rule_datasource_auth_set
-- rule_datasource_cache_cleanup
-- rule_datasource_cache_clear
-- rule_datasource_cache_get
-- rule_datasource_cache_set
-- rule_datasource_cleanup_old_requests
-- rule_datasource_delete
-- rule_datasource_fetch
-- rule_datasource_get
-- rule_datasource_list
-- rule_datasource_register
-- rule_datasource_update

-- 4. Check views exist
SELECT schemaname, viewname
FROM pg_views
WHERE schemaname = 'public'
AND viewname LIKE 'datasource%'
ORDER BY viewname;

-- Expected views:
-- datasource_cache_stats
-- datasource_performance_stats
-- datasource_recent_failures
-- datasource_status_summary

-- 5. Test basic functionality
SELECT run_rule_engine(
    '{"x": 10}',
    'rule "test" { when x > 5 then x = x * 2; }'
)::jsonb;
-- Should return: {"x": 20}
```

---

## Troubleshooting

### Error: "extension does not support UPDATE"

**Cause:** The extension is not properly installed or control file is missing.

**Solution:**
```bash
# Reinstall the extension
sudo apt-get install --reinstall postgresql-16-rule-engine

# Or rebuild from source
cd rule-engine-postgres
./install.sh
```

### Error: "migration script not found"

**Cause:** Missing migration file (e.g., `rule_engine_postgre_extensions--1.5.0--1.6.0.sql`)

**Solution:**
```bash
# Check if migration files exist
ls -la /usr/share/postgresql/16/extension/rule_engine_postgre_extensions--*.sql

# Reinstall if missing
sudo apt-get install --reinstall postgresql-16-rule-engine
```

### Error: "column already exists"

**Cause:** Partially applied migration or manual schema changes.

**Solution:**
```sql
-- Option 1: Drop extension and recreate (LOSES ALL DATA!)
DROP EXTENSION rule_engine_postgre_extensions CASCADE;
CREATE EXTENSION rule_engine_postgre_extensions VERSION '1.6.0';

-- Option 2: Restore from backup
\i backup_before_upgrade.sql
```

### Extension version doesn't change

**Cause:** PostgreSQL caching issue.

**Solution:**
```sql
-- Reconnect to database
\c your_database

-- Or restart PostgreSQL
sudo systemctl restart postgresql
```

---

## Best Practices

1. **Always Backup First**
   ```bash
   pg_dump -U postgres -d your_database > backup_$(date +%Y%m%d_%H%M%S).sql
   ```

2. **Test in Development First**
   - Upgrade a copy of your production database
   - Run your test suite
   - Verify all features work

3. **Read Release Notes**
   - Check [CHANGELOG.md](../CHANGELOG.md) for breaking changes
   - Review new features and deprecations

4. **Monitor After Upgrade**
   ```sql
   -- Check for errors in PostgreSQL logs
   SELECT * FROM pg_stat_activity WHERE state = 'active';

   -- Monitor performance
   SELECT * FROM pg_stat_user_tables WHERE schemaname = 'public';
   ```

5. **Schedule During Low Traffic**
   - Upgrades are typically fast (< 1 second)
   - But plan for downtime just in case

---

## Version History

| Version | Release Date | Major Features |
|---------|--------------|----------------|
| 1.6.0 | 2025-12-12 | External Data Sources, API integration |
| 1.5.0 | 2025-12-11 | Webhooks, HTTP callouts |
| 1.4.0 | 2025-12-10 | Event Triggers, Database triggers |
| 1.3.0 | 2025-11-15 | Rule Sets, Batch execution |
| 1.2.0 | 2025-10-20 | Testing framework, Assertions |
| 1.1.0 | 2025-09-10 | Backward chaining |
| 1.0.0 | 2025-08-01 | Initial release |

---

## Getting Help

- **Documentation:** [docs/](../docs/)
- **Issues:** [GitHub Issues](https://github.com/KSD-CO/rule-engine-postgres/issues)
- **Discussions:** [GitHub Discussions](https://github.com/KSD-CO/rule-engine-postgres/discussions)

---

**Last Updated:** December 12, 2025
**Current Version:** 1.6.0
