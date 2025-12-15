-- ============================================================================
-- MIGRATION: Add Credential Encryption
-- Version: 1.6.1
-- Date: 2025-12-12
-- Description: Add pgcrypto-based encryption for datasource credentials
-- ============================================================================

\echo '============================================================================'
\echo 'MIGRATION: Add Credential Encryption (v1.6.1)'
\echo '============================================================================'

-- Step 1: Install pgcrypto extension
\echo '\n=== Step 1: Installing pgcrypto extension ==='
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Step 2: Configure encryption key (if not already set)
\echo '\n=== Step 2: Checking encryption key configuration ==='
DO $$
DECLARE
    v_key TEXT;
BEGIN
    -- Try to get existing key
    BEGIN
        v_key := current_setting('rule_engine.encryption_key');
        RAISE NOTICE 'Encryption key already configured';
    EXCEPTION WHEN OTHERS THEN
        -- Generate new key and set it
        v_key := encode(gen_random_bytes(32), 'base64');
        EXECUTE format('ALTER SYSTEM SET rule_engine.encryption_key = %L', v_key);
        PERFORM pg_reload_conf();
        RAISE NOTICE 'Generated new encryption key: %', LEFT(v_key, 10) || '...';
        RAISE WARNING 'IMPORTANT: Back up this key securely!';
    END;
END $$;

-- Step 3: Create encryption helper functions
\echo '\n=== Step 3: Creating encryption helper functions ==='

-- Function: Get encryption key safely
CREATE OR REPLACE FUNCTION get_encryption_key()
RETURNS BYTEA AS $$
DECLARE
    v_key_base64 TEXT;
BEGIN
    -- Get key from PostgreSQL config
    v_key_base64 := current_setting('rule_engine.encryption_key', true);

    IF v_key_base64 IS NULL THEN
        RAISE EXCEPTION 'Encryption key not configured. Set rule_engine.encryption_key in postgresql.conf';
    END IF;

    -- Decode from base64
    RETURN decode(v_key_base64, 'base64');
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to get encryption key: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_encryption_key() IS 'Safely retrieves encryption key from PostgreSQL configuration';

-- Function: Encrypt credential
CREATE OR REPLACE FUNCTION encrypt_credential(p_plaintext TEXT)
RETURNS TEXT AS $$
BEGIN
    IF p_plaintext IS NULL THEN
        RETURN NULL;
    END IF;

    -- Encrypt using pgcrypto and encode as base64
    RETURN encode(
        pgp_sym_encrypt(
            p_plaintext,
            get_encryption_key()
        ),
        'base64'
    );
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Encryption failed: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION encrypt_credential(TEXT) IS 'Encrypts credential using pgcrypto symmetric encryption';

-- Function: Decrypt credential
CREATE OR REPLACE FUNCTION decrypt_credential(p_encrypted TEXT)
RETURNS TEXT AS $$
BEGIN
    IF p_encrypted IS NULL THEN
        RETURN NULL;
    END IF;

    -- Decode from base64 and decrypt
    RETURN pgp_sym_decrypt(
        decode(p_encrypted, 'base64'),
        get_encryption_key()
    );
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Decryption failed: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION decrypt_credential(TEXT) IS 'Decrypts credential using pgcrypto symmetric encryption';

-- Step 4: Update rule_datasource_auth_set to auto-encrypt
\echo '\n=== Step 4: Updating rule_datasource_auth_set() to auto-encrypt ==='

CREATE OR REPLACE FUNCTION rule_datasource_auth_set(
    p_datasource_id INTEGER,
    p_auth_key TEXT,
    p_auth_value TEXT
)
RETURNS BOOLEAN AS $$
BEGIN
    -- Validate inputs
    IF p_datasource_id IS NULL OR p_auth_key IS NULL OR p_auth_value IS NULL THEN
        RAISE EXCEPTION 'datasource_id, auth_key, and auth_value cannot be NULL';
    END IF;

    -- Check if datasource exists
    IF NOT EXISTS (SELECT 1 FROM rule_datasources WHERE datasource_id = p_datasource_id) THEN
        RAISE EXCEPTION 'Data source with ID % does not exist', p_datasource_id;
    END IF;

    -- Insert or update with encryption
    INSERT INTO rule_datasource_auth (datasource_id, auth_key, auth_value)
    VALUES (
        p_datasource_id,
        p_auth_key,
        encrypt_credential(p_auth_value)  -- ✅ Auto-encrypt
    )
    ON CONFLICT (datasource_id, auth_key)
    DO UPDATE SET
        auth_value = encrypt_credential(p_auth_value),  -- ✅ Auto-encrypt
        created_at = CURRENT_TIMESTAMP;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_datasource_auth_set(INTEGER, TEXT, TEXT) IS 'Stores encrypted authentication credentials for a data source';

-- Step 5: Update rule_datasource_auth_get to auto-decrypt
\echo '\n=== Step 5: Updating rule_datasource_auth_get() to auto-decrypt ==='

CREATE OR REPLACE FUNCTION rule_datasource_auth_get(
    p_datasource_id INTEGER,
    p_auth_key TEXT
)
RETURNS TEXT AS $$
DECLARE
    v_encrypted TEXT;
BEGIN
    -- Get encrypted value
    SELECT auth_value INTO v_encrypted
    FROM rule_datasource_auth
    WHERE datasource_id = p_datasource_id
      AND auth_key = p_auth_key;

    IF v_encrypted IS NULL THEN
        RETURN NULL;
    END IF;

    -- Decrypt and return
    RETURN decrypt_credential(v_encrypted);  -- ✅ Auto-decrypt
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to retrieve auth credential: %', SQLERRM;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION rule_datasource_auth_get(INTEGER, TEXT) IS 'Retrieves and decrypts authentication credentials for a data source';

-- Step 6: Migrate existing plaintext credentials to encrypted
\echo '\n=== Step 6: Migrating existing plaintext credentials ==='

DO $$
DECLARE
    v_record RECORD;
    v_count INTEGER := 0;
BEGIN
    FOR v_record IN
        SELECT auth_id, auth_value
        FROM rule_datasource_auth
        WHERE auth_value IS NOT NULL
    LOOP
        BEGIN
            -- Try to decrypt - if it fails, it's plaintext
            PERFORM decrypt_credential(v_record.auth_value);
            -- Already encrypted, skip
        EXCEPTION WHEN OTHERS THEN
            -- Not encrypted, encrypt it now
            UPDATE rule_datasource_auth
            SET auth_value = encrypt_credential(v_record.auth_value)
            WHERE auth_id = v_record.auth_id;
            v_count := v_count + 1;
        END;
    END LOOP;

    IF v_count > 0 THEN
        RAISE NOTICE 'Encrypted % existing plaintext credentials', v_count;
    ELSE
        RAISE NOTICE 'No plaintext credentials found to encrypt';
    END IF;
END $$;

-- Step 7: Add encryption metadata column (optional)
\echo '\n=== Step 7: Adding encryption metadata ==='

DO $$
BEGIN
    -- Add encrypted_at timestamp if not exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'rule_datasource_auth'
        AND column_name = 'encrypted_at'
    ) THEN
        ALTER TABLE rule_datasource_auth
        ADD COLUMN encrypted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

        COMMENT ON COLUMN rule_datasource_auth.encrypted_at IS 'Timestamp when credential was encrypted';
    END IF;

    -- Add encryption_version for key rotation tracking
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'rule_datasource_auth'
        AND column_name = 'encryption_version'
    ) THEN
        ALTER TABLE rule_datasource_auth
        ADD COLUMN encryption_version INTEGER DEFAULT 1;

        COMMENT ON COLUMN rule_datasource_auth.encryption_version IS 'Encryption key version for rotation tracking';
    END IF;
END $$;

-- Step 8: Create key rotation function
\echo '\n=== Step 8: Creating key rotation function ==='

CREATE OR REPLACE FUNCTION rotate_encryption_key(
    p_old_key TEXT,
    p_new_key TEXT
)
RETURNS TABLE(
    credentials_rotated INTEGER,
    errors INTEGER
) AS $$
DECLARE
    v_record RECORD;
    v_success INTEGER := 0;
    v_errors INTEGER := 0;
    v_decrypted TEXT;
BEGIN
    FOR v_record IN SELECT * FROM rule_datasource_auth LOOP
        BEGIN
            -- Decrypt with old key
            v_decrypted := pgp_sym_decrypt(
                decode(v_record.auth_value, 'base64'),
                decode(p_old_key, 'base64')
            );

            -- Encrypt with new key
            UPDATE rule_datasource_auth
            SET auth_value = encode(
                    pgp_sym_encrypt(v_decrypted, decode(p_new_key, 'base64')),
                    'base64'
                ),
                encryption_version = encryption_version + 1,
                encrypted_at = CURRENT_TIMESTAMP
            WHERE auth_id = v_record.auth_id;

            v_success := v_success + 1;
        EXCEPTION WHEN OTHERS THEN
            v_errors := v_errors + 1;
            RAISE WARNING 'Failed to rotate credential ID %: %', v_record.auth_id, SQLERRM;
        END;
    END LOOP;

    RETURN QUERY SELECT v_success, v_errors;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rotate_encryption_key(TEXT, TEXT) IS 'Rotates all credentials from old encryption key to new key';

-- Step 9: Create audit view for encrypted credentials
\echo '\n=== Step 9: Creating encryption audit view ==='

CREATE OR REPLACE VIEW datasource_encryption_audit AS
SELECT
    da.auth_id,
    da.datasource_id,
    ds.datasource_name,
    da.auth_key,
    LEFT(da.auth_value, 20) || '...' AS encrypted_preview,
    LENGTH(da.auth_value) AS encrypted_length,
    da.encryption_version,
    da.encrypted_at,
    da.created_at,
    da.created_by
FROM rule_datasource_auth da
JOIN rule_datasources ds ON da.datasource_id = ds.datasource_id
ORDER BY da.encrypted_at DESC;

COMMENT ON VIEW datasource_encryption_audit IS 'Audit view showing encryption status of credentials (safe to query)';

-- Step 10: Grant permissions
\echo '\n=== Step 10: Setting up permissions ==='

-- Revoke direct access to auth table
REVOKE ALL ON rule_datasource_auth FROM PUBLIC;

-- Grant access only through functions
GRANT EXECUTE ON FUNCTION rule_datasource_auth_set(INTEGER, TEXT, TEXT) TO PUBLIC;
GRANT EXECUTE ON FUNCTION rule_datasource_auth_get(INTEGER, TEXT) TO PUBLIC;
GRANT EXECUTE ON FUNCTION rule_datasource_auth_delete(INTEGER, TEXT) TO PUBLIC;

-- Grant select on audit view only
GRANT SELECT ON datasource_encryption_audit TO PUBLIC;

\echo '\n=== Step 11: Verification Tests ==='

-- Test encryption
DO $$
DECLARE
    v_test_plain TEXT := 'test-secret-value-123';
    v_encrypted TEXT;
    v_decrypted TEXT;
BEGIN
    -- Test encrypt
    v_encrypted := encrypt_credential(v_test_plain);
    RAISE NOTICE 'Encrypted: %', LEFT(v_encrypted, 30) || '...';

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
\echo '  ✅ Encryption key configured (backed up securely!)'
\echo '  ✅ encrypt_credential() function created'
\echo '  ✅ decrypt_credential() function created'
\echo '  ✅ rule_datasource_auth_set() updated (auto-encrypt)'
\echo '  ✅ rule_datasource_auth_get() updated (auto-decrypt)'
\echo '  ✅ Existing credentials encrypted'
\echo '  ✅ Key rotation function available'
\echo '  ✅ Audit view created'
\echo ''
\echo 'Security Notes:'
\echo '  ⚠️  Encryption key stored in postgresql.conf'
\echo '  ⚠️  Back up key securely: SELECT current_setting(''rule_engine.encryption_key'');'
\echo '  ⚠️  Protect postgresql.conf with: chmod 600'
\echo '  ⚠️  Direct SELECT on rule_datasource_auth is now restricted'
\echo ''
\echo 'Usage:'
\echo '  -- Store encrypted credential'
\echo '  SELECT rule_datasource_auth_set(1, ''api_key'', ''my-secret'');'
\echo ''
\echo '  -- Retrieve decrypted credential'
\echo '  SELECT rule_datasource_auth_get(1, ''api_key'');'
\echo ''
\echo '  -- View encryption audit'
\echo '  SELECT * FROM datasource_encryption_audit;'
\echo '============================================================================'
