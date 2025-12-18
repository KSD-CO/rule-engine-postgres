# pgcrypto Extension Requirement

Starting from **v1.6.0**, the rule engine extension requires PostgreSQL's `pgcrypto` extension.

## Why is pgcrypto Required?

The `pgcrypto` extension provides cryptographic functions that are used for:

- **AES-256 Encryption** of API keys and credentials in External Data Sources
- **Secure storage** of sensitive authentication information
- **Transparent encryption/decryption** of secrets at rest

This ensures that credentials stored in the database are encrypted and cannot be read directly from database dumps or backups.

## Installation Order

**IMPORTANT:** Always install `pgcrypto` **BEFORE** installing the rule engine extension.

### Correct Order ✅

```sql
-- 1. Install pgcrypto first
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. Install rule engine
CREATE EXTENSION IF NOT EXISTS rule_engine_postgre_extensions;

-- 3. Verify
SELECT rule_engine_version();
```

### Incorrect Order ❌

```sql
-- This will FAIL with "nested CREATE EXTENSION is not supported"
CREATE EXTENSION IF NOT EXISTS rule_engine_postgre_extensions;
```

**Error:**
```
ERROR:  nested CREATE EXTENSION is not supported
```

## Why Does This Error Occur?

The rule engine's SQL installation script includes:

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

PostgreSQL does not allow creating extensions from within another extension's installation script. This is a PostgreSQL limitation, not a bug.

## Quick Fix

If you already tried to install without pgcrypto:

```sql
-- Drop the failed installation (if any)
DROP EXTENSION IF EXISTS rule_engine_postgre_extensions CASCADE;

-- Install pgcrypto
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Reinstall rule engine
CREATE EXTENSION rule_engine_postgre_extensions;
```

## What if I Don't Use External Data Sources?

Even if you don't plan to use External Data Sources, you still need `pgcrypto` installed because:

1. The extension schema includes encryption tables
2. Future features may also use encryption
3. It's a lightweight extension with minimal overhead

`pgcrypto` is a standard PostgreSQL contrib extension and is safe to install.

## Verification

After installation, verify both extensions are installed:

```sql
-- List installed extensions
SELECT extname, extversion 
FROM pg_extension 
WHERE extname IN ('pgcrypto', 'rule_engine_postgre_extensions');
```

**Expected output:**
```
           extname            | extversion 
------------------------------+------------
 pgcrypto                     | 1.3
 rule_engine_postgre_extensions| 1.6.0
(2 rows)
```

## References

- [Installation Guide](INSTALLATION.md) - Updated installation instructions
- [Troubleshooting Guide](TROUBLESHOOTING.md) - Common issues and solutions
- [External Data Sources Guide](EXTERNAL_DATASOURCES.md) - Why encryption is needed
- [Credential Encryption Guide](CREDENTIAL_ENCRYPTION_GUIDE.md) - How encryption works

## Version History

- **v1.6.0** - pgcrypto became required (credential encryption added)
- **v1.5.0 and earlier** - pgcrypto not required

---

**TL;DR:** Always run `CREATE EXTENSION IF NOT EXISTS pgcrypto;` before installing the rule engine (v1.6.0+).
