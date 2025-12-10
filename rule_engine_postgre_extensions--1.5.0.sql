-- Health check and version functions
CREATE OR REPLACE FUNCTION rule_engine_health_check()
RETURNS TEXT
AS 'MODULE_PATHNAME', 'rule_engine_health_check_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION rule_engine_version()
RETURNS TEXT
AS 'MODULE_PATHNAME', 'rule_engine_version_wrapper'
LANGUAGE C STRICT;

-- Forward chaining API
CREATE OR REPLACE FUNCTION run_rule_engine(facts_json TEXT, rules_grl TEXT)
RETURNS TEXT
AS 'MODULE_PATHNAME', 'run_rule_engine_wrapper'
LANGUAGE C STRICT;

-- Backward chaining API
CREATE OR REPLACE FUNCTION query_backward_chaining(facts_json TEXT, rules_grl TEXT, goal TEXT)
RETURNS TEXT
AS 'MODULE_PATHNAME', 'query_backward_chaining_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION query_backward_chaining_multi(facts_json TEXT, rules_grl TEXT, goals TEXT[])
RETURNS TEXT
AS 'MODULE_PATHNAME', 'query_backward_chaining_multi_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION can_prove_goal(facts_json TEXT, rules_grl TEXT, goal TEXT)
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'can_prove_goal_wrapper'
LANGUAGE C STRICT;

-- Rule Repository API (wrapper functions)
-- These wrappers call into the extension shared library. Several of them
-- intentionally do NOT use STRICT because they accept NULL for optional
-- parameters (mapped to Option<T> in Rust). Do NOT change to LANGUAGE C STRICT
-- for those functions that accept NULL.

CREATE OR REPLACE FUNCTION rule_save(name TEXT, grl_content TEXT, version TEXT, description TEXT, change_notes TEXT)
RETURNS INT
AS 'MODULE_PATHNAME', 'rule_save_wrapper'
LANGUAGE C;

CREATE OR REPLACE FUNCTION rule_get(name TEXT, version TEXT)
RETURNS TEXT
AS 'MODULE_PATHNAME', 'rule_get_wrapper'
LANGUAGE C;

CREATE OR REPLACE FUNCTION rule_activate(name TEXT, version TEXT)
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'rule_activate_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION rule_delete(name TEXT, version TEXT)
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'rule_delete_wrapper'
LANGUAGE C;

CREATE OR REPLACE FUNCTION rule_tag_add(name TEXT, tag TEXT)
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'rule_tag_add_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION rule_tag_remove(name TEXT, tag TEXT)
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'rule_tag_remove_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION rule_execute_by_name(name TEXT, facts_json TEXT, version TEXT)
RETURNS TEXT
AS 'MODULE_PATHNAME', 'rule_execute_by_name_wrapper'
LANGUAGE C;

CREATE OR REPLACE FUNCTION rule_query_by_name(name TEXT, facts_json TEXT, goal TEXT, version TEXT)
RETURNS TEXT
AS 'MODULE_PATHNAME', 'rule_query_by_name_wrapper'
LANGUAGE C;

CREATE OR REPLACE FUNCTION rule_can_prove_by_name(name TEXT, facts_json TEXT, goal TEXT, version TEXT)
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'rule_can_prove_by_name_wrapper'
LANGUAGE C;

-- Migration: Rule Repository & Versioning
-- RFC-0001: Implement persistent storage for GRL rules with semantic versioning
-- Author: Rule Engine Team
-- Date: 2025-12-06

-- =============================================================================
-- Core Tables
-- =============================================================================

-- Rule definitions (main metadata)
CREATE TABLE IF NOT EXISTS rule_definitions (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_by TEXT,
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_by TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    
    CONSTRAINT rule_name_valid CHECK (name ~ '^[a-zA-Z][a-zA-Z0-9_-]*$')
);

CREATE INDEX IF NOT EXISTS idx_rule_definitions_name ON rule_definitions(name);
CREATE INDEX IF NOT EXISTS idx_rule_definitions_active ON rule_definitions(is_active);

COMMENT ON TABLE rule_definitions IS 'Main rule metadata and lifecycle management';
COMMENT ON COLUMN rule_definitions.name IS 'Unique rule identifier (alphanumeric, underscore, hyphen)';
COMMENT ON COLUMN rule_definitions.is_active IS 'Whether rule is active and can be executed';

-- Rule versions with semantic versioning
CREATE TABLE IF NOT EXISTS rule_versions (
    id SERIAL PRIMARY KEY,
    rule_id INTEGER NOT NULL REFERENCES rule_definitions(id) ON DELETE CASCADE,
    version TEXT NOT NULL,
    grl_content TEXT NOT NULL,
    change_notes TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_by TEXT,
    is_default BOOLEAN NOT NULL DEFAULT false,
    
    CONSTRAINT rule_version_unique UNIQUE (rule_id, version),
    CONSTRAINT version_format_valid CHECK (version ~ '^\d+\.\d+\.\d+(-[a-zA-Z0-9]+)?$'),
    CONSTRAINT grl_not_empty CHECK (length(grl_content) > 0),
    CONSTRAINT grl_size_limit CHECK (length(grl_content) <= 1048576) -- 1MB
);

CREATE INDEX IF NOT EXISTS idx_rule_versions_rule_id ON rule_versions(rule_id);
CREATE INDEX IF NOT EXISTS idx_rule_versions_default ON rule_versions(rule_id, is_default) WHERE is_default = true;
CREATE INDEX IF NOT EXISTS idx_rule_versions_created ON rule_versions(created_at DESC);

COMMENT ON TABLE rule_versions IS 'Version history for each rule with GRL content';
COMMENT ON COLUMN rule_versions.version IS 'Semantic version (e.g., 1.0.0, 2.1.0-beta)';
COMMENT ON COLUMN rule_versions.is_default IS 'The active/default version used when version not specified';

-- Tags for categorization
CREATE TABLE IF NOT EXISTS rule_tags (
    id SERIAL PRIMARY KEY,
    rule_id INTEGER NOT NULL REFERENCES rule_definitions(id) ON DELETE CASCADE,
    tag TEXT NOT NULL,
    
    CONSTRAINT rule_tag_unique UNIQUE (rule_id, tag),
    CONSTRAINT tag_format_valid CHECK (tag ~ '^[a-z][a-z0-9_-]*$')
);

CREATE INDEX IF NOT EXISTS idx_rule_tags_tag ON rule_tags(tag);
CREATE INDEX IF NOT EXISTS idx_rule_tags_rule_id ON rule_tags(rule_id);

COMMENT ON TABLE rule_tags IS 'Tags for organizing and filtering rules';

-- Audit log for compliance and debugging
CREATE TABLE IF NOT EXISTS rule_audit_log (
    id BIGSERIAL PRIMARY KEY,
    -- Store rule_id for audit purposes. We intentionally do NOT enforce a
    -- foreign key constraint here because audit records must remain even if
    -- the referenced rule is deleted. Keeping a strict FK caused a failure
    -- when the audit trigger attempted to insert after the rule row was
    -- removed.
    rule_id INTEGER NOT NULL,
    action TEXT NOT NULL,
    version_before TEXT,
    version_after TEXT,
    changed_by TEXT,
    changed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    change_details JSONB,
    
    CONSTRAINT valid_action CHECK (action IN ('create', 'update', 'delete', 'activate', 'deactivate'))
);

CREATE INDEX IF NOT EXISTS idx_rule_audit_rule_id ON rule_audit_log(rule_id);
CREATE INDEX IF NOT EXISTS idx_rule_audit_changed_at ON rule_audit_log(changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_rule_audit_action ON rule_audit_log(action);

COMMENT ON TABLE rule_audit_log IS 'Complete audit trail of all rule changes';

-- =============================================================================
-- Views
-- =============================================================================

-- Active rules with their default version
CREATE OR REPLACE VIEW rule_catalog AS
SELECT 
    rd.id,
    rd.name,
    rd.description,
    rd.is_active,
    rv.version as default_version,
    rv.grl_content,
    rv.created_at as version_created_at,
    rd.created_at as rule_created_at,
    rd.updated_at,
    ARRAY_AGG(DISTINCT rt.tag ORDER BY rt.tag) FILTER (WHERE rt.tag IS NOT NULL) as tags
FROM rule_definitions rd
LEFT JOIN rule_versions rv ON rd.id = rv.rule_id AND rv.is_default = true
LEFT JOIN rule_tags rt ON rd.id = rt.rule_id
GROUP BY rd.id, rd.name, rd.description, rd.is_active, rv.version, rv.grl_content, 
         rv.created_at, rd.created_at, rd.updated_at;

COMMENT ON VIEW rule_catalog IS 'Complete catalog of rules with their default version and tags';

-- =============================================================================
-- Triggers
-- =============================================================================

-- Update updated_at timestamp automatically
CREATE OR REPLACE FUNCTION update_rule_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_rule_definitions_updated_at
    BEFORE UPDATE ON rule_definitions
    FOR EACH ROW
    EXECUTE FUNCTION update_rule_updated_at();

-- Ensure only one default version per rule
CREATE OR REPLACE FUNCTION ensure_single_default_version()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_default = true THEN
        -- Unset other default versions for this rule
        UPDATE rule_versions
        SET is_default = false
        WHERE rule_id = NEW.rule_id
          AND id != NEW.id
          AND is_default = true;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_single_default_version
    BEFORE INSERT OR UPDATE ON rule_versions
    FOR EACH ROW
    WHEN (NEW.is_default = true)
    EXECUTE FUNCTION ensure_single_default_version();

-- Automatically log audit trail
CREATE OR REPLACE FUNCTION log_rule_audit()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO rule_audit_log (rule_id, action, version_after, changed_by)
        VALUES (NEW.id, 'create', NULL, NEW.created_by);
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.is_active != NEW.is_active THEN
            INSERT INTO rule_audit_log (rule_id, action, changed_by)
            VALUES (
                NEW.id,
                CASE WHEN NEW.is_active THEN 'activate' ELSE 'deactivate' END,
                NEW.updated_by
            );
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO rule_audit_log (rule_id, action, changed_by)
        VALUES (OLD.id, 'delete', NULL);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_rule_audit
    AFTER INSERT OR UPDATE OR DELETE ON rule_definitions
    FOR EACH ROW
    EXECUTE FUNCTION log_rule_audit();

-- Log version changes
CREATE OR REPLACE FUNCTION log_version_audit()
RETURNS TRIGGER AS $$
DECLARE
    prev_version TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Get previous default version
        SELECT version INTO prev_version
        FROM rule_versions
        WHERE rule_id = NEW.rule_id 
          AND is_default = true 
          AND id != NEW.id
        LIMIT 1;
        
        INSERT INTO rule_audit_log (
            rule_id, 
            action, 
            version_before, 
            version_after, 
            changed_by,
            change_details
        )
        VALUES (
            NEW.rule_id,
            'update',
            prev_version,
            NEW.version,
            NEW.created_by,
            jsonb_build_object('change_notes', NEW.change_notes)
        );
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_version_audit
    AFTER INSERT ON rule_versions
    FOR EACH ROW
    EXECUTE FUNCTION log_version_audit();

-- =============================================================================
-- Utility Functions
-- =============================================================================

-- Check if a version string is valid semantic version
CREATE OR REPLACE FUNCTION is_valid_semver(version_str TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN version_str ~ '^\d+\.\d+\.\d+(-[a-zA-Z0-9]+)?$';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Compare semantic versions (returns -1, 0, or 1)
CREATE OR REPLACE FUNCTION compare_semver(v1 TEXT, v2 TEXT)
RETURNS INTEGER AS $$
DECLARE
    v1_parts TEXT[];
    v2_parts TEXT[];
    v1_major INTEGER;
    v1_minor INTEGER;
    v1_patch INTEGER;
    v2_major INTEGER;
    v2_minor INTEGER;
    v2_patch INTEGER;
BEGIN
    -- Extract major.minor.patch (ignore pre-release)
    v1_parts := regexp_split_to_array(split_part(v1, '-', 1), '\.');
    v2_parts := regexp_split_to_array(split_part(v2, '-', 1), '\.');
    
    v1_major := v1_parts[1]::INTEGER;
    v1_minor := v1_parts[2]::INTEGER;
    v1_patch := v1_parts[3]::INTEGER;
    
    v2_major := v2_parts[1]::INTEGER;
    v2_minor := v2_parts[2]::INTEGER;
    v2_patch := v2_parts[3]::INTEGER;
    
    IF v1_major != v2_major THEN
        RETURN SIGN(v1_major - v2_major);
    ELSIF v1_minor != v2_minor THEN
        RETURN SIGN(v1_minor - v2_minor);
    ELSIF v1_patch != v2_patch THEN
        RETURN SIGN(v1_patch - v2_patch);
    ELSE
        RETURN 0;
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- =============================================================================
-- Permissions (Optional - uncomment if needed)
-- =============================================================================

-- GRANT SELECT ON rule_catalog TO PUBLIC;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON rule_definitions TO rule_admin;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON rule_versions TO rule_admin;
-- GRANT SELECT ON rule_audit_log TO rule_admin;

-- =============================================================================
-- Sample Data (Optional - for testing)
-- =============================================================================

-- Uncomment to insert sample data
/*
-- Insert sample rule
INSERT INTO rule_definitions (name, description, created_by, is_active)
VALUES ('sample_discount', 'Sample discount calculation rule', 'system', true);

-- Insert version
INSERT INTO rule_versions (rule_id, version, grl_content, is_default, created_by)
VALUES (
    (SELECT id FROM rule_definitions WHERE name = 'sample_discount'),
    '1.0.0',
    'rule "SampleDiscount" salience 10 {
        when Order.Amount > 100
        then Order.Discount = 10;
    }',
    true,
    'system'
);

-- Add tags
INSERT INTO rule_tags (rule_id, tag)
VALUES 
    ((SELECT id FROM rule_definitions WHERE name = 'sample_discount'), 'discount'),
    ((SELECT id FROM rule_definitions WHERE name = 'sample_discount'), 'pricing');
*/

-- =============================================================================
-- Migration Complete
-- =============================================================================

-- Verify tables created
DO $$
BEGIN
    ASSERT (SELECT COUNT(*) FROM information_schema.tables 
            WHERE table_name IN ('rule_definitions', 'rule_versions', 'rule_tags', 'rule_audit_log')) = 4,
           'Not all required tables were created';
    RAISE NOTICE 'Migration 001_rule_repository completed successfully';
END $$;
-- Migration: 002_rule_triggers.sql
-- Add Event Triggers Integration
-- Requires: 001_rule_repository.sql


-- ============================================================================
-- 1. RULE TRIGGERS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS rule_triggers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    table_name VARCHAR(255) NOT NULL,
    rule_name VARCHAR(255) NOT NULL,
    event_type VARCHAR(10) NOT NULL CHECK (event_type IN ('INSERT', 'UPDATE', 'DELETE')),
    enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    created_by VARCHAR(255) DEFAULT CURRENT_USER,
    updated_at TIMESTAMP DEFAULT NOW(),
    updated_by VARCHAR(255) DEFAULT CURRENT_USER,
    CONSTRAINT unique_trigger UNIQUE (table_name, event_type, rule_name),
    CONSTRAINT fk_rule_name FOREIGN KEY (rule_name) REFERENCES rule_definitions(name) ON DELETE CASCADE
);

COMMENT ON TABLE rule_triggers IS 'Trigger configurations for automatic rule execution';
COMMENT ON COLUMN rule_triggers.name IS 'Unique trigger name';
COMMENT ON COLUMN rule_triggers.table_name IS 'Target table name to monitor';
COMMENT ON COLUMN rule_triggers.rule_name IS 'Rule to execute (from rule_definitions)';
COMMENT ON COLUMN rule_triggers.event_type IS 'Event type: INSERT, UPDATE, or DELETE';
COMMENT ON COLUMN rule_triggers.enabled IS 'Whether trigger is active';

-- ============================================================================
-- 2. TRIGGER HISTORY TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS rule_trigger_history (
    id BIGSERIAL PRIMARY KEY,
    trigger_id INTEGER NOT NULL REFERENCES rule_triggers(id) ON DELETE CASCADE,
    executed_at TIMESTAMP DEFAULT NOW(),
    event_type VARCHAR(10) NOT NULL,
    old_data JSONB,
    new_data JSONB,
    result_data JSONB,
    success BOOLEAN NOT NULL,
    error_message TEXT,
    execution_time_ms NUMERIC(10, 2),
    CONSTRAINT chk_event_type CHECK (event_type IN ('INSERT', 'UPDATE', 'DELETE'))
);

COMMENT ON TABLE rule_trigger_history IS 'Execution history for rule triggers';
COMMENT ON COLUMN rule_trigger_history.old_data IS 'Row data before change (UPDATE/DELETE)';
COMMENT ON COLUMN rule_trigger_history.new_data IS 'Row data after change (INSERT/UPDATE)';
COMMENT ON COLUMN rule_trigger_history.result_data IS 'Rule execution result';
COMMENT ON COLUMN rule_trigger_history.execution_time_ms IS 'Execution time in milliseconds';

-- Indexes for performance
CREATE INDEX idx_trigger_history_trigger_id ON rule_trigger_history(trigger_id);
CREATE INDEX idx_trigger_history_executed_at ON rule_trigger_history(executed_at DESC);
CREATE INDEX idx_trigger_history_success ON rule_trigger_history(success) WHERE success = FALSE;
CREATE INDEX idx_triggers_table_name ON rule_triggers(table_name);
CREATE INDEX idx_triggers_enabled ON rule_triggers(enabled) WHERE enabled = TRUE;

-- ============================================================================
-- 3. TRIGGER FUNCTION
-- ============================================================================

CREATE OR REPLACE FUNCTION execute_rule_trigger()
RETURNS TRIGGER AS $$
DECLARE
    trigger_config RECORD;
    facts_json TEXT;
    result_json TEXT;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    execution_ms NUMERIC;
    error_occurred BOOLEAN := FALSE;
BEGIN
    -- Loop through all enabled triggers for this table and event
    FOR trigger_config IN
        SELECT rt.id, rt.rule_name
        FROM rule_triggers rt
        WHERE rt.table_name = TG_TABLE_NAME
          AND rt.event_type = TG_OP
          AND rt.enabled = TRUE
    LOOP
        BEGIN
            start_time := clock_timestamp();
            
            -- Build facts JSON based on event type
            IF TG_OP = 'DELETE' THEN
                facts_json := row_to_json(OLD)::TEXT;
            ELSE
                facts_json := row_to_json(NEW)::TEXT;
            END IF;
            
            -- Execute rule by name (uses default version)
            result_json := rule_execute_by_name(
                trigger_config.rule_name,
                facts_json,
                NULL
            );
            
            end_time := clock_timestamp();
            execution_ms := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;
            
            -- Log success
            INSERT INTO rule_trigger_history (
                trigger_id, event_type, old_data, new_data, 
                result_data, success, execution_time_ms
            ) VALUES (
                trigger_config.id,
                TG_OP,
                CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN row_to_json(OLD) ELSE NULL END,
                CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN row_to_json(NEW) ELSE NULL END,
                result_json::JSONB,
                TRUE,
                execution_ms
            );
            
            -- Update NEW with modified data (for INSERT/UPDATE only)
            IF TG_OP IN ('INSERT', 'UPDATE') THEN
                -- Merge result back into NEW row
                NEW := jsonb_populate_record(NEW, result_json::JSONB);
            END IF;
            
        EXCEPTION WHEN OTHERS THEN
            error_occurred := TRUE;
            
            -- Log error
            INSERT INTO rule_trigger_history (
                trigger_id, event_type, old_data, new_data,
                success, error_message, execution_time_ms
            ) VALUES (
                trigger_config.id,
                TG_OP,
                CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN row_to_json(OLD) ELSE NULL END,
                CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN row_to_json(NEW) ELSE NULL END,
                FALSE,
                SQLERRM,
                EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000
            );
            
            -- Log warning but don't fail the transaction
            RAISE WARNING 'Rule trigger % failed: %', trigger_config.rule_name, SQLERRM;
        END;
    END LOOP;
    
    -- Return appropriate value based on operation
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION execute_rule_trigger() IS 'Generic trigger function that executes rules on table changes';

-- ============================================================================
-- 4. API FUNCTIONS
-- ============================================================================

-- Create a rule trigger
CREATE OR REPLACE FUNCTION rule_trigger_create(
    p_name TEXT,
    p_table_name TEXT,
    p_rule_name TEXT,
    p_event_type TEXT
) RETURNS INTEGER AS $$
DECLARE
    v_trigger_id INTEGER;
    v_trigger_name TEXT;
    v_table_exists BOOLEAN;
BEGIN
    -- Validate event type
    IF p_event_type NOT IN ('INSERT', 'UPDATE', 'DELETE') THEN
        RAISE EXCEPTION 'ERR_RT001: Invalid event_type. Must be INSERT, UPDATE, or DELETE';
    END IF;
    
    -- Check if rule exists
    IF NOT EXISTS (SELECT 1 FROM rule_definitions WHERE name = p_rule_name) THEN
        RAISE EXCEPTION 'ERR_RT002: Rule not found: %', p_rule_name;
    END IF;
    
    -- Check if table exists
    SELECT EXISTS (
        SELECT FROM pg_tables 
        WHERE schemaname = 'public' 
        AND tablename = p_table_name
    ) INTO v_table_exists;
    
    IF NOT v_table_exists THEN
        RAISE EXCEPTION 'ERR_RT003: Table not found: %', p_table_name;
    END IF;
    
    -- Insert trigger config
    INSERT INTO rule_triggers (name, table_name, rule_name, event_type)
    VALUES (p_name, p_table_name, p_rule_name, p_event_type)
    RETURNING id INTO v_trigger_id;
    
    -- Create PostgreSQL trigger
    v_trigger_name := 'rule_trigger_' || p_table_name || '_' || lower(p_event_type);
    
    -- Drop existing trigger first to avoid conflicts
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', v_trigger_name, p_table_name);
    
    -- Create new trigger
    EXECUTE format(
        'CREATE TRIGGER %I
         BEFORE %s ON %I
         FOR EACH ROW
         EXECUTE FUNCTION execute_rule_trigger()',
        v_trigger_name,
        p_event_type,
        p_table_name
    );
    
    RAISE NOTICE 'Created rule trigger: % (id=%)', p_name, v_trigger_id;
    
    RETURN v_trigger_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_trigger_create IS 'Create a new rule trigger for automatic execution';

-- Enable or disable a trigger
CREATE OR REPLACE FUNCTION rule_trigger_enable(
    p_trigger_id INTEGER,
    p_enabled BOOLEAN DEFAULT TRUE
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE rule_triggers
    SET enabled = p_enabled,
        updated_at = NOW(),
        updated_by = CURRENT_USER
    WHERE id = p_trigger_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ERR_RT004: Trigger not found: %', p_trigger_id;
    END IF;
    
    RAISE NOTICE 'Trigger % %', p_trigger_id, CASE WHEN p_enabled THEN 'enabled' ELSE 'disabled' END;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_trigger_enable IS 'Enable or disable a rule trigger';

-- Get trigger execution history
CREATE OR REPLACE FUNCTION rule_trigger_history(
    p_trigger_id INTEGER,
    p_start_time TIMESTAMP DEFAULT NOW() - INTERVAL '1 day',
    p_end_time TIMESTAMP DEFAULT NOW()
) RETURNS TABLE (
    id BIGINT,
    executed_at TIMESTAMP,
    event_type TEXT,
    success BOOLEAN,
    execution_time_ms NUMERIC,
    error_message TEXT,
    result_summary TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        rth.id,
        rth.executed_at,
        rth.event_type,
        rth.success,
        rth.execution_time_ms,
        rth.error_message,
        CASE 
            WHEN rth.result_data IS NOT NULL THEN 
                substring(rth.result_data::TEXT, 1, 100) || '...'
            ELSE NULL
        END AS result_summary
    FROM rule_trigger_history rth
    WHERE rth.trigger_id = p_trigger_id
      AND rth.executed_at BETWEEN p_start_time AND p_end_time
    ORDER BY rth.executed_at DESC
    LIMIT 1000;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_trigger_history IS 'Get execution history for a rule trigger';

-- Delete a trigger
CREATE OR REPLACE FUNCTION rule_trigger_delete(
    p_trigger_id INTEGER
) RETURNS BOOLEAN AS $$
DECLARE
    v_trigger RECORD;
    v_trigger_name TEXT;
    v_has_others BOOLEAN;
BEGIN
    -- Get trigger info
    SELECT * INTO v_trigger
    FROM rule_triggers
    WHERE id = p_trigger_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ERR_RT005: Trigger not found: %', p_trigger_id;
    END IF;
    
    -- Delete trigger config (cascade deletes history)
    DELETE FROM rule_triggers WHERE id = p_trigger_id;
    
    -- Check if other triggers exist for this table/event
    SELECT EXISTS (
        SELECT 1 FROM rule_triggers
        WHERE table_name = v_trigger.table_name
          AND event_type = v_trigger.event_type
    ) INTO v_has_others;
    
    -- Drop PostgreSQL trigger if no more configs exist
    IF NOT v_has_others THEN
        v_trigger_name := 'rule_trigger_' || v_trigger.table_name || '_' || lower(v_trigger.event_type);
        
        EXECUTE format(
            'DROP TRIGGER IF EXISTS %I ON %I',
            v_trigger_name,
            v_trigger.table_name
        );
        
        RAISE NOTICE 'Dropped PostgreSQL trigger: %', v_trigger_name;
    END IF;
    
    RAISE NOTICE 'Deleted rule trigger: %', v_trigger.name;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_trigger_delete IS 'Delete a rule trigger';

-- ============================================================================
-- 5. VIEWS FOR MONITORING
-- ============================================================================

CREATE OR REPLACE VIEW rule_trigger_stats AS
SELECT 
    rt.id AS trigger_id,
    rt.name AS trigger_name,
    rt.table_name,
    rt.rule_name,
    rt.event_type,
    rt.enabled,
    COUNT(rth.id) AS total_executions,
    COUNT(CASE WHEN rth.success THEN 1 END) AS successful_executions,
    COUNT(CASE WHEN NOT rth.success THEN 1 END) AS failed_executions,
    ROUND(AVG(rth.execution_time_ms), 2) AS avg_execution_time_ms,
    MAX(rth.executed_at) AS last_executed_at
FROM rule_triggers rt
LEFT JOIN rule_trigger_history rth ON rt.id = rth.trigger_id
GROUP BY rt.id, rt.name, rt.table_name, rt.rule_name, rt.event_type, rt.enabled;

COMMENT ON VIEW rule_trigger_stats IS 'Statistics for rule trigger executions';

-- ============================================================================
-- 6. GRANTS
-- ============================================================================

-- Grant access to tables
GRANT SELECT, INSERT, UPDATE, DELETE ON rule_triggers TO PUBLIC;
GRANT SELECT ON rule_trigger_history TO PUBLIC;
GRANT USAGE, SELECT ON SEQUENCE rule_triggers_id_seq TO PUBLIC;
GRANT USAGE, SELECT ON SEQUENCE rule_trigger_history_id_seq TO PUBLIC;

-- Grant execute on functions
GRANT EXECUTE ON FUNCTION rule_trigger_create TO PUBLIC;
GRANT EXECUTE ON FUNCTION rule_trigger_enable TO PUBLIC;
GRANT EXECUTE ON FUNCTION rule_trigger_history TO PUBLIC;
GRANT EXECUTE ON FUNCTION rule_trigger_delete TO PUBLIC;


-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

DO $$ 
BEGIN
    RAISE NOTICE '✅ Migration 002_rule_triggers.sql completed successfully';
    RAISE NOTICE 'Created tables: rule_triggers, rule_trigger_history';
    RAISE NOTICE 'Created functions: rule_trigger_create, rule_trigger_enable, rule_trigger_history, rule_trigger_delete';
    RAISE NOTICE 'Created view: rule_trigger_stats';
END $$;
-- Migration 003: Rule Sets (Collections) and Execution Statistics
-- Version: 1.3.0
-- Description: Add rule sets for grouping rules and execution statistics tracking


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
        -- Older PostgreSQL versions do not accept expressions in ON CONFLICT, so
        -- do an UPDATE first and then INSERT if no row updated.
        UPDATE rule_set_members
        SET execution_order = p_order, added_at = CURRENT_TIMESTAMP, added_by = CURRENT_USER
        WHERE ruleset_id = p_ruleset_id
            AND rule_name = p_rule_name
            AND ( (rule_version IS NULL AND p_rule_version IS NULL) OR rule_version = p_rule_version );

        IF NOT FOUND THEN
                INSERT INTO rule_set_members (ruleset_id, rule_name, rule_version, execution_order)
                VALUES (p_ruleset_id, p_rule_name, p_rule_version, p_order);
        END IF;

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

-- Upgrade script from version 1.3.0 to 1.4.0
-- Phase 2: Developer Experience
-- This file is used when running: ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.4.0';

-- ============================================================================
-- 2.1 RULE TESTING FRAMEWORK
-- ============================================================================

-- Table: rule_test_cases
-- Stores test definitions for rules
CREATE TABLE IF NOT EXISTS rule_test_cases (
    test_id SERIAL PRIMARY KEY,
    test_name TEXT NOT NULL UNIQUE,
    rule_name TEXT NOT NULL,
    rule_version TEXT DEFAULT 'latest',
    description TEXT,
    input_facts JSONB NOT NULL,
    expected_output JSONB,
    expected_modifications JSONB,
    assertions JSONB,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    tags TEXT[] DEFAULT '{}',
    enabled BOOLEAN DEFAULT true
);

CREATE TABLE IF NOT EXISTS rule_test_results (
    result_id SERIAL PRIMARY KEY,
    test_id INTEGER REFERENCES rule_test_cases(test_id) ON DELETE CASCADE,
    executed_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    passed BOOLEAN NOT NULL,
    execution_time_ms NUMERIC,
    actual_output JSONB,
    actual_modifications JSONB,
    error_message TEXT,
    assertion_results JSONB
);

CREATE TABLE IF NOT EXISTS rule_test_coverage (
    rule_name TEXT PRIMARY KEY,
    total_tests INTEGER DEFAULT 0,
    passing_tests INTEGER DEFAULT 0,
    failing_tests INTEGER DEFAULT 0,
    last_test_run TIMESTAMPTZ,
    coverage_score NUMERIC DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_test_cases_rule ON rule_test_cases(rule_name, rule_version);
CREATE INDEX IF NOT EXISTS idx_test_results_test ON rule_test_results(test_id, executed_at DESC);
CREATE INDEX IF NOT EXISTS idx_test_results_passed ON rule_test_results(passed);

-- Testing API Functions
CREATE OR REPLACE FUNCTION rule_test_create(
    p_test_name TEXT,
    p_rule_name TEXT,
    p_input_facts JSONB,
    p_expected_output JSONB DEFAULT NULL,
    p_rule_version TEXT DEFAULT 'latest',
    p_description TEXT DEFAULT NULL,
    p_assertions JSONB DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_test_id INTEGER;
BEGIN
    INSERT INTO rule_test_cases (
        test_name, rule_name, rule_version, description,
        input_facts, expected_output, assertions
    ) VALUES (
        p_test_name, p_rule_name, p_rule_version, p_description,
        p_input_facts, p_expected_output, p_assertions
    ) RETURNING test_id INTO v_test_id;
    RETURN v_test_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rule_test_check_assertions(
    p_actual JSONB,
    p_assertions JSONB
) RETURNS JSONB AS $$
DECLARE
    v_assertion JSONB;
    v_results JSONB := '[]'::JSONB;
    v_passed BOOLEAN;
    v_all_passed BOOLEAN := true;
    v_actual_value JSONB;
    v_expected_value JSONB;
    v_assertion_type TEXT;
    v_path TEXT;
BEGIN
    FOR v_assertion IN SELECT jsonb_array_elements(p_assertions)
    LOOP
        v_assertion_type := v_assertion->>'type';
        v_path := v_assertion->>'path';
        v_expected_value := v_assertion->'value';

        BEGIN
            EXECUTE format('SELECT $1#>%L', string_to_array(v_path, '.'))
            INTO v_actual_value
            USING p_actual;
        EXCEPTION WHEN OTHERS THEN
            v_actual_value := NULL;
        END;

        CASE v_assertion_type
            WHEN 'equals' THEN
                v_passed := (v_actual_value = v_expected_value);
            WHEN 'not_equals' THEN
                v_passed := (v_actual_value != v_expected_value);
            WHEN 'exists' THEN
                v_passed := (v_actual_value IS NOT NULL);
            WHEN 'not_exists' THEN
                v_passed := (v_actual_value IS NULL);
            WHEN 'contains' THEN
                v_passed := (v_actual_value ? (v_expected_value->>0));
            WHEN 'greater_than' THEN
                v_passed := ((v_actual_value->>0)::NUMERIC > (v_expected_value->>0)::NUMERIC);
            WHEN 'less_than' THEN
                v_passed := ((v_actual_value->>0)::NUMERIC < (v_expected_value->>0)::NUMERIC);
            ELSE
                v_passed := false;
        END CASE;

        v_all_passed := v_all_passed AND v_passed;

        v_results := v_results || jsonb_build_object(
            'type', v_assertion_type,
            'path', v_path,
            'expected', v_expected_value,
            'actual', v_actual_value,
            'passed', v_passed
        );
    END LOOP;

    RETURN jsonb_build_object(
        'all_passed', v_all_passed,
        'results', v_results,
        'summary', CASE
            WHEN v_all_passed THEN 'All assertions passed'
            ELSE format('%s of %s assertions failed',
                jsonb_array_length(v_results) - (
                    SELECT COUNT(*) FROM jsonb_array_elements(v_results)
                    WHERE value->>'passed' = 'true'
                ),
                jsonb_array_length(v_results)
            )
        END
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rule_test_run(p_test_id INTEGER)
RETURNS JSON AS $$
DECLARE
    v_test rule_test_cases%ROWTYPE;
    v_actual_output TEXT;
    v_actual_json JSONB;
    v_passed BOOLEAN;
    v_error_message TEXT;
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_execution_time_ms NUMERIC;
    v_assertion_results JSONB;
    v_result_id INTEGER;
BEGIN
    SELECT * INTO v_test FROM rule_test_cases WHERE test_id = p_test_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Test case not found');
    END IF;

    IF NOT v_test.enabled THEN
        RETURN json_build_object('success', false, 'error', 'Test case is disabled');
    END IF;

    v_start_time := clock_timestamp();

    BEGIN
        SELECT rule_execute_by_name(
            v_test.rule_name,
            v_test.input_facts,
            v_test.rule_version
        ) INTO v_actual_output;

        v_actual_json := v_actual_output::JSONB;

        IF v_test.assertions IS NOT NULL THEN
            v_assertion_results := rule_test_check_assertions(v_actual_json, v_test.assertions);
            v_passed := (v_assertion_results->>'all_passed')::BOOLEAN;
            v_error_message := v_assertion_results->>'summary';
        ELSIF v_test.expected_output IS NOT NULL THEN
            v_passed := (v_actual_json = v_test.expected_output);
            v_error_message := CASE
                WHEN NOT v_passed THEN format('Expected: %s, Got: %s', v_test.expected_output, v_actual_json)
                ELSE NULL
            END;
        ELSE
            v_passed := true;
        END IF;

    EXCEPTION WHEN OTHERS THEN
        v_passed := false;
        v_error_message := SQLERRM;
        v_actual_json := NULL;
    END;

    v_end_time := clock_timestamp();
    v_execution_time_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;

    INSERT INTO rule_test_results (
        test_id, passed, execution_time_ms,
        actual_output, error_message, assertion_results
    ) VALUES (
        p_test_id, v_passed, v_execution_time_ms,
        v_actual_json, v_error_message, v_assertion_results
    ) RETURNING result_id INTO v_result_id;

    PERFORM rule_test_update_coverage(v_test.rule_name);

    RETURN json_build_object(
        'test_id', p_test_id,
        'test_name', v_test.test_name,
        'passed', v_passed,
        'execution_time_ms', v_execution_time_ms,
        'actual_output', v_actual_json,
        'expected_output', v_test.expected_output,
        'error_message', v_error_message,
        'assertion_results', v_assertion_results,
        'result_id', v_result_id
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rule_test_run_all(p_rule_name TEXT DEFAULT NULL)
RETURNS TABLE (
    test_id INTEGER,
    test_name TEXT,
    rule_name TEXT,
    passed BOOLEAN,
    execution_time_ms NUMERIC,
    error_message TEXT
) AS $$
DECLARE
    v_test RECORD;
    v_result JSON;
BEGIN
    FOR v_test IN
        SELECT tc.test_id, tc.test_name, tc.rule_name
        FROM rule_test_cases tc
        WHERE (p_rule_name IS NULL OR tc.rule_name = p_rule_name)
          AND tc.enabled = true
        ORDER BY tc.test_name
    LOOP
        v_result := rule_test_run(v_test.test_id);

        RETURN QUERY SELECT
            (v_result->>'test_id')::INTEGER,
            v_result->>'test_name',
            v_test.rule_name,
            (v_result->>'passed')::BOOLEAN,
            (v_result->>'execution_time_ms')::NUMERIC,
            v_result->>'error_message';
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rule_test_coverage(p_rule_name TEXT)
RETURNS JSON AS $$
DECLARE
    v_coverage rule_test_coverage%ROWTYPE;
BEGIN
    SELECT * INTO v_coverage FROM rule_test_coverage WHERE rule_name = p_rule_name;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'rule_name', p_rule_name,
            'total_tests', 0,
            'passing_tests', 0,
            'failing_tests', 0,
            'coverage_score', 0
        );
    END IF;

    RETURN row_to_json(v_coverage);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rule_test_update_coverage(p_rule_name TEXT)
RETURNS VOID AS $$
DECLARE
    v_total INTEGER;
    v_passing INTEGER;
    v_failing INTEGER;
BEGIN
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE passed = true),
        COUNT(*) FILTER (WHERE passed = false)
    INTO v_total, v_passing, v_failing
    FROM (
        SELECT DISTINCT ON (test_id) test_id, passed
        FROM rule_test_results rtr
        JOIN rule_test_cases rtc ON rtr.test_id = rtc.test_id
        WHERE rtc.rule_name = p_rule_name
        ORDER BY test_id, executed_at DESC
    ) latest_results;

    INSERT INTO rule_test_coverage (
        rule_name, total_tests, passing_tests, failing_tests,
        last_test_run, coverage_score
    ) VALUES (
        p_rule_name, v_total, v_passing, v_failing,
        CURRENT_TIMESTAMP,
        CASE WHEN v_total > 0 THEN (v_passing::NUMERIC / v_total * 100) ELSE 0 END
    )
    ON CONFLICT (rule_name) DO UPDATE SET
        total_tests = EXCLUDED.total_tests,
        passing_tests = EXCLUDED.passing_tests,
        failing_tests = EXCLUDED.failing_tests,
        last_test_run = EXCLUDED.last_test_run,
        coverage_score = EXCLUDED.coverage_score,
        updated_at = CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 2.2 RULE VALIDATION & LINTING
-- ============================================================================

CREATE OR REPLACE FUNCTION rule_validate(p_grl TEXT)
RETURNS JSON AS $$
DECLARE
    v_errors TEXT[] := '{}';
    v_warnings TEXT[] := '{}';
    v_test_result TEXT;
BEGIN
    BEGIN
        SELECT run_rule_engine('{}'::JSONB, p_grl) INTO v_test_result;
    EXCEPTION WHEN OTHERS THEN
        v_errors := array_append(v_errors, 'Syntax error: ' || SQLERRM);
    END;

    IF trim(p_grl) = '' THEN
        v_errors := array_append(v_errors, 'Rule cannot be empty');
    END IF;

    IF p_grl !~ 'rule\s+\w+' THEN
        v_errors := array_append(v_errors, 'Missing rule declaration');
    END IF;

    IF (length(p_grl) - length(replace(p_grl, '&&', ''))) / 2 > 5 THEN
        v_warnings := array_append(v_warnings, 'Complex condition: More than 5 AND operators may impact performance');
    END IF;

    IF (length(p_grl) - length(replace(p_grl, '{', ''))) > 10 THEN
        v_warnings := array_append(v_warnings, 'Deep nesting detected: Consider refactoring');
    END IF;

    RETURN json_build_object(
        'valid', array_length(v_errors, 1) IS NULL,
        'errors', v_errors,
        'warnings', v_warnings,
        'error_count', COALESCE(array_length(v_errors, 1), 0),
        'warning_count', COALESCE(array_length(v_warnings, 1), 0)
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rule_lint(
    p_grl TEXT,
    p_strict_mode BOOLEAN DEFAULT false
) RETURNS JSON AS $$
DECLARE
    v_validation JSON;
    v_issues JSONB := '[]'::JSONB;
    v_lines TEXT[];
    v_line TEXT;
    v_line_num INTEGER;
BEGIN
    v_validation := rule_validate(p_grl);

    IF (v_validation->>'error_count')::INTEGER > 0 THEN
        v_issues := v_issues || jsonb_build_object(
            'type', 'error',
            'category', 'syntax',
            'message', 'Syntax validation failed',
            'details', v_validation->'errors'
        );
    END IF;

    v_lines := string_to_array(p_grl, E'\n');

    FOR v_line_num IN 1..array_length(v_lines, 1) LOOP
        v_line := v_lines[v_line_num];

        IF v_line ~ '^\s*\w+\s*:=.*' AND NOT (p_grl ~ ('\y' || split_part(trim(v_line), ' ', 1) || '\y')) THEN
            v_issues := v_issues || jsonb_build_object(
                'type', 'warning',
                'category', 'unused_variable',
                'line', v_line_num,
                'message', format('Potentially unused variable at line %s', v_line_num)
            );
        END IF;

        IF p_strict_mode AND length(v_line) > 120 THEN
            v_issues := v_issues || jsonb_build_object(
                'type', 'style',
                'category', 'line_length',
                'line', v_line_num,
                'message', format('Line %s exceeds 120 characters', v_line_num)
            );
        END IF;

        IF v_line ~* 'TODO|FIXME' THEN
            v_issues := v_issues || jsonb_build_object(
                'type', 'info',
                'category', 'todo',
                'line', v_line_num,
                'message', format('TODO/FIXME found at line %s', v_line_num)
            );
        END IF;
    END LOOP;

    IF p_grl !~ 'salience' THEN
        v_issues := v_issues || jsonb_build_object(
            'type', 'info',
            'category', 'best_practice',
            'message', 'Consider adding salience for rule prioritization'
        );
    END IF;

    RETURN jsonb_build_object(
        'passed', jsonb_array_length(v_issues) = 0,
        'issue_count', jsonb_array_length(v_issues),
        'issues', v_issues,
        'validation', v_validation
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 2.3 RULE DEBUGGING TOOLS
-- ============================================================================

CREATE TABLE IF NOT EXISTS rule_debug_traces (
    trace_id SERIAL PRIMARY KEY,
    session_id TEXT,
    rule_name TEXT,
    step_number INTEGER,
    step_type TEXT,
    description TEXT,
    before_facts JSONB,
    after_facts JSONB,
    evaluated_condition TEXT,
    condition_result BOOLEAN,
    traced_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_debug_traces_session ON rule_debug_traces(session_id, step_number);

CREATE OR REPLACE FUNCTION rule_debug_execute(
    p_facts JSONB,
    p_rules TEXT,
    p_session_id TEXT DEFAULT NULL
) RETURNS JSON AS $$
DECLARE
    v_session_id TEXT;
    v_result TEXT;
    v_trace_count INTEGER;
BEGIN
    v_session_id := COALESCE(p_session_id, 'debug_' || extract(epoch from now())::TEXT);

    BEGIN
        SELECT run_rule_engine(p_facts, p_rules) INTO v_result;

        INSERT INTO rule_debug_traces (
            session_id, rule_name, step_number, step_type,
            description, before_facts, after_facts
        ) VALUES (
            v_session_id, 'debug_session', 1, 'execution',
            'Rule execution completed', p_facts, v_result::JSONB
        );

    EXCEPTION WHEN OTHERS THEN
        INSERT INTO rule_debug_traces (
            session_id, rule_name, step_number, step_type,
            description, before_facts
        ) VALUES (
            v_session_id, 'debug_session', 1, 'error',
            'Error: ' || SQLERRM, p_facts
        );
    END;

    SELECT COUNT(*) INTO v_trace_count FROM rule_debug_traces WHERE session_id = v_session_id;

    RETURN json_build_object(
        'session_id', v_session_id,
        'result', v_result,
        'trace_count', v_trace_count,
        'message', 'Debug session completed. Use rule_trace_get() to retrieve detailed trace.'
    );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rule_trace_get(p_session_id TEXT)
RETURNS TABLE (
    step_number INTEGER,
    step_type TEXT,
    description TEXT,
    before_facts JSONB,
    after_facts JSONB,
    traced_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        rdt.step_number,
        rdt.step_type,
        rdt.description,
        rdt.before_facts,
        rdt.after_facts,
        rdt.traced_at
    FROM rule_debug_traces rdt
    WHERE rdt.session_id = p_session_id
    ORDER BY rdt.step_number;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 2.4 RULE TEMPLATES
-- ============================================================================

CREATE TABLE IF NOT EXISTS rule_templates (
    template_id SERIAL PRIMARY KEY,
    template_name TEXT NOT NULL UNIQUE,
    description TEXT,
    grl_template TEXT NOT NULL,
    parameters JSONB NOT NULL,
    category TEXT,
    usage_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    tags TEXT[] DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS rule_template_instances (
    instance_id SERIAL PRIMARY KEY,
    template_id INTEGER REFERENCES rule_templates(template_id) ON DELETE CASCADE,
    rule_name TEXT NOT NULL,
    parameter_values JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER
);

CREATE INDEX IF NOT EXISTS idx_templates_category ON rule_templates(category);
CREATE INDEX IF NOT EXISTS idx_template_instances_template ON rule_template_instances(template_id);

CREATE OR REPLACE FUNCTION rule_template_create(
    p_template_name TEXT,
    p_grl_template TEXT,
    p_parameters JSONB,
    p_description TEXT DEFAULT NULL,
    p_category TEXT DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_template_id INTEGER;
BEGIN
    INSERT INTO rule_templates (
        template_name, grl_template, parameters, description, category
    ) VALUES (
        p_template_name, p_grl_template, p_parameters, p_description, p_category
    ) RETURNING template_id INTO v_template_id;

    RETURN v_template_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rule_template_instantiate(
    p_template_id INTEGER,
    p_parameter_values JSONB,
    p_rule_name TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    v_template rule_templates%ROWTYPE;
    v_grl TEXT;
    v_param JSONB;
    v_param_name TEXT;
    v_param_value TEXT;
    v_rule_name TEXT;
BEGIN
    SELECT * INTO v_template FROM rule_templates WHERE template_id = p_template_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Template not found: %', p_template_id;
    END IF;

    v_grl := v_template.grl_template;
    v_rule_name := COALESCE(p_rule_name, v_template.template_name || '_' || extract(epoch from now())::TEXT);

    FOR v_param IN SELECT jsonb_array_elements(v_template.parameters)
    LOOP
        v_param_name := v_param->>'name';
        v_param_value := p_parameter_values->>v_param_name;

        IF v_param_value IS NULL THEN
            v_param_value := v_param->>'default';
        END IF;

        IF v_param_value IS NULL THEN
            RAISE EXCEPTION 'Required parameter not provided: %', v_param_name;
        END IF;

        v_grl := replace(v_grl, '{{' || v_param_name || '}}', v_param_value);
    END LOOP;

    INSERT INTO rule_template_instances (
        template_id, rule_name, parameter_values
    ) VALUES (
        p_template_id, v_rule_name, p_parameter_values
    );

    UPDATE rule_templates
    SET usage_count = usage_count + 1
    WHERE template_id = p_template_id;

    RETURN v_grl;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rule_template_list(p_category TEXT DEFAULT NULL)
RETURNS TABLE (
    template_id INTEGER,
    template_name TEXT,
    description TEXT,
    category TEXT,
    parameters JSONB,
    usage_count INTEGER,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        rt.template_id,
        rt.template_name,
        rt.description,
        rt.category,
        rt.parameters,
        rt.usage_count,
        rt.created_at
    FROM rule_templates rt
    WHERE (p_category IS NULL OR rt.category = p_category)
    ORDER BY rt.usage_count DESC, rt.template_name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rule_template_get(p_identifier TEXT)
RETURNS JSON AS $$
DECLARE
    v_template rule_templates%ROWTYPE;
BEGIN
    BEGIN
        SELECT * INTO v_template FROM rule_templates
        WHERE template_id = p_identifier::INTEGER;
    EXCEPTION WHEN OTHERS THEN
        SELECT * INTO v_template FROM rule_templates
        WHERE template_name = p_identifier;
    END;

    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Template not found');
    END IF;

    RETURN row_to_json(v_template);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEWS FOR DEVELOPER EXPERIENCE
-- ============================================================================

CREATE OR REPLACE VIEW test_suite_summary AS
SELECT
    rtc.rule_name,
    COUNT(*) as total_tests,
    COUNT(*) FILTER (WHERE enabled = true) as enabled_tests,
    COUNT(DISTINCT rtc.test_id) FILTER (
        WHERE EXISTS (
            SELECT 1 FROM rule_test_results rtr
            WHERE rtr.test_id = rtc.test_id
            AND rtr.passed = true
            ORDER BY rtr.executed_at DESC LIMIT 1
        )
    ) as passing_tests,
    MAX(rtr.executed_at) as last_run,
    ROUND(AVG(rtr.execution_time_ms)::NUMERIC, 2) as avg_execution_time_ms
FROM rule_test_cases rtc
LEFT JOIN rule_test_results rtr ON rtc.test_id = rtr.test_id
GROUP BY rtc.rule_name;

CREATE OR REPLACE VIEW recent_test_failures AS
SELECT
    rtr.result_id,
    rtc.test_name,
    rtc.rule_name,
    rtr.executed_at,
    rtr.error_message,
    rtr.execution_time_ms
FROM rule_test_results rtr
JOIN rule_test_cases rtc ON rtr.test_id = rtc.test_id
WHERE rtr.passed = false
ORDER BY rtr.executed_at DESC
LIMIT 50;

CREATE OR REPLACE VIEW template_usage_stats AS
SELECT
    rt.template_name,
    rt.category,
    rt.usage_count,
    COUNT(rti.instance_id) as total_instances,
    MAX(rti.created_at) as last_used,
    rt.created_at
FROM rule_templates rt
LEFT JOIN rule_template_instances rti ON rt.template_id = rti.template_id
GROUP BY rt.template_id, rt.template_name, rt.category, rt.usage_count, rt.created_at
ORDER BY rt.usage_count DESC;

-- ============================================================================
-- SAMPLE TEMPLATES
-- ============================================================================

INSERT INTO rule_templates (template_name, description, grl_template, parameters, category, tags) VALUES
(
    'threshold_check',
    'Checks if a numeric value exceeds a threshold',
    'rule ThresholdCheck "Check if {{field}} exceeds {{threshold}}" salience 10 {
    when
        {{field}} > {{threshold}}
    then
        Result.triggered = true;
        Result.message = "{{field}} exceeded threshold of {{threshold}}";
        Retract("ThresholdCheck");
    }',
    '[{"name": "field", "type": "string", "description": "Field path to check"},
      {"name": "threshold", "type": "number", "description": "Threshold value"}]'::JSONB,
    'validation',
    ARRAY['threshold', 'validation', 'numeric']
),
(
    'tier_assignment',
    'Assigns tier based on value ranges',
    'rule TierAssignment "Assign tier based on {{metric}}" salience 10 {
    when
        {{metric}} >= {{tier1_min}} && {{metric}} < {{tier2_min}}
    then
        Result.tier = "{{tier1_name}}";
        Retract("TierAssignment");
    }',
    '[{"name": "metric", "type": "string", "description": "Metric to evaluate"},
      {"name": "tier1_min", "type": "number", "description": "Tier 1 minimum value"},
      {"name": "tier2_min", "type": "number", "description": "Tier 2 minimum value"},
      {"name": "tier1_name", "type": "string", "description": "Tier 1 name", "default": "Bronze"}]'::JSONB,
    'classification',
    ARRAY['tier', 'classification', 'range']
),
(
    'discount_rule',
    'Applies discount based on conditions',
    'rule DiscountRule "Apply {{discount_pct}}% discount when {{condition}}" salience 10 {
    when
        {{condition}}
    then
        Result.discount = {{discount_pct}};
        Result.discount_applied = true;
        Retract("DiscountRule");
    }',
    '[{"name": "condition", "type": "string", "description": "Condition expression"},
      {"name": "discount_pct", "type": "number", "description": "Discount percentage"}]'::JSONB,
    'pricing',
    ARRAY['discount', 'pricing', 'promotion']
)
ON CONFLICT (template_name) DO NOTHING;

-- ============================================================================
-- SCHEMA MIGRATIONS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    description TEXT,
    applied_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO schema_migrations (version, description, applied_at)
VALUES ('004', 'Developer Experience - Testing, Validation, Debugging, Templates', CURRENT_TIMESTAMP)
ON CONFLICT (version) DO NOTHING;
-- Migration 005: Webhook Support (Phase 4.2)
-- Created: 2025-12-09
-- Description: HTTP callouts from rules, webhook management, retry logic

-- ============================================================================
-- WEBHOOK REGISTRY & CONFIGURATION
-- ============================================================================

-- Table: rule_webhooks
-- Stores webhook endpoint configurations
CREATE TABLE IF NOT EXISTS rule_webhooks (
    webhook_id SERIAL PRIMARY KEY,
    webhook_name TEXT NOT NULL UNIQUE,
    description TEXT,
    url TEXT NOT NULL,
    method TEXT DEFAULT 'POST' CHECK (method IN ('GET', 'POST', 'PUT', 'PATCH', 'DELETE')),
    headers JSONB DEFAULT '{}'::JSONB, -- {"Content-Type": "application/json", "Authorization": "Bearer ..."}
    timeout_ms INTEGER DEFAULT 5000 CHECK (timeout_ms > 0 AND timeout_ms <= 60000),
    retry_enabled BOOLEAN DEFAULT true,
    max_retries INTEGER DEFAULT 3 CHECK (max_retries >= 0 AND max_retries <= 10),
    retry_delay_ms INTEGER DEFAULT 1000 CHECK (retry_delay_ms >= 0),
    retry_backoff_multiplier NUMERIC DEFAULT 2.0 CHECK (retry_backoff_multiplier >= 1.0),
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    tags TEXT[] DEFAULT '{}'
);

-- Table: rule_webhook_secrets
-- Stores encrypted secrets for webhooks (API keys, tokens)
CREATE TABLE IF NOT EXISTS rule_webhook_secrets (
    secret_id SERIAL PRIMARY KEY,
    webhook_id INTEGER REFERENCES rule_webhooks(webhook_id) ON DELETE CASCADE,
    secret_name TEXT NOT NULL, -- e.g., 'api_key', 'signing_secret'
    secret_value TEXT NOT NULL, -- Should be encrypted in production
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER,
    UNIQUE(webhook_id, secret_name)
);

-- Table: rule_webhook_calls
-- Queue and history of webhook calls
CREATE TABLE IF NOT EXISTS rule_webhook_calls (
    call_id SERIAL PRIMARY KEY,
    webhook_id INTEGER REFERENCES rule_webhooks(webhook_id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'success', 'failed', 'retrying')),
    payload JSONB NOT NULL,
    rule_name TEXT, -- Which rule triggered this
    rule_execution_id BIGINT, -- Link to rule execution if tracked
    scheduled_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    retry_count INTEGER DEFAULT 0,
    next_retry_at TIMESTAMPTZ,
    response_status INTEGER, -- HTTP status code
    response_body TEXT,
    response_headers JSONB,
    error_message TEXT,
    execution_time_ms NUMERIC,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Table: rule_webhook_call_history
-- Detailed history of all attempts including retries
CREATE TABLE IF NOT EXISTS rule_webhook_call_history (
    history_id SERIAL PRIMARY KEY,
    call_id INTEGER REFERENCES rule_webhook_calls(call_id) ON DELETE CASCADE,
    attempt_number INTEGER NOT NULL,
    started_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    response_status INTEGER,
    response_body TEXT,
    error_message TEXT,
    execution_time_ms NUMERIC
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_webhooks_enabled ON rule_webhooks(enabled) WHERE enabled = true;
CREATE INDEX IF NOT EXISTS idx_webhook_calls_status ON rule_webhook_calls(status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_webhook_calls_webhook ON rule_webhook_calls(webhook_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_webhook_calls_retry ON rule_webhook_calls(next_retry_at) WHERE status = 'retrying';

-- ============================================================================
-- WEBHOOK MANAGEMENT FUNCTIONS
-- ============================================================================

-- Function: rule_webhook_register
-- Registers a new webhook endpoint
CREATE OR REPLACE FUNCTION rule_webhook_register(
    p_name TEXT,
    p_url TEXT,
    p_method TEXT DEFAULT 'POST',
    p_headers JSONB DEFAULT '{}'::JSONB,
    p_description TEXT DEFAULT NULL,
    p_timeout_ms INTEGER DEFAULT 5000,
    p_max_retries INTEGER DEFAULT 3
) RETURNS INTEGER AS $$
DECLARE
    v_webhook_id INTEGER;
BEGIN
    -- Validate URL format
    IF p_url !~ '^https?://' THEN
        RAISE EXCEPTION 'Invalid URL format. Must start with http:// or https://';
    END IF;

    INSERT INTO rule_webhooks (
        webhook_name, url, method, headers, description,
        timeout_ms, max_retries
    ) VALUES (
        p_name, p_url, UPPER(p_method), p_headers, p_description,
        p_timeout_ms, p_max_retries
    ) RETURNING webhook_id INTO v_webhook_id;

    RETURN v_webhook_id;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_webhook_update
-- Updates webhook configuration
CREATE OR REPLACE FUNCTION rule_webhook_update(
    p_webhook_id INTEGER,
    p_url TEXT DEFAULT NULL,
    p_method TEXT DEFAULT NULL,
    p_headers JSONB DEFAULT NULL,
    p_timeout_ms INTEGER DEFAULT NULL,
    p_enabled BOOLEAN DEFAULT NULL
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE rule_webhooks SET
        url = COALESCE(p_url, url),
        method = COALESCE(UPPER(p_method), method),
        headers = COALESCE(p_headers, headers),
        timeout_ms = COALESCE(p_timeout_ms, timeout_ms),
        enabled = COALESCE(p_enabled, enabled),
        updated_at = CURRENT_TIMESTAMP
    WHERE webhook_id = p_webhook_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_webhook_delete
-- Deletes a webhook (cascade deletes calls and secrets)
CREATE OR REPLACE FUNCTION rule_webhook_delete(p_webhook_id INTEGER)
RETURNS BOOLEAN AS $$
BEGIN
    DELETE FROM rule_webhooks WHERE webhook_id = p_webhook_id;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_webhook_list
-- Lists all webhooks
CREATE OR REPLACE FUNCTION rule_webhook_list(p_enabled_only BOOLEAN DEFAULT false)
RETURNS TABLE (
    webhook_id INTEGER,
    webhook_name TEXT,
    url TEXT,
    method TEXT,
    enabled BOOLEAN,
    total_calls BIGINT,
    success_rate NUMERIC,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        w.webhook_id,
        w.webhook_name,
        w.url,
        w.method,
        w.enabled,
        COUNT(c.call_id) as total_calls,
        ROUND(
            CASE
                WHEN COUNT(c.call_id) > 0 THEN
                    (COUNT(*) FILTER (WHERE c.status = 'success')::NUMERIC / COUNT(*) * 100)
                ELSE 0
            END, 2
        ) as success_rate,
        w.created_at
    FROM rule_webhooks w
    LEFT JOIN rule_webhook_calls c ON w.webhook_id = c.webhook_id
    WHERE (NOT p_enabled_only OR w.enabled = true)
    GROUP BY w.webhook_id
    ORDER BY w.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_webhook_get
-- Gets webhook configuration by ID or name
CREATE OR REPLACE FUNCTION rule_webhook_get(p_identifier TEXT)
RETURNS JSON AS $$
DECLARE
    v_webhook rule_webhooks%ROWTYPE;
BEGIN
    BEGIN
        SELECT * INTO v_webhook FROM rule_webhooks
        WHERE webhook_id = p_identifier::INTEGER;
    EXCEPTION WHEN OTHERS THEN
        SELECT * INTO v_webhook FROM rule_webhooks
        WHERE webhook_name = p_identifier;
    END;

    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Webhook not found');
    END IF;

    RETURN row_to_json(v_webhook);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- WEBHOOK SECRET MANAGEMENT
-- ============================================================================

-- Function: rule_webhook_secret_set
-- Sets a secret for a webhook
CREATE OR REPLACE FUNCTION rule_webhook_secret_set(
    p_webhook_id INTEGER,
    p_secret_name TEXT,
    p_secret_value TEXT
) RETURNS BOOLEAN AS $$
BEGIN
    -- In production, encrypt p_secret_value before storing
    -- For now, storing as-is (WARNING: not secure for production)
    INSERT INTO rule_webhook_secrets (webhook_id, secret_name, secret_value)
    VALUES (p_webhook_id, p_secret_name, p_secret_value)
    ON CONFLICT (webhook_id, secret_name) DO UPDATE
    SET secret_value = EXCLUDED.secret_value,
        created_at = CURRENT_TIMESTAMP;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_webhook_secret_get
-- Gets a secret value (use carefully!)
CREATE OR REPLACE FUNCTION rule_webhook_secret_get(
    p_webhook_id INTEGER,
    p_secret_name TEXT
) RETURNS TEXT AS $$
DECLARE
    v_secret_value TEXT;
BEGIN
    SELECT secret_value INTO v_secret_value
    FROM rule_webhook_secrets
    WHERE webhook_id = p_webhook_id AND secret_name = p_secret_name;

    RETURN v_secret_value;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: rule_webhook_secret_delete
-- Removes a secret
CREATE OR REPLACE FUNCTION rule_webhook_secret_delete(
    p_webhook_id INTEGER,
    p_secret_name TEXT
) RETURNS BOOLEAN AS $$
BEGIN
    DELETE FROM rule_webhook_secrets
    WHERE webhook_id = p_webhook_id AND secret_name = p_secret_name;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- WEBHOOK EXECUTION FUNCTIONS
-- ============================================================================

-- Function: rule_webhook_enqueue
-- Enqueues a webhook call for processing
CREATE OR REPLACE FUNCTION rule_webhook_enqueue(
    p_webhook_id INTEGER,
    p_payload JSONB,
    p_rule_name TEXT DEFAULT NULL,
    p_scheduled_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
) RETURNS INTEGER AS $$
DECLARE
    v_call_id INTEGER;
    v_webhook rule_webhooks%ROWTYPE;
BEGIN
    -- Check if webhook exists and is enabled
    SELECT * INTO v_webhook FROM rule_webhooks WHERE webhook_id = p_webhook_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Webhook not found: %', p_webhook_id;
    END IF;

    IF NOT v_webhook.enabled THEN
        RAISE EXCEPTION 'Webhook is disabled: %', v_webhook.webhook_name;
    END IF;

    -- Enqueue the call
    INSERT INTO rule_webhook_calls (
        webhook_id, payload, rule_name, scheduled_at, status
    ) VALUES (
        p_webhook_id, p_payload, p_rule_name, p_scheduled_at, 'pending'
    ) RETURNING call_id INTO v_call_id;

    RETURN v_call_id;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_webhook_call
-- Synchronous webhook call (requires http extension or external processor)
-- This is a placeholder that enqueues the call
-- In production, use with pgsql-http extension or external worker
CREATE OR REPLACE FUNCTION rule_webhook_call(
    p_webhook_id INTEGER,
    p_payload JSONB
) RETURNS JSON AS $$
DECLARE
    v_call_id INTEGER;
    v_webhook rule_webhooks%ROWTYPE;
    v_result JSON;
BEGIN
    -- Get webhook configuration
    SELECT * INTO v_webhook FROM rule_webhooks WHERE webhook_id = p_webhook_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Webhook not found'
        );
    END IF;

    IF NOT v_webhook.enabled THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Webhook is disabled'
        );
    END IF;

    -- Enqueue the call
    v_call_id := rule_webhook_enqueue(p_webhook_id, p_payload);

    -- Note: Actual HTTP call requires http extension or external worker
    -- This function returns the queued call info
    RETURN json_build_object(
        'success', true,
        'call_id', v_call_id,
        'status', 'enqueued',
        'webhook_name', v_webhook.webhook_name,
        'url', v_webhook.url,
        'message', 'Webhook call enqueued. Requires http extension or external worker to process.'
    );
END;
$$ LANGUAGE plpgsql;

-- Function: rule_webhook_call_with_http (if http extension is available)
-- This function uses pgsql-http extension if installed
CREATE OR REPLACE FUNCTION rule_webhook_call_with_http(
    p_webhook_id INTEGER,
    p_payload JSONB
) RETURNS JSON AS $$
DECLARE
    v_webhook rule_webhooks%ROWTYPE;
    v_call_id INTEGER;
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_response RECORD;
    v_has_http BOOLEAN;
BEGIN
    -- Check if http extension is available
    SELECT EXISTS(
        SELECT 1 FROM pg_extension WHERE extname = 'http'
    ) INTO v_has_http;

    IF NOT v_has_http THEN
        RETURN json_build_object(
            'success', false,
            'error', 'HTTP extension not installed. Install with: CREATE EXTENSION http;'
        );
    END IF;

    -- Get webhook config
    SELECT * INTO v_webhook FROM rule_webhooks WHERE webhook_id = p_webhook_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Webhook not found');
    END IF;

    -- Create call record
    INSERT INTO rule_webhook_calls (webhook_id, payload, status, started_at)
    VALUES (p_webhook_id, p_payload, 'processing', CURRENT_TIMESTAMP)
    RETURNING call_id INTO v_call_id;

    v_start_time := clock_timestamp();

    BEGIN
        -- Make HTTP request using http extension
        -- Note: This requires http extension to be installed
        EXECUTE format(
            'SELECT status, content, headers FROM http((
                SELECT ROW(
                    %L,
                    %L,
                    %L,
                    %L,
                    %L
                )::http_request
            ))',
            v_webhook.method,
            v_webhook.url,
            v_webhook.headers,
            'application/json',
            p_payload::TEXT
        ) INTO v_response;

        v_end_time := clock_timestamp();

        -- Update call with success
        UPDATE rule_webhook_calls SET
            status = 'success',
            completed_at = v_end_time,
            response_status = v_response.status,
            response_body = v_response.content,
            response_headers = v_response.headers,
            execution_time_ms = EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000
        WHERE call_id = v_call_id;

        -- Log attempt
        INSERT INTO rule_webhook_call_history (
            call_id, attempt_number, started_at, completed_at,
            response_status, response_body, execution_time_ms
        ) VALUES (
            v_call_id, 1, v_start_time, v_end_time,
            v_response.status, v_response.content,
            EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000
        );

        RETURN json_build_object(
            'success', true,
            'call_id', v_call_id,
            'status', v_response.status,
            'response', v_response.content,
            'execution_time_ms', EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000
        );

    EXCEPTION WHEN OTHERS THEN
        v_end_time := clock_timestamp();

        -- Update call with error
        UPDATE rule_webhook_calls SET
            status = 'failed',
            completed_at = v_end_time,
            error_message = SQLERRM,
            execution_time_ms = EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000
        WHERE call_id = v_call_id;

        -- Log failed attempt
        INSERT INTO rule_webhook_call_history (
            call_id, attempt_number, started_at, completed_at,
            error_message, execution_time_ms
        ) VALUES (
            v_call_id, 1, v_start_time, v_end_time,
            SQLERRM, EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000
        );

        RETURN json_build_object(
            'success', false,
            'call_id', v_call_id,
            'error', SQLERRM
        );
    END;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- RETRY & RECOVERY FUNCTIONS
-- ============================================================================

-- Function: rule_webhook_retry
-- Marks a failed call for retry
CREATE OR REPLACE FUNCTION rule_webhook_retry(p_call_id INTEGER)
RETURNS BOOLEAN AS $$
DECLARE
    v_call rule_webhook_calls%ROWTYPE;
    v_webhook rule_webhooks%ROWTYPE;
    v_next_delay_ms INTEGER;
BEGIN
    SELECT * INTO v_call FROM rule_webhook_calls WHERE call_id = p_call_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Call not found: %', p_call_id;
    END IF;

    SELECT * INTO v_webhook FROM rule_webhooks WHERE webhook_id = v_call.webhook_id;

    -- Check if retry is enabled and not exceeded max retries
    IF NOT v_webhook.retry_enabled THEN
        RETURN false;
    END IF;

    IF v_call.retry_count >= v_webhook.max_retries THEN
        UPDATE rule_webhook_calls
        SET status = 'failed',
            error_message = 'Max retries exceeded'
        WHERE call_id = p_call_id;
        RETURN false;
    END IF;

    -- Calculate next retry delay with exponential backoff
    v_next_delay_ms := v_webhook.retry_delay_ms *
        (v_webhook.retry_backoff_multiplier ^ v_call.retry_count);

    -- Update call for retry
    UPDATE rule_webhook_calls SET
        status = 'retrying',
        retry_count = retry_count + 1,
        next_retry_at = CURRENT_TIMESTAMP + (v_next_delay_ms || ' milliseconds')::INTERVAL
    WHERE call_id = p_call_id;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_webhook_process_retries
-- Processes pending retries (called by scheduler/cron)
CREATE OR REPLACE FUNCTION rule_webhook_process_retries()
RETURNS TABLE (
    call_id INTEGER,
    webhook_name TEXT,
    retry_result JSON
) AS $$
DECLARE
    v_call RECORD;
BEGIN
    FOR v_call IN
        SELECT
            c.call_id,
            c.webhook_id,
            c.payload,
            w.webhook_name
        FROM rule_webhook_calls c
        JOIN rule_webhooks w ON c.webhook_id = w.webhook_id
        WHERE c.status = 'retrying'
          AND c.next_retry_at <= CURRENT_TIMESTAMP
        ORDER BY c.next_retry_at
        LIMIT 100
    LOOP
        -- Try to execute the webhook again
        -- In production, this would call the actual HTTP function
        RETURN QUERY SELECT
            v_call.call_id,
            v_call.webhook_name,
            json_build_object(
                'status', 'retry_enqueued',
                'message', 'Retry scheduled for processing'
            );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- MONITORING & ANALYTICS VIEWS
-- ============================================================================

-- View: webhook_status_summary
-- Summary of webhook call statuses
CREATE OR REPLACE VIEW webhook_status_summary AS
SELECT
    w.webhook_id,
    w.webhook_name,
    w.url,
    w.enabled,
    COUNT(c.call_id) as total_calls,
    COUNT(*) FILTER (WHERE c.status = 'success') as successful_calls,
    COUNT(*) FILTER (WHERE c.status = 'failed') as failed_calls,
    COUNT(*) FILTER (WHERE c.status = 'pending') as pending_calls,
    COUNT(*) FILTER (WHERE c.status = 'retrying') as retrying_calls,
    ROUND(AVG(c.execution_time_ms)::NUMERIC, 2) as avg_execution_time_ms,
    MAX(c.created_at) as last_call_at,
    ROUND(
        CASE
            WHEN COUNT(c.call_id) > 0 THEN
                (COUNT(*) FILTER (WHERE c.status = 'success')::NUMERIC / COUNT(*) * 100)
            ELSE 0
        END, 2
    ) as success_rate_pct
FROM rule_webhooks w
LEFT JOIN rule_webhook_calls c ON w.webhook_id = c.webhook_id
GROUP BY w.webhook_id, w.webhook_name, w.url, w.enabled;

-- View: webhook_recent_failures
-- Recent failed webhook calls for debugging
CREATE OR REPLACE VIEW webhook_recent_failures AS
SELECT
    c.call_id,
    w.webhook_name,
    w.url,
    c.status,
    c.retry_count,
    c.error_message,
    c.response_status,
    c.payload,
    c.created_at,
    c.completed_at
FROM rule_webhook_calls c
JOIN rule_webhooks w ON c.webhook_id = w.webhook_id
WHERE c.status IN ('failed', 'retrying')
ORDER BY c.created_at DESC
LIMIT 100;

-- View: webhook_performance_stats
-- Performance statistics per webhook
CREATE OR REPLACE VIEW webhook_performance_stats AS
SELECT
    w.webhook_id,
    w.webhook_name,
    COUNT(c.call_id) as total_calls,
    ROUND(AVG(c.execution_time_ms)::NUMERIC, 2) as avg_time_ms,
    ROUND(MIN(c.execution_time_ms)::NUMERIC, 2) as min_time_ms,
    ROUND(MAX(c.execution_time_ms)::NUMERIC, 2) as max_time_ms,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY c.execution_time_ms)::NUMERIC, 2) as p50_time_ms,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY c.execution_time_ms)::NUMERIC, 2) as p95_time_ms,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY c.execution_time_ms)::NUMERIC, 2) as p99_time_ms
FROM rule_webhooks w
LEFT JOIN rule_webhook_calls c ON w.webhook_id = c.webhook_id
WHERE c.status = 'success'
GROUP BY w.webhook_id, w.webhook_name
HAVING COUNT(c.call_id) > 0;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function: rule_webhook_call_status
-- Gets the status of a webhook call
CREATE OR REPLACE FUNCTION rule_webhook_call_status(p_call_id INTEGER)
RETURNS JSON AS $$
DECLARE
    v_call rule_webhook_calls%ROWTYPE;
    v_webhook rule_webhooks%ROWTYPE;
    v_attempts JSON;
BEGIN
    SELECT * INTO v_call FROM rule_webhook_calls WHERE call_id = p_call_id;

    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Call not found');
    END IF;

    SELECT * INTO v_webhook FROM rule_webhooks WHERE webhook_id = v_call.webhook_id;

    -- Get all attempts
    SELECT json_agg(row_to_json(h)) INTO v_attempts
    FROM rule_webhook_call_history h
    WHERE h.call_id = p_call_id
    ORDER BY h.attempt_number;

    RETURN json_build_object(
        'call_id', v_call.call_id,
        'webhook_name', v_webhook.webhook_name,
        'url', v_webhook.url,
        'status', v_call.status,
        'retry_count', v_call.retry_count,
        'payload', v_call.payload,
        'response_status', v_call.response_status,
        'response_body', v_call.response_body,
        'error_message', v_call.error_message,
        'execution_time_ms', v_call.execution_time_ms,
        'scheduled_at', v_call.scheduled_at,
        'started_at', v_call.started_at,
        'completed_at', v_call.completed_at,
        'next_retry_at', v_call.next_retry_at,
        'attempts', COALESCE(v_attempts, '[]'::JSON)
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- CLEANUP FUNCTIONS
-- ============================================================================

-- Function: rule_webhook_cleanup_old_calls
-- Removes old webhook call records
CREATE OR REPLACE FUNCTION rule_webhook_cleanup_old_calls(
    p_older_than INTERVAL DEFAULT '30 days',
    p_keep_failed BOOLEAN DEFAULT true
) RETURNS BIGINT AS $$
DECLARE
    v_deleted_count BIGINT;
BEGIN
    DELETE FROM rule_webhook_calls
    WHERE created_at < (CURRENT_TIMESTAMP - p_older_than)
      AND (NOT p_keep_failed OR status = 'success')
    ;

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- SCHEMA MIGRATIONS TABLE UPDATE
-- ============================================================================

