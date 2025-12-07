-- Migration 003: Rule Sets (Collections) and Execution Statistics
-- Version: 1.3.0
-- Description: Add rule sets for grouping rules and execution statistics tracking

BEGIN;

-- ============================================================================
-- PART 1: RULE SETS (COLLECTIONS)
-- ============================================================================

-- Table: rule_sets
-- Purpose: Group multiple rules into reusable collections
CREATE TABLE rule_sets (
    ruleset_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) DEFAULT CURRENT_USER,
    is_active BOOLEAN NOT NULL DEFAULT true
);

COMMENT ON TABLE rule_sets IS 'Collections of rules that can be executed together';
COMMENT ON COLUMN rule_sets.ruleset_id IS 'Unique identifier for the rule set';
COMMENT ON COLUMN rule_sets.name IS 'Unique name of the rule set';
COMMENT ON COLUMN rule_sets.is_active IS 'Whether this rule set is currently active';

-- Table: rule_set_members
-- Purpose: Define which rules belong to which sets and their execution order
CREATE TABLE rule_set_members (
    member_id SERIAL PRIMARY KEY,
    ruleset_id INTEGER NOT NULL REFERENCES rule_sets(ruleset_id) ON DELETE CASCADE,
    rule_name VARCHAR(255) NOT NULL,
    rule_version VARCHAR(50),
    execution_order INTEGER NOT NULL DEFAULT 0,
    added_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    added_by VARCHAR(100) DEFAULT CURRENT_USER,
    UNIQUE (ruleset_id, rule_name, rule_version)
);

COMMENT ON TABLE rule_set_members IS 'Mapping of rules to rule sets with execution order';
COMMENT ON COLUMN rule_set_members.execution_order IS 'Order in which rules execute (lower = earlier)';

-- Index for faster lookups
CREATE INDEX idx_rule_set_members_order ON rule_set_members(ruleset_id, execution_order);

-- ============================================================================
-- PART 2: RULE EXECUTION STATISTICS
-- ============================================================================

-- Table: rule_execution_stats
-- Purpose: Track detailed execution metrics for each rule
CREATE TABLE rule_execution_stats (
    stat_id BIGSERIAL PRIMARY KEY,
    rule_name VARCHAR(255) NOT NULL,
    rule_version VARCHAR(50),
    executed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    execution_time_ms NUMERIC(10,3) NOT NULL,
    success BOOLEAN NOT NULL,
    error_message TEXT,
    facts_modified INTEGER DEFAULT 0,
    rules_fired INTEGER DEFAULT 0,
    executed_by VARCHAR(100) DEFAULT CURRENT_USER
);

COMMENT ON TABLE rule_execution_stats IS 'Detailed execution statistics for all rule runs';
COMMENT ON COLUMN rule_execution_stats.execution_time_ms IS 'Execution duration in milliseconds';
COMMENT ON COLUMN rule_execution_stats.facts_modified IS 'Number of facts modified during execution';
COMMENT ON COLUMN rule_execution_stats.rules_fired IS 'Number of rules that fired during execution';

-- Indexes for performance
CREATE INDEX idx_rule_execution_stats_name ON rule_execution_stats(rule_name);
CREATE INDEX idx_rule_execution_stats_time ON rule_execution_stats(executed_at DESC);
CREATE INDEX idx_rule_execution_stats_success ON rule_execution_stats(success);

-- View: rule_performance_summary
-- Purpose: Aggregate statistics per rule
CREATE VIEW rule_performance_summary AS
SELECT 
    rule_name,
    rule_version,
    COUNT(*) as total_executions,
    SUM(CASE WHEN success THEN 1 ELSE 0 END) as successful_executions,
    SUM(CASE WHEN NOT success THEN 1 ELSE 0 END) as failed_executions,
    ROUND(AVG(execution_time_ms)::numeric, 3) as avg_execution_time_ms,
    ROUND(MIN(execution_time_ms)::numeric, 3) as min_execution_time_ms,
    ROUND(MAX(execution_time_ms)::numeric, 3) as max_execution_time_ms,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY execution_time_ms)::numeric, 3) as median_execution_time_ms,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY execution_time_ms)::numeric, 3) as p95_execution_time_ms,
    SUM(facts_modified) as total_facts_modified,
    SUM(rules_fired) as total_rules_fired,
    MAX(executed_at) as last_executed_at,
    MIN(executed_at) as first_executed_at
FROM rule_execution_stats
GROUP BY rule_name, rule_version;

COMMENT ON VIEW rule_performance_summary IS 'Aggregated performance metrics per rule';

-- ============================================================================
-- API FUNCTIONS: RULE SETS
-- ============================================================================

-- Function: ruleset_create
-- Purpose: Create a new rule set
CREATE OR REPLACE FUNCTION ruleset_create(
    p_name VARCHAR(255),
    p_description TEXT DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_ruleset_id INTEGER;
BEGIN
    -- Validate input
    IF p_name IS NULL OR TRIM(p_name) = '' THEN
        RAISE EXCEPTION 'Rule set name cannot be empty';
    END IF;

    -- Insert rule set
    INSERT INTO rule_sets (name, description)
    VALUES (TRIM(p_name), p_description)
    RETURNING ruleset_id INTO v_ruleset_id;

    RETURN v_ruleset_id;
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Rule set "%" already exists', p_name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ruleset_create IS 'Create a new rule set';

-- Function: ruleset_add_rule
-- Purpose: Add a rule to a rule set with execution order
CREATE OR REPLACE FUNCTION ruleset_add_rule(
    p_ruleset_id INTEGER,
    p_rule_name VARCHAR(255),
    p_rule_version VARCHAR(50) DEFAULT NULL,
    p_order INTEGER DEFAULT 0
) RETURNS BOOLEAN AS $$
BEGIN
    -- Validate rule set exists
    IF NOT EXISTS (SELECT 1 FROM rule_sets WHERE ruleset_id = p_ruleset_id) THEN
        RAISE EXCEPTION 'Rule set ID % does not exist', p_ruleset_id;
    END IF;

    -- Validate rule exists (if rule_definitions table exists from v1.1.0)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'rule_definitions') THEN
        IF NOT EXISTS (
            SELECT 1 FROM rule_definitions WHERE name = p_rule_name
        ) THEN
            RAISE EXCEPTION 'Rule "%" does not exist in rule_definitions', p_rule_name;
        END IF;
    END IF;

    -- Insert or update rule set member
    INSERT INTO rule_set_members (ruleset_id, rule_name, rule_version, execution_order)
    VALUES (p_ruleset_id, p_rule_name, p_rule_version, p_order)
    ON CONFLICT (ruleset_id, rule_name, COALESCE(rule_version, 'default'))
    DO UPDATE SET execution_order = p_order;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ruleset_add_rule IS 'Add a rule to a rule set with execution order';

-- Function: ruleset_remove_rule
-- Purpose: Remove a rule from a rule set
CREATE OR REPLACE FUNCTION ruleset_remove_rule(
    p_ruleset_id INTEGER,
    p_rule_name VARCHAR(255),
    p_rule_version VARCHAR(50) DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    v_deleted INTEGER;
BEGIN
    DELETE FROM rule_set_members
    WHERE ruleset_id = p_ruleset_id
    AND rule_name = p_rule_name
    AND (p_rule_version IS NULL OR rule_version = p_rule_version OR (rule_version IS NULL AND p_rule_version = 'default'));
    
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    
    RETURN v_deleted > 0;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ruleset_remove_rule IS 'Remove a rule from a rule set';

-- Function: ruleset_execute
-- Purpose: Execute all rules in a rule set in order
CREATE OR REPLACE FUNCTION ruleset_execute(
    p_ruleset_id INTEGER,
    p_facts_json TEXT
) RETURNS TEXT AS $$
DECLARE
    v_rule_record RECORD;
    v_result TEXT;
    v_current_facts TEXT := p_facts_json;
BEGIN
    -- Validate rule set exists and is active
    IF NOT EXISTS (SELECT 1 FROM rule_sets WHERE ruleset_id = p_ruleset_id AND is_active = true) THEN
        RAISE EXCEPTION 'Rule set ID % does not exist or is not active', p_ruleset_id;
    END IF;

    -- Execute rules in order
    FOR v_rule_record IN 
        SELECT rsm.rule_name, rsm.rule_version
        FROM rule_set_members rsm
        WHERE rsm.ruleset_id = p_ruleset_id
        ORDER BY rsm.execution_order, rsm.rule_name
    LOOP
        -- Execute each rule with current facts
        v_result := rule_execute_by_name(
            v_rule_record.rule_name,
            v_current_facts,
            v_rule_record.rule_version
        );
        
        -- Update facts with result for next rule
        v_current_facts := v_result;
    END LOOP;

    RETURN v_current_facts;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ruleset_execute IS 'Execute all rules in a rule set sequentially';

-- Function: ruleset_list
-- Purpose: List all rule sets
CREATE OR REPLACE FUNCTION ruleset_list()
RETURNS TABLE (
    ruleset_id INTEGER,
    name VARCHAR(255),
    description TEXT,
    rule_count BIGINT,
    is_active BOOLEAN,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        rs.ruleset_id,
        rs.name,
        rs.description,
        COUNT(rsm.rule_name) as rule_count,
        rs.is_active,
        rs.created_at
    FROM rule_sets rs
    LEFT JOIN rule_set_members rsm ON rs.ruleset_id = rsm.ruleset_id
    GROUP BY rs.ruleset_id, rs.name, rs.description, rs.is_active, rs.created_at
    ORDER BY rs.name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ruleset_list IS 'List all rule sets with member count';

-- Function: ruleset_get_rules
-- Purpose: Get all rules in a rule set
CREATE OR REPLACE FUNCTION ruleset_get_rules(p_ruleset_id INTEGER)
RETURNS TABLE (
    rule_name VARCHAR(255),
    rule_version VARCHAR(50),
    execution_order INTEGER,
    added_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        rsm.rule_name,
        rsm.rule_version,
        rsm.execution_order,
        rsm.added_at
    FROM rule_set_members rsm
    WHERE rsm.ruleset_id = p_ruleset_id
    ORDER BY rsm.execution_order, rsm.rule_name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ruleset_get_rules IS 'Get all rules in a rule set ordered by execution order';

-- Function: ruleset_delete
-- Purpose: Delete a rule set
CREATE OR REPLACE FUNCTION ruleset_delete(p_ruleset_id INTEGER)
RETURNS BOOLEAN AS $$
DECLARE
    v_deleted INTEGER;
BEGIN
    DELETE FROM rule_sets WHERE ruleset_id = p_ruleset_id;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted > 0;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ruleset_delete IS 'Delete a rule set and all its members';

-- ============================================================================
-- API FUNCTIONS: EXECUTION STATISTICS
-- ============================================================================

-- Function: rule_record_execution
-- Purpose: Record a rule execution for statistics
CREATE OR REPLACE FUNCTION rule_record_execution(
    p_rule_name VARCHAR(255),
    p_rule_version VARCHAR(50),
    p_execution_time_ms NUMERIC,
    p_success BOOLEAN,
    p_error_message TEXT DEFAULT NULL,
    p_facts_modified INTEGER DEFAULT 0,
    p_rules_fired INTEGER DEFAULT 0
) RETURNS BIGINT AS $$
DECLARE
    v_stat_id BIGINT;
BEGIN
    INSERT INTO rule_execution_stats (
        rule_name,
        rule_version,
        execution_time_ms,
        success,
        error_message,
        facts_modified,
        rules_fired
    ) VALUES (
        p_rule_name,
        p_rule_version,
        p_execution_time_ms,
        p_success,
        p_error_message,
        p_facts_modified,
        p_rules_fired
    ) RETURNING stat_id INTO v_stat_id;

    RETURN v_stat_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_record_execution IS 'Record a rule execution for statistics tracking';

-- Function: rule_stats
-- Purpose: Get statistics for a specific rule within a time range
CREATE OR REPLACE FUNCTION rule_stats(
    p_rule_name VARCHAR(255),
    p_start_time TIMESTAMPTZ DEFAULT NOW() - INTERVAL '7 days',
    p_end_time TIMESTAMPTZ DEFAULT NOW()
) RETURNS JSON AS $$
DECLARE
    v_stats JSON;
BEGIN
    SELECT json_build_object(
        'rule_name', p_rule_name,
        'time_range', json_build_object(
            'start', p_start_time,
            'end', p_end_time
        ),
        'total_executions', COUNT(*),
        'successful_executions', SUM(CASE WHEN success THEN 1 ELSE 0 END),
        'failed_executions', SUM(CASE WHEN NOT success THEN 1 ELSE 0 END),
        'success_rate', ROUND(
            (SUM(CASE WHEN success THEN 1 ELSE 0 END)::numeric / NULLIF(COUNT(*), 0) * 100)::numeric, 
            2
        ),
        'execution_time', json_build_object(
            'avg_ms', ROUND(AVG(execution_time_ms)::numeric, 3),
            'min_ms', ROUND(MIN(execution_time_ms)::numeric, 3),
            'max_ms', ROUND(MAX(execution_time_ms)::numeric, 3),
            'median_ms', ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY execution_time_ms)::numeric, 3),
            'p95_ms', ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY execution_time_ms)::numeric, 3),
            'p99_ms', ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY execution_time_ms)::numeric, 3)
        ),
        'facts_modified', SUM(facts_modified),
        'rules_fired', SUM(rules_fired),
        'last_execution', MAX(executed_at),
        'recent_errors', (
            SELECT json_agg(json_build_object(
                'timestamp', executed_at,
                'error', error_message
            ))
            FROM (
                SELECT executed_at, error_message
                FROM rule_execution_stats
                WHERE rule_name = p_rule_name
                AND NOT success
                AND executed_at BETWEEN p_start_time AND p_end_time
                ORDER BY executed_at DESC
                LIMIT 10
            ) recent
        )
    ) INTO v_stats
    FROM rule_execution_stats
    WHERE rule_name = p_rule_name
    AND executed_at BETWEEN p_start_time AND p_end_time;

    RETURN COALESCE(v_stats, json_build_object(
        'rule_name', p_rule_name,
        'total_executions', 0,
        'message', 'No execution data found for this time range'
    ));
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_stats IS 'Get comprehensive statistics for a rule';

-- Function: rule_performance_report
-- Purpose: Get performance report for all rules
CREATE OR REPLACE FUNCTION rule_performance_report(
    p_limit INTEGER DEFAULT 50,
    p_order_by VARCHAR(50) DEFAULT 'total_executions'
) RETURNS TABLE (
    rule_name VARCHAR(255),
    rule_version VARCHAR(50),
    total_executions BIGINT,
    success_rate NUMERIC,
    avg_execution_time_ms NUMERIC,
    p95_execution_time_ms NUMERIC,
    last_executed_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY EXECUTE format('
        SELECT 
            rps.rule_name,
            rps.rule_version,
            rps.total_executions,
            ROUND((rps.successful_executions::numeric / NULLIF(rps.total_executions, 0) * 100)::numeric, 2) as success_rate,
            rps.avg_execution_time_ms,
            rps.p95_execution_time_ms,
            rps.last_executed_at
        FROM rule_performance_summary rps
        ORDER BY %I DESC
        LIMIT $1
    ', p_order_by)
    USING p_limit;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_performance_report IS 'Get performance report for all rules';

-- Function: rule_clear_stats
-- Purpose: Clear statistics for a specific rule
CREATE OR REPLACE FUNCTION rule_clear_stats(
    p_rule_name VARCHAR(255),
    p_before_date TIMESTAMPTZ DEFAULT NULL
) RETURNS BIGINT AS $$
DECLARE
    v_deleted BIGINT;
BEGIN
    IF p_before_date IS NULL THEN
        -- Delete all stats for this rule
        DELETE FROM rule_execution_stats WHERE rule_name = p_rule_name;
    ELSE
        -- Delete stats before specific date
        DELETE FROM rule_execution_stats 
        WHERE rule_name = p_rule_name 
        AND executed_at < p_before_date;
    END IF;
    
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_clear_stats IS 'Clear execution statistics for a rule';

-- ============================================================================
-- TRIGGERS FOR AUTO-UPDATE
-- ============================================================================

-- Trigger: Update rule_sets.updated_at
CREATE OR REPLACE FUNCTION update_rule_sets_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_rule_sets_updated_at
BEFORE UPDATE ON rule_sets
FOR EACH ROW
EXECUTE FUNCTION update_rule_sets_timestamp();

COMMIT;
