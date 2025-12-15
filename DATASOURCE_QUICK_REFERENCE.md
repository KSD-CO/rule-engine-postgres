# 🔌 External Data Sources - Quick Reference

**Version:** 1.6.0 | **Status:** ✅ Production Ready

---

## 🚀 5-Minute Setup

```sql
-- 1. Enable encryption (one-time)
\i migrations/001_add_credential_encryption_v2.sql

-- 2. Register API
SELECT rule_datasource_register(
    'my_api', 'https://api.example.com', 'api_key', '{}'::JSONB, 'Description', 5000, 300
);

-- 3. Store credentials (auto-encrypted)
SELECT rule_datasource_auth_set(1, 'api_key', 'your-secret-key');

-- 4. Fetch data
SELECT rule_datasource_fetch(1, '/endpoint', '{}'::JSONB);
```

---

## 📋 Common Functions

### Registration
```sql
rule_datasource_register(name, base_url, auth_type, headers, desc, timeout_ms, cache_ttl_sec)
rule_datasource_update(id, url, headers, timeout, cache_ttl, enabled)
rule_datasource_delete(id)
rule_datasource_get(name)
rule_datasource_list()
```

### Credentials (Encrypted)
```sql
rule_datasource_auth_set(datasource_id, key, value)   -- Auto-encrypt
rule_datasource_auth_get(datasource_id, key)          -- Auto-decrypt
rule_datasource_auth_delete(datasource_id, key)
```

### Fetching
```sql
rule_datasource_fetch(datasource_id, endpoint, params)
```

### Cache
```sql
rule_datasource_cache_get(datasource_id, key)
rule_datasource_cache_set(datasource_id, key, value, status, ttl)
rule_datasource_cache_clear(datasource_id)
rule_datasource_cache_cleanup()  -- Remove expired
```

---

## 📊 Monitoring Views

```sql
datasource_status_summary          -- Overall stats
datasource_performance_stats       -- Response times
datasource_cache_stats             -- Cache hit rates
datasource_recent_failures         -- Last 50 failures
datasource_encryption_audit        -- Credential security
```

---

## 🔐 Encryption

### How It Works
- **Algorithm:** AES-256 (pgcrypto)
- **Automatic:** encrypt on SET, decrypt on GET
- **Key Location:** `rule_engine_config` table
- **Access:** SECURITY DEFINER functions only

### Verify Encryption
```sql
SELECT * FROM datasource_encryption_audit;
-- Shows: encrypted_preview: "ww0EBwMC..." ✅ (not plaintext)
```

### Backup Key
```sql
SELECT config_value FROM rule_engine_config WHERE config_key = 'encryption_key';
-- Save securely! (not in Git)
```

---

## ⚡ Quick Examples

### Weather API
```sql
SELECT rule_datasource_register('weather', 'https://api.weatherapi.com', 'api_key', '{}'::JSONB, 'Weather', 5000, 300);
SELECT rule_datasource_auth_set(1, 'key', 'YOUR_KEY');
SELECT rule_datasource_fetch(1, '/current.json', '{"q": "London"}'::JSONB);
```

### GitHub API
```sql
SELECT rule_datasource_register('github', 'https://api.github.com', 'bearer', '{"Accept": "application/vnd.github+json"}'::JSONB, 'GitHub', 5000, 600);
SELECT rule_datasource_auth_set(2, 'token', 'ghp_YOUR_TOKEN');
SELECT rule_datasource_fetch(2, '/user/repos', '{}'::JSONB);
```

### OpenAI API
```sql
SELECT rule_datasource_register('openai', 'https://api.openai.com/v1', 'bearer', '{"Content-Type": "application/json"}'::JSONB, 'OpenAI', 30000, 3600);
SELECT rule_datasource_auth_set(3, 'token', 'sk-proj-YOUR_KEY');
SELECT rule_datasource_fetch(3, '/chat/completions', '{"model": "gpt-4", "messages": [...]}'::JSONB);
```

---

## 🐛 Common Errors

| Error | Solution |
|-------|----------|
| "Encryption key not found" | Run migration: `\i migrations/001_add_credential_encryption_v2.sql` |
| "Data source does not exist" | Register first with `rule_datasource_register()` |
| Connection timeout | Increase timeout: `rule_datasource_update(id, NULL, NULL, 30000, NULL, NULL)` |
| 401 Unauthorized | Check credentials: `rule_datasource_auth_get(id, 'key')` |
| Low cache hit rate | Increase TTL: `rule_datasource_update(id, NULL, NULL, NULL, 3600, NULL)` |

---

## 📖 Full Documentation

- **[Complete Guide](docs/EXTERNAL_DATASOURCES.md)** - All features explained
- **[Encryption Guide](docs/CREDENTIAL_ENCRYPTION_GUIDE.md)** - Security details
- **[API Reference](docs/api-reference.md)** - Function signatures
- **[Migration Script](migrations/001_add_credential_encryption_v2.sql)** - Encryption setup

---

## ✅ Production Checklist

```sql
-- 1. Verify encryption enabled
SELECT COUNT(*) FROM rule_engine_config WHERE config_key = 'encryption_key';
-- Should return: 1

-- 2. Backup encryption key
SELECT config_value FROM rule_engine_config WHERE config_key = 'encryption_key';
-- Save to secure location!

-- 3. Verify credentials encrypted
SELECT * FROM datasource_encryption_audit;
-- Should show: encryption_status = '✅ ENCRYPTED'

-- 4. Check cache hit rates
SELECT datasource_name, cache_hit_rate_pct FROM datasource_status_summary;
-- Target: 85%+

-- 5. Monitor failures
SELECT COUNT(*) FROM datasource_recent_failures WHERE completed_at > NOW() - INTERVAL '1 hour';
-- Should be low
```

---

**Status:** ✅ Ready for Production
**Version:** 1.6.0
**Updated:** 2025-12-12
