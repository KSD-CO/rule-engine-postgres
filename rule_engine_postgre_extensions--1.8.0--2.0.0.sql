-- Migration from 1.8.0 to 2.0.0
-- Adds RETE engine and time-travel debugging with PostgreSQL persistence

-- ============================================================================
-- PHASE 1: RETE Engine Functions
-- ============================================================================

-- Add new RETE and FC explicit functions
CREATE OR REPLACE FUNCTION run_rule_engine_rete(facts_json TEXT, rules_grl TEXT)
RETURNS TEXT
AS 'MODULE_PATHNAME', 'run_rule_engine_rete_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION run_rule_engine_fc(facts_json TEXT, rules_grl TEXT)
RETURNS TEXT
AS 'MODULE_PATHNAME', 'run_rule_engine_fc_wrapper'
LANGUAGE C STRICT;

-- Update comment for run_rule_engine (now uses RETE by default)
COMMENT ON FUNCTION run_rule_engine(text, text) IS
'Execute GRL rules using RETE algorithm (default).
Performance: 2-24x faster than forward chaining for batches.
Use run_rule_engine_fc() for simple single evaluations.';

COMMENT ON FUNCTION run_rule_engine_rete(text, text) IS
'Execute GRL rules using RETE algorithm (explicit).
Use for high-performance batch processing and complex rule sets.';

COMMENT ON FUNCTION run_rule_engine_fc(text, text) IS
'Execute GRL rules using traditional forward chaining.
Use for simple rules (1-3) or when predictable execution order is needed.';

-- ============================================================================
-- PHASE 2: PostgreSQL Persistence for Event Sourcing
-- ============================================================================

-- Main event log (append-only, immutable)
CREATE TABLE IF NOT EXISTS rule_execution_events (
    id BIGSERIAL PRIMARY KEY,
    session_id TEXT NOT NULL,
    step BIGINT NOT NULL,
    event_timestamp BIGINT NOT NULL,
    event_type TEXT NOT NULL,
    event_data JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_events_session_step ON rule_execution_events(session_id, step);
CREATE INDEX IF NOT EXISTS idx_events_session_type ON rule_execution_events(session_id, event_type);
CREATE INDEX IF NOT EXISTS idx_events_timestamp ON rule_execution_events(event_timestamp);

-- Sessions metadata
CREATE TABLE IF NOT EXISTS rule_execution_sessions (
    session_id TEXT PRIMARY KEY,
    started_at BIGINT NOT NULL,
    completed_at BIGINT,
    rules_grl TEXT NOT NULL,
    initial_facts JSONB NOT NULL,
    final_facts JSONB,
    total_steps BIGINT DEFAULT 0,
    total_events BIGINT DEFAULT 0,
    status TEXT DEFAULT 'running',
    duration_ms BIGINT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sessions_started ON rule_execution_sessions(started_at);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON rule_execution_sessions(status);

-- Timeline branches (for what-if scenarios) - Phase 5
CREATE TABLE IF NOT EXISTS rule_execution_timelines (
    timeline_id TEXT PRIMARY KEY,
    parent_session_id TEXT NOT NULL,
    branched_at_step BIGINT NOT NULL,
    modifications JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    FOREIGN KEY (parent_session_id) REFERENCES rule_execution_sessions(session_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_timelines_parent ON rule_execution_timelines(parent_session_id);

-- ============================================================================
-- SQL Functions for Time-Travel Debugging
-- ============================================================================

-- Debug execution function
CREATE OR REPLACE FUNCTION run_rule_engine_debug(facts_json TEXT, rules_grl TEXT)
RETURNS TABLE(session_id TEXT, total_steps BIGINT, total_events BIGINT, result JSONB)
AS 'MODULE_PATHNAME', 'run_rule_engine_debug_wrapper'
LANGUAGE C STRICT;

-- Debug query functions
CREATE OR REPLACE FUNCTION debug_get_events(session_id TEXT)
RETURNS TABLE(step BIGINT, event_type TEXT, description TEXT, event_data JSONB)
AS 'MODULE_PATHNAME', 'debug_get_events_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION debug_get_session(session_id TEXT)
RETURNS TABLE(session_id TEXT, started_at BIGINT, completed_at BIGINT, duration_ms BIGINT, status TEXT, total_steps BIGINT, total_events BIGINT, rules_grl TEXT)
AS 'MODULE_PATHNAME', 'debug_get_session_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION debug_list_sessions()
RETURNS TABLE(session_id TEXT, started_at BIGINT, duration_ms BIGINT, status TEXT, total_events BIGINT)
AS 'MODULE_PATHNAME', 'debug_list_sessions_wrapper'
LANGUAGE C STRICT;

-- Debug management functions
CREATE OR REPLACE FUNCTION debug_delete_session(session_id TEXT)
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'debug_delete_session_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION debug_clear_all_sessions()
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'debug_clear_all_sessions_wrapper'
LANGUAGE C STRICT;

-- Debug configuration functions
CREATE OR REPLACE FUNCTION debug_enable()
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'debug_enable_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION debug_disable()
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'debug_disable_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION debug_enable_persistence()
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'debug_enable_persistence_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION debug_disable_persistence()
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'debug_disable_persistence_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION debug_status()
RETURNS JSONB
AS 'MODULE_PATHNAME', 'debug_status_wrapper'
LANGUAGE C STRICT;

COMMENT ON TABLE rule_execution_events IS 'Event sourcing log for time-travel debugging (v2.0.0+)';
COMMENT ON TABLE rule_execution_sessions IS 'Execution sessions metadata for debugging (v2.0.0+)';
COMMENT ON TABLE rule_execution_timelines IS 'Timeline branches for what-if scenarios (v2.0.0+)';

-- ============================================================================
-- Migration Summary
-- ============================================================================
-- Note: rule_engine_version() is automatically updated by pgrx to return '2.0.0'
-- ============================================================================

-- Log migration completion
DO $$
BEGIN
    RAISE NOTICE '============================================';
    RAISE NOTICE 'Migration to v2.0.0 completed successfully!';
    RAISE NOTICE '============================================';
    RAISE NOTICE '';
    RAISE NOTICE 'New Features:';
    RAISE NOTICE '  ✓ RETE algorithm (2-24x faster)';
    RAISE NOTICE '  ✓ run_rule_engine() now uses RETE by default';
    RAISE NOTICE '  ✓ run_rule_engine_rete() for explicit RETE';
    RAISE NOTICE '  ✓ run_rule_engine_fc() for forward chaining';
    RAISE NOTICE '  ✓ Time-travel debugging with event sourcing';
    RAISE NOTICE '  ✓ PostgreSQL persistence for debug sessions';
    RAISE NOTICE '';
    RAISE NOTICE 'Performance Benchmarks:';
    RAISE NOTICE '  - High-throughput: 44,286 evals/sec';
    RAISE NOTICE '  - E-commerce: 103,734 orders/sec';
    RAISE NOTICE '  - Batch processing: 66 orders/sec';
    RAISE NOTICE '';
    RAISE NOTICE 'Breaking Changes:';
    RAISE NOTICE '  - run_rule_engine() now uses RETE (results identical)';
    RAISE NOTICE '  - Use run_rule_engine_fc() for old FC behavior';
    RAISE NOTICE '';
    RAISE NOTICE 'Documentation:';
    RAISE NOTICE '  - Engine Selection: docs/ENGINE_SELECTION.md';
    RAISE NOTICE '  - Performance: tests/PERFORMANCE_RESULTS.md';
    RAISE NOTICE '  - Release Summary: docs/V2_RELEASE_SUMMARY.md';
    RAISE NOTICE '============================================';
END $$;
