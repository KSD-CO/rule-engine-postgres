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
