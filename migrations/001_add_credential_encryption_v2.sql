-- ============================================================================
-- MIGRATION: Add Credential Encryption (Simplified)
-- Version: 1.6.1
-- Date: 2025-12-12
-- Description: Add pgcrypto-based encryption using config table
-- ============================================================================

\echo '============================================================================'
\echo 'MIGRATION: Add Credential Encryption (v1.6.1)'
\echo '============================================================================'

-- Step 1: Install pgcrypto extension
\echo '\n=== Step 1: Installing pgcrypto extension ==='
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Step 2: Create config table for encryption key
\echo '\n=== Step 2: Creating encryption config table ==='

CREATE TABLE IF NOT EXISTS rule_engine_config (
    config_key TEXT PRIMARY KEY,
    config_value TEXT NOT NULL,
    config_type TEXT DEFAULT 'string',
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE rule_engine_config IS 'System configuration for rule engine (encryption keys, settings)';

-- Restrict access
REVOKE ALL ON rule_engine_config FROM PUBLIC;

-- Step 3: Generate and store encryption key
\echo '\n=== Step 3: Generating encryption key ==='

DO $$
DECLARE
    v_key TEXT;
BEGIN
    -- Check if key already exists
    SELECT config_value INTO v_key
    FROM rule_engine_config
    WHERE config_key = 'encryption_key';

    IF v_key IS NULL THEN
        -- Generate new key
        v_key := encode(gen_random_bytes(32), 'base64');

        INSERT INTO rule_engine_config (config_key, config_value, description)
        VALUES (
            'encryption_key',
            v_key,
            'AES-256 encryption key for credentials (DO NOT SHARE)'
        );

        RAISE NOTICE '✅ Generated new encryption key: %', LEFT(v_key, 10) || '...';
        RAISE WARNING '⚠️  IMPORTANT: Back up this key securely!';
        RAISE WARNING '⚠️  Query: SELECT config_value FROM rule_engine_config WHERE config_key = ''encryption_key'';';
    ELSE
        RAISE NOTICE '✅ Encryption key already exists';
    END IF;
END $$;

-- Step 4: Create encryption helper functions
\echo '\n=== Step 4: Creating encryption helper functions ==='

-- Function: Get encryption key
CREATE OR REPLACE FUNCTION get_encryption_key()
RETURNS TEXT AS $$
DECLARE
    v_key TEXT;
BEGIN
    SELECT config_value INTO v_key
    FROM rule_engine_config
    WHERE config_key = 'encryption_key';

    IF v_key IS NULL THEN
        RAISE EXCEPTION 'Encryption key not found in rule_engine_config';
    END IF;

    RETURN v_key;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_encryption_key() IS 'Retrieves encryption key from config table';

-- Function: Encrypt credential
CREATE OR REPLACE FUNCTION encrypt_credential(p_plaintext TEXT)
RETURNS TEXT AS $$
DECLARE
    v_key TEXT;
BEGIN
    IF p_plaintext IS NULL THEN
        RETURN NULL;
    END IF;

    v_key := get_encryption_key();

    -- Use pgcrypto to encrypt
    RETURN encode(
        pgp_sym_encrypt(
            p_plaintext::TEXT,
            v_key::TEXT
        ),
        'base64'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION encrypt_credential(TEXT) IS 'Encrypts credential using pgcrypto';

-- Function: Decrypt credential
CREATE OR REPLACE FUNCTION decrypt_credential(p_encrypted TEXT)
RETURNS TEXT AS $$
DECLARE
    v_key TEXT;
BEGIN
    IF p_encrypted IS NULL THEN
        RETURN NULL;
    END IF;

    v_key := get_encryption_key();

    -- Decrypt
    RETURN pgp_sym_decrypt(
        decode(p_encrypted, 'base64'),
        v_key::TEXT
    )::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION decrypt_credential(TEXT) IS 'Decrypts credential using pgcrypto';

-- Step 5: Update rule_datasource_auth_set to auto-encrypt
\echo '\n=== Step 5: Updating rule_datasource_auth_set() to auto-encrypt ==='

CREATE OR REPLACE FUNCTION rule_datasource_auth_set(
    p_datasource_id INTEGER,
    p_auth_key TEXT,
    p_auth_value TEXT
)
RETURNS BOOLEAN AS $$
BEGIN
    IF p_datasource_id IS NULL OR p_auth_key IS NULL OR p_auth_value IS NULL THEN
        RAISE EXCEPTION 'datasource_id, auth_key, and auth_value cannot be NULL';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM rule_datasources WHERE datasource_id = p_datasource_id) THEN
        RAISE EXCEPTION 'Data source with ID % does not exist', p_datasource_id;
    END IF;

    INSERT INTO rule_datasource_auth (datasource_id, auth_key, auth_value)
    VALUES (
        p_datasource_id,
        p_auth_key,
        encrypt_credential(p_auth_value)  -- ✅ Auto-encrypt
    )
    ON CONFLICT (datasource_id, auth_key)
    DO UPDATE SET
        auth_value = encrypt_credential(p_auth_value),
        created_at = CURRENT_TIMESTAMP;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_datasource_auth_set(INTEGER, TEXT, TEXT) IS 'Stores encrypted authentication credentials';

-- Step 6: Update rule_datasource_auth_get to auto-decrypt
\echo '\n=== Step 6: Updating rule_datasource_auth_get() to auto-decrypt ==='

CREATE OR REPLACE FUNCTION rule_datasource_auth_get(
    p_datasource_id INTEGER,
    p_auth_key TEXT
)
RETURNS TEXT AS $$
DECLARE
    v_encrypted TEXT;
BEGIN
    SELECT auth_value INTO v_encrypted
    FROM rule_datasource_auth
    WHERE datasource_id = p_datasource_id
      AND auth_key = p_auth_key;

    IF v_encrypted IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN decrypt_credential(v_encrypted);  -- ✅ Auto-decrypt
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION rule_datasource_auth_get(INTEGER, TEXT) IS 'Retrieves and decrypts credentials';

-- Step 7: Migrate existing plaintext credentials
\echo '\n=== Step 7: Migrating existing plaintext credentials ==='

DO $$
DECLARE
    v_record RECORD;
    v_count INTEGER := 0;
    v_is_encrypted BOOLEAN;
BEGIN
    FOR v_record IN
        SELECT auth_id, auth_value
        FROM rule_datasource_auth
        WHERE auth_value IS NOT NULL
    LOOP
        -- Check if already encrypted by trying to decrypt
        BEGIN
            PERFORM decrypt_credential(v_record.auth_value);
            v_is_encrypted := TRUE;
        EXCEPTION WHEN OTHERS THEN
            v_is_encrypted := FALSE;
        END;

        IF NOT v_is_encrypted THEN
            -- Encrypt plaintext credential
            UPDATE rule_datasource_auth
            SET auth_value = encrypt_credential(v_record.auth_value)
            WHERE auth_id = v_record.auth_id;
            v_count := v_count + 1;
        END IF;
    END LOOP;

    IF v_count > 0 THEN
        RAISE NOTICE '✅ Encrypted % existing plaintext credentials', v_count;
    ELSE
        RAISE NOTICE 'ℹ️  No plaintext credentials found';
    END IF;
END $$;

-- Step 8: Create audit view
\echo '\n=== Step 8: Creating encryption audit view ==='

CREATE OR REPLACE VIEW datasource_encryption_audit AS
SELECT
    da.auth_id,
    da.datasource_id,
    ds.datasource_name,
    da.auth_key,
    LEFT(da.auth_value, 20) || '...' AS encrypted_preview,
    LENGTH(da.auth_value) AS encrypted_length,
    da.created_at,
    da.created_by
FROM rule_datasource_auth da
JOIN rule_datasources ds ON da.datasource_id = ds.datasource_id
ORDER BY da.created_at DESC;

COMMENT ON VIEW datasource_encryption_audit IS 'Safe audit view of encrypted credentials';

-- Step 9: Grant permissions
\echo '\n=== Step 9: Setting up permissions ==='

GRANT SELECT ON datasource_encryption_audit TO PUBLIC;

-- Step 10: Verification test
\echo '\n=== Step 10: Verification Tests ==='

DO $$
DECLARE
    v_test_plain TEXT := 'test-secret-value-12345';
    v_encrypted TEXT;
    v_decrypted TEXT;
BEGIN
    -- Test encrypt
    v_encrypted := encrypt_credential(v_test_plain);
    RAISE NOTICE 'Encrypted (preview): %', LEFT(v_encrypted, 30) || '...';

    -- Test decrypt
    v_decrypted := decrypt_credential(v_encrypted);

    IF v_decrypted = v_test_plain THEN
        RAISE NOTICE '✅ Encryption/Decryption test PASSED';
    ELSE
        RAISE EXCEPTION '❌ Encryption/Decryption test FAILED';
    END IF;
END $$;

\echo '\n============================================================================'
\echo 'MIGRATION COMPLETE: Credential Encryption Enabled'
\echo '============================================================================'
\echo ''
\echo 'Summary:'
\echo '  ✅ pgcrypto extension installed'
\echo '  ✅ Config table created (rule_engine_config)'
\echo '  ✅ Encryption key generated and stored'
\echo '  ✅ encrypt_credential() function created'
\echo '  ✅ decrypt_credential() function created'
\echo '  ✅ rule_datasource_auth_set() updated (auto-encrypt)'
\echo '  ✅ rule_datasource_auth_get() updated (auto-decrypt)'
\echo '  ✅ Existing credentials encrypted'
\echo '  ✅ Audit view created'
\echo ''
\echo 'Security:'
\echo '  ⚠️  Encryption key stored in: rule_engine_config table'
\echo '  ⚠️  Back up key: SELECT config_value FROM rule_engine_config WHERE config_key = ''encryption_key'';'
\echo '  ⚠️  Keep backup secure and offline'
\echo ''
\echo 'Usage:'
\echo '  -- Store encrypted'
\echo '  SELECT rule_datasource_auth_set(1, ''api_key'', ''my-secret'');'
\echo ''
\echo '  -- Retrieve decrypted'
\echo '  SELECT rule_datasource_auth_get(1, ''api_key'');'
\echo ''
\echo '  -- View audit'
\echo '  SELECT * FROM datasource_encryption_audit;'
\echo '============================================================================'
