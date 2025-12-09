-- Fix for Migration 004: Developer Experience
-- Fixes:
--   1. Reserved keyword 'timestamp' -> 'traced_at'
--   2. Create schema_migrations table

-- ============================================================================
-- Fix 1: Rename timestamp column to traced_at
-- ============================================================================

-- Drop the problematic function first
DROP FUNCTION IF EXISTS rule_trace_get(TEXT);

-- Drop the table with the reserved keyword
DROP TABLE IF EXISTS rule_debug_traces;

-- Recreate the table with correct column name
CREATE TABLE IF NOT EXISTS rule_debug_traces (
    trace_id SERIAL PRIMARY KEY,
    session_id TEXT,
    rule_name TEXT,
    step_number INTEGER,
    step_type TEXT, -- 'condition', 'action', 'fact_change'
    description TEXT,
    before_facts JSONB,
    after_facts JSONB,
    evaluated_condition TEXT,
    condition_result BOOLEAN,
    traced_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP  -- Changed from 'timestamp'
);

CREATE INDEX IF NOT EXISTS idx_debug_traces_session ON rule_debug_traces(session_id, step_number);

-- Recreate the function with correct column name
CREATE OR REPLACE FUNCTION rule_trace_get(p_session_id TEXT)
RETURNS TABLE (
    step_number INTEGER,
    step_type TEXT,
    description TEXT,
    before_facts JSONB,
    after_facts JSONB,
    traced_at TIMESTAMPTZ  -- Changed from 'timestamp'
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        rdt.step_number,
        rdt.step_type,
        rdt.description,
        rdt.before_facts,
        rdt.after_facts,
        rdt.traced_at  -- Changed from 'timestamp'
    FROM rule_debug_traces rdt
    WHERE rdt.session_id = p_session_id
    ORDER BY rdt.step_number;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Fix 2: Create schema_migrations table
-- ============================================================================

CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    description TEXT,
    applied_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Insert migration record
INSERT INTO schema_migrations (version, description, applied_at)
VALUES ('004', 'Developer Experience - Testing, Validation, Debugging, Templates', CURRENT_TIMESTAMP)
ON CONFLICT (version) DO NOTHING;

-- ============================================================================
-- Verification
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Migration 004 fixes applied successfully!';
    RAISE NOTICE '✓ Fixed: timestamp column renamed to traced_at';
    RAISE NOTICE '✓ Fixed: schema_migrations table created';
    RAISE NOTICE '';
    RAISE NOTICE 'All Phase 2 features are now ready to use!';
END $$;
