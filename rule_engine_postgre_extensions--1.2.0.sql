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
LANGUAGE C STRICT;-- Migration: Rule Repository & Versioning
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
    rule_id INTEGER NOT NULL REFERENCES rule_definitions(id) ON DELETE CASCADE,
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
