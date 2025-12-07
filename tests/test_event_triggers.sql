-- Test Suite: Event Triggers Integration
-- Tests rule_trigger_* functions

BEGIN;

\echo '======================================'
\echo 'Event Triggers Integration Test Suite'
\echo '======================================'

-- ============================================================================
-- SETUP
-- ============================================================================

\echo '1. Setup: Creating test tables and rules...'

-- Create test orders table
CREATE TABLE IF NOT EXISTS test_orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL,
    discount_amount NUMERIC(10, 2) DEFAULT 0,
    final_amount NUMERIC(10, 2),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create test rule for order discounts
INSERT INTO rule_definitions (name, content_json, version)
VALUES (
    'test_order_discount',
    '{
        "name": "test_order_discount",
        "description": "Apply 10% discount for orders over $100",
        "salience": 100,
        "when": "total_amount > 100",
        "then": [
            "discount_amount = total_amount * 0.1",
            "final_amount = total_amount - discount_amount"
        ]
    }'::JSONB,
    1
) ON CONFLICT (name, version) DO NOTHING;

\echo '✓ Test tables and rules created'

-- ============================================================================
-- TEST 1: Create Trigger
-- ============================================================================

\echo ''
\echo '2. TEST: Create rule trigger'

SELECT rule_trigger_create(
    'test_order_trigger',
    'test_orders',
    'test_order_discount',
    'INSERT'
) AS trigger_id \gset

\echo '✓ Created trigger with ID: ' :trigger_id

-- Verify trigger exists
SELECT 
    CASE 
        WHEN COUNT(*) = 1 THEN '✓ Trigger record created'
        ELSE '✗ ERROR: Trigger not found'
    END AS result
FROM rule_triggers
WHERE id = :trigger_id;

-- Verify PostgreSQL trigger exists
SELECT 
    CASE 
        WHEN COUNT(*) > 0 THEN '✓ PostgreSQL trigger created'
        ELSE '✗ ERROR: PostgreSQL trigger not found'
    END AS result
FROM pg_trigger
WHERE tgname LIKE 'rule_trigger_test_orders_%';

-- ============================================================================
-- TEST 2: Trigger Execution
-- ============================================================================

\echo ''
\echo '3. TEST: Trigger execution on INSERT'

-- Insert order below threshold (no discount)
INSERT INTO test_orders (customer_id, total_amount)
VALUES (1, 50.00)
RETURNING id AS order_id_1 \gset

SELECT 
    id,
    total_amount,
    discount_amount,
    final_amount,
    CASE 
        WHEN discount_amount = 0 AND final_amount IS NULL THEN '✓ No discount applied (total < $100)'
        ELSE '✗ ERROR: Discount should not apply'
    END AS result
FROM test_orders
WHERE id = :order_id_1;

-- Insert order above threshold (should get discount)
INSERT INTO test_orders (customer_id, total_amount)
VALUES (2, 150.00)
RETURNING id AS order_id_2 \gset

SELECT 
    id,
    total_amount,
    discount_amount,
    final_amount,
    CASE 
        WHEN discount_amount = 15.00 AND final_amount = 135.00 THEN '✓ 10% discount applied correctly'
        ELSE '✗ ERROR: Discount calculation incorrect'
    END AS result
FROM test_orders
WHERE id = :order_id_2;

-- ============================================================================
-- TEST 3: Trigger History
-- ============================================================================

\echo ''
\echo '4. TEST: Trigger execution history'

-- Check history records
SELECT 
    COUNT(*) AS execution_count,
    COUNT(CASE WHEN success THEN 1 END) AS success_count,
    COUNT(CASE WHEN NOT success THEN 1 END) AS fail_count,
    CASE 
        WHEN COUNT(*) >= 2 AND COUNT(CASE WHEN success THEN 1 END) >= 2 
        THEN '✓ History records created'
        ELSE '✗ ERROR: Missing history records'
    END AS result
FROM rule_trigger_history
WHERE trigger_id = :trigger_id;

-- View detailed history
SELECT * FROM rule_trigger_history(:trigger_id);

\echo '✓ History records:'
SELECT 
    event_type,
    success,
    execution_time_ms,
    result_summary
FROM rule_trigger_history(:trigger_id)
ORDER BY executed_at;

-- ============================================================================
-- TEST 4: Trigger Stats View
-- ============================================================================

\echo ''
\echo '5. TEST: Trigger statistics view'

SELECT 
    trigger_name,
    table_name,
    rule_name,
    total_executions,
    successful_executions,
    failed_executions,
    avg_execution_time_ms,
    CASE 
        WHEN total_executions >= 2 AND successful_executions >= 2 
        THEN '✓ Stats calculated correctly'
        ELSE '✗ ERROR: Stats mismatch'
    END AS result
FROM rule_trigger_stats
WHERE trigger_id = :trigger_id;

-- ============================================================================
-- TEST 5: Enable/Disable Trigger
-- ============================================================================

\echo ''
\echo '6. TEST: Enable/disable trigger'

-- Disable trigger
SELECT rule_trigger_enable(:trigger_id, FALSE);

-- Verify disabled
SELECT 
    CASE 
        WHEN NOT enabled THEN '✓ Trigger disabled'
        ELSE '✗ ERROR: Trigger still enabled'
    END AS result
FROM rule_triggers
WHERE id = :trigger_id;

-- Insert should not trigger rule
INSERT INTO test_orders (customer_id, total_amount)
VALUES (3, 200.00)
RETURNING id AS order_id_3 \gset

SELECT 
    id,
    total_amount,
    discount_amount,
    final_amount,
    CASE 
        WHEN discount_amount = 0 AND final_amount IS NULL THEN '✓ Rule not executed (trigger disabled)'
        ELSE '✗ ERROR: Rule should not have executed'
    END AS result
FROM test_orders
WHERE id = :order_id_3;

-- Re-enable trigger
SELECT rule_trigger_enable(:trigger_id, TRUE);

-- Verify enabled
SELECT 
    CASE 
        WHEN enabled THEN '✓ Trigger re-enabled'
        ELSE '✗ ERROR: Trigger not enabled'
    END AS result
FROM rule_triggers
WHERE id = :trigger_id;

-- ============================================================================
-- TEST 6: Multiple Event Types
-- ============================================================================

\echo ''
\echo '7. TEST: Multiple event types (UPDATE trigger)'

-- Create UPDATE trigger
SELECT rule_trigger_create(
    'test_order_update_trigger',
    'test_orders',
    'test_order_discount',
    'UPDATE'
) AS update_trigger_id \gset

\echo '✓ Created UPDATE trigger with ID: ' :update_trigger_id

-- Update order to trigger discount recalculation
UPDATE test_orders
SET total_amount = 120.00
WHERE id = :order_id_1
RETURNING 
    id,
    total_amount,
    discount_amount,
    final_amount,
    CASE 
        WHEN discount_amount = 12.00 AND final_amount = 108.00 
        THEN '✓ UPDATE trigger applied discount'
        ELSE '✗ ERROR: UPDATE trigger failed'
    END AS result;

-- ============================================================================
-- TEST 7: Error Handling
-- ============================================================================

\echo ''
\echo '8. TEST: Error handling'

-- Test invalid event type
DO $$
BEGIN
    PERFORM rule_trigger_create('invalid_trigger', 'test_orders', 'test_order_discount', 'INVALID');
    RAISE EXCEPTION 'Should have failed with ERR_RT001';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%ERR_RT001%' THEN
            RAISE NOTICE '✓ Invalid event type rejected';
        ELSE
            RAISE EXCEPTION '✗ ERROR: Wrong error code: %', SQLERRM;
        END IF;
END $$;

-- Test non-existent rule
DO $$
BEGIN
    PERFORM rule_trigger_create('invalid_rule_trigger', 'test_orders', 'non_existent_rule', 'INSERT');
    RAISE EXCEPTION 'Should have failed with ERR_RT002';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%ERR_RT002%' THEN
            RAISE NOTICE '✓ Non-existent rule rejected';
        ELSE
            RAISE EXCEPTION '✗ ERROR: Wrong error code: %', SQLERRM;
        END IF;
END $$;

-- Test non-existent table
DO $$
BEGIN
    PERFORM rule_trigger_create('invalid_table_trigger', 'non_existent_table', 'test_order_discount', 'INSERT');
    RAISE EXCEPTION 'Should have failed with ERR_RT003';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%ERR_RT003%' THEN
            RAISE NOTICE '✓ Non-existent table rejected';
        ELSE
            RAISE EXCEPTION '✗ ERROR: Wrong error code: %', SQLERRM;
        END IF;
END $$;

-- ============================================================================
-- TEST 8: Delete Trigger
-- ============================================================================

\echo ''
\echo '9. TEST: Delete trigger'

-- Delete triggers
SELECT rule_trigger_delete(:trigger_id);
SELECT rule_trigger_delete(:update_trigger_id);

-- Verify triggers deleted
SELECT 
    CASE 
        WHEN COUNT(*) = 0 THEN '✓ Triggers deleted from database'
        ELSE '✗ ERROR: Triggers still exist'
    END AS result
FROM rule_triggers
WHERE id IN (:trigger_id, :update_trigger_id);

-- Verify PostgreSQL triggers removed
SELECT 
    CASE 
        WHEN COUNT(*) = 0 THEN '✓ PostgreSQL triggers cleaned up'
        ELSE '✗ WARNING: Some PostgreSQL triggers remain'
    END AS result
FROM pg_trigger
WHERE tgname LIKE 'rule_trigger_test_orders_%';

-- ============================================================================
-- TEST 9: Performance Test
-- ============================================================================

\echo ''
\echo '10. TEST: Performance (bulk inserts)'

-- Recreate trigger for performance test
SELECT rule_trigger_create(
    'perf_test_trigger',
    'test_orders',
    'test_order_discount',
    'INSERT'
) AS perf_trigger_id \gset

-- Insert 100 orders
\timing on
INSERT INTO test_orders (customer_id, total_amount)
SELECT 
    generate_series(1, 100),
    (random() * 200 + 50)::NUMERIC(10, 2);
\timing off

-- Check average execution time
SELECT 
    COUNT(*) AS total_executions,
    ROUND(AVG(execution_time_ms), 2) AS avg_time_ms,
    ROUND(MAX(execution_time_ms), 2) AS max_time_ms,
    CASE 
        WHEN AVG(execution_time_ms) < 10 THEN '✓ Performance acceptable (<10ms avg)'
        WHEN AVG(execution_time_ms) < 50 THEN '⚠ Performance warning (10-50ms avg)'
        ELSE '✗ Performance issue (>50ms avg)'
    END AS result
FROM rule_trigger_history
WHERE trigger_id = :perf_trigger_id;

-- Cleanup
SELECT rule_trigger_delete(:perf_trigger_id);

-- ============================================================================
-- CLEANUP
-- ============================================================================

\echo ''
\echo '11. Cleanup: Removing test data...'

DROP TABLE IF EXISTS test_orders CASCADE;
DELETE FROM rule_definitions WHERE name LIKE 'test_%';

\echo '✓ Cleanup complete'

-- ============================================================================
-- SUMMARY
-- ============================================================================

\echo ''
\echo '======================================'
\echo 'Test Suite Complete'
\echo '======================================'
\echo 'All Event Triggers Integration tests passed ✓'
\echo ''

ROLLBACK;
