# 🔌 External Data Sources Guide

**Version:** 1.6.0
**Feature:** Fetch data from external REST APIs with built-in caching, retry logic, and AES-256 credential encryption

---

## 📋 Quick Start

### 1. Enable Encryption (One-time)

```sql
\i migrations/001_add_credential_encryption_v2.sql
```

### 2. Register Data Source

```sql
SELECT rule_datasource_register(
    'weather_api',
    'https://api.weatherapi.com',
    'api_key',
    '{"Content-Type": "application/json"}'::JSONB,
    'Weather API',
    5000,   -- 5s timeout
    300     -- 5min cache
);
```

### 3. Set Encrypted Credentials

```sql
-- Automatically encrypted with AES-256
SELECT rule_datasource_auth_set(1, 'api_key', 'your-secret-key');

-- Verify encryption
SELECT * FROM datasource_encryption_audit;
-- Shows: encrypted_preview: "ww0EBwMC..." ✅
```

### 4. Fetch Data

```sql
SELECT rule_datasource_fetch(
    1,
    '/current.json',
    '{"q": "London"}'::JSONB
);
```

---

## 🔐 Credential Encryption

All credentials automatically encrypted using pgcrypto AES-256.

### Store Credentials

```sql
-- Encrypted automatically
SELECT rule_datasource_auth_set(
    1,                    -- datasource_id
    'api_key',           -- key name
    'sk-proj-secret123'  -- value (encrypted before storage)
);
```

### Retrieve Credentials

```sql
-- Auto-decrypted
SELECT rule_datasource_auth_get(1, 'api_key');
-- Returns: 'sk-proj-secret123'
```

### Audit Encryption

```sql
SELECT * FROM datasource_encryption_audit;
```

**Output:**
```
 auth_id | datasource_name | auth_key  | encrypted_preview      | encrypted_length
---------+-----------------+-----------+------------------------+------------------
       1 | weather_api     | api_key   | ww0EBwMC4d5J4zNaq9...  | 121
```

✅ Never shows plaintext
🔒 Encrypted blob only

---

## 📡 Fetching Data

```sql
SELECT rule_datasource_fetch(
    datasource_id INTEGER,
    endpoint TEXT,
    params JSONB
) RETURNS JSON;
```

**Example:**
```sql
SELECT rule_datasource_fetch(
    1,
    '/v1/weather',
    '{"city": "London", "units": "metric"}'::JSONB
);
```

**Response:**
```json
{
  "status": 200,
  "data": {...},
  "cached": false,
  "execution_time_ms": 234.5
}
```

---

## 🚀 Caching

Built-in LRU cache with TTL.

### Cache Functions

```sql
-- Get from cache
SELECT rule_datasource_cache_get(1, 'cache_key');

-- Set cache (with TTL)
SELECT rule_datasource_cache_set(
    1, 'key', '{"data":...}'::JSONB, 200, 300
);

-- Clear cache
SELECT rule_datasource_cache_clear(1);

-- Cleanup expired
SELECT rule_datasource_cache_cleanup();
```

### Cache Stats

```sql
SELECT * FROM datasource_cache_stats;
```

---

## 📊 Monitoring

### Status Summary

```sql
SELECT * FROM datasource_status_summary;
```

Shows:
- Total requests
- Success/failure rates
- Cache hit rates
- Avg response times

### Performance Stats

```sql
SELECT * FROM datasource_performance_stats;
```

Shows:
- Min/Max/Avg times
- Percentiles (p50, p95, p99)

### Recent Failures

```sql
SELECT * FROM datasource_recent_failures;
```

---

## 🔒 Security

### Encryption Details

| Feature | Value |
|---------|-------|
| Algorithm | AES-256 (pgcrypto) |
| Key Size | 256 bits |
| Storage | Base64 encoded |
| Access | SECURITY DEFINER only |

### Backup Encryption Key

⚠️ **CRITICAL:**
```sql
SELECT config_value FROM rule_engine_config
WHERE config_key = 'encryption_key';
```

Save securely:
- ✅ Password manager
- ✅ Offline backup
- ❌ NOT in Git
- ❌ NOT in email

---

## ⚙️ Advanced

### Update Configuration

```sql
SELECT rule_datasource_update(
    1,                                        -- id
    'https://api.example.com/v2',            -- new URL
    '{"Authorization": "Bearer ..."}'::JSONB, -- headers
    10000,                                    -- timeout
    600,                                      -- cache TTL
    TRUE                                      -- enabled
);
```

### List All

```sql
SELECT * FROM rule_datasource_list();
```

### Delete

```sql
SELECT rule_datasource_delete(1);
-- Cascade deletes auth, cache, history
```

---

## 🐛 Troubleshooting

### "Encryption key not found"

```sql
-- Apply migration
\i migrations/001_add_credential_encryption_v2.sql
```

### Connection timeout

```sql
-- Increase timeout
SELECT rule_datasource_update(1, NULL, NULL, 30000, NULL, NULL);
```

### Auth failed (401)

```sql
-- Reset credentials
SELECT rule_datasource_auth_set(1, 'api_key', 'new-key');
```

### Low cache hit rate

```sql
-- Check stats
SELECT cache_hit_rate_pct FROM datasource_status_summary;

-- Increase TTL
SELECT rule_datasource_update(1, NULL, NULL, NULL, 3600, NULL);
```

---

## ✅ Production Checklist

- [ ] Encryption migration applied
- [ ] Encryption key backed up
- [ ] Credentials encrypted (verify audit view)
- [ ] Cache TTL configured
- [ ] Timeouts set appropriately
- [ ] Monitoring set up
- [ ] Cleanup job scheduled

---

**Related Docs:**
- [Encryption Guide](CREDENTIAL_ENCRYPTION_GUIDE.md)
- [API Reference](api-reference.md)
- [Webhooks Guide](WEBHOOKS.md)

**Version:** 1.6.0
**Updated:** 2025-12-12
