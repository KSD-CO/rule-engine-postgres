# Rule Repository Quick Reference

Quick reference guide for the Rule Repository & Versioning system (v1.1.0+).

## Installation

```sql
-- Run migration to create schema
\i migrations/001_rule_repository.sql
```

## Core Functions

### Save Rules

```sql
-- Save new rule (auto-versioned as 1.0.0)
SELECT rule_save(
    'rule_name',
    'rule "MyRule" { when X > 10 then Y = 20; }',
    NULL,          -- NULL = auto version
    'Description',
    'Change notes'
);

-- Save explicit version
SELECT rule_save(
    'rule_name',
    'rule "MyRule" { when X > 10 then Y = 30; }',
    '2.0.0',       -- Explicit version
    'Updated logic',
    'Changed Y from 20 to 30'
);
```

### Retrieve Rules

```sql
-- Get default version
SELECT rule_get('rule_name', NULL);

-- Get specific version
SELECT rule_get('rule_name', '1.0.0');
```

### Execute Rules

```sql
-- Forward chaining (execute rules)
SELECT rule_execute_by_name(
    'rule_name',
    '{"X": 15}',
    NULL  -- Uses default version
);

-- Backward chaining (query goal with proof trace)
SELECT rule_query_by_name(
    'rule_name',
    '{"X": 15}',
    'Y == 20',
    NULL
)::jsonb;

-- Backward chaining (fast boolean check)
SELECT rule_can_prove_by_name(
    'rule_name',
    '{"X": 15}',
    'Y == 20',
    NULL
);
```

### Version Management

```sql
-- Activate version as default
SELECT rule_activate('rule_name', '2.0.0');

-- Delete non-default version
SELECT rule_delete('rule_name', '1.0.0');

-- Delete entire rule (all versions)
SELECT rule_delete('rule_name', NULL);
```

### Tagging

```sql
-- Add tags
SELECT rule_tag_add('rule_name', 'production');
SELECT rule_tag_add('rule_name', 'billing');
SELECT rule_tag_add('rule_name', 'critical');

-- Remove tag
SELECT rule_tag_remove('rule_name', 'billing');
```

## Database Queries

### List All Rules

```sql
SELECT 
    name,
    description,
    is_active,
    created_at,
    updated_at
FROM rule_definitions
ORDER BY name;
```

### List All Versions

```sql
SELECT 
    rd.name,
    rv.version,
    rv.is_default,
    rv.created_at,
    rv.change_notes
FROM rule_versions rv
JOIN rule_definitions rd ON rv.rule_id = rd.id
WHERE rd.name = 'rule_name'
ORDER BY rv.created_at DESC;
```

### View Rule Catalog

```sql
-- Pre-built view with all information
SELECT 
    name,
    description,
    default_version,
    tags,
    rule_created_at,
    updated_at
FROM rule_catalog
WHERE is_active = true
ORDER BY name;
```

### Find Rules by Tag

```sql
SELECT DISTINCT rd.name, rd.description
FROM rule_definitions rd
JOIN rule_tags rt ON rt.rule_id = rd.id
WHERE rt.tag = 'production'
ORDER BY rd.name;

-- Or use the catalog view
SELECT name, default_version
FROM rule_catalog
WHERE 'production' = ANY(tags);
```

### Audit Trail

```sql
-- View all changes for a rule
SELECT 
    action,
    changed_at,
    changed_by,
    details
FROM rule_audit_log
WHERE rule_id = (SELECT id FROM rule_definitions WHERE name = 'rule_name')
ORDER BY changed_at DESC;
```

## Database Schema

### Tables

- **`rule_definitions`**: Main rule records (id, name, description, is_active, timestamps)
- **`rule_versions`**: Version history (id, rule_id, version, grl_content, is_default, change_notes)
- **`rule_tags`**: Tags for organization (id, rule_id, tag)
- **`rule_audit_log`**: Automatic audit trail (id, rule_id, action, changed_at, changed_by, details)

### Triggers

- **Single Default Version**: Automatically unsets other defaults when one is set
- **Audit Logging**: Automatically logs all INSERT/UPDATE/DELETE operations
- **Updated Timestamp**: Automatically updates `updated_at` on changes

### Views

- **`rule_catalog`**: Complete view with all rule info, default version, and tags

## Best Practices

### Versioning Strategy

```sql
-- MAJOR: Breaking changes
SELECT rule_save('rule_name', '...', '2.0.0', ...);  -- Changed behavior

-- MINOR: New features, backward compatible
SELECT rule_save('rule_name', '...', '1.1.0', ...);  -- Added condition

-- PATCH: Bug fixes, no behavior change
SELECT rule_save('rule_name', '...', '1.0.1', ...);  -- Fixed typo
```

### Tag Organization

```sql
-- Environment tags
SELECT rule_tag_add('rule_name', 'production');
SELECT rule_tag_add('rule_name', 'staging');
SELECT rule_tag_add('rule_name', 'development');

-- Category tags
SELECT rule_tag_add('rule_name', 'billing');
SELECT rule_tag_add('rule_name', 'validation');
SELECT rule_tag_add('rule_name', 'compliance');

-- Priority tags
SELECT rule_tag_add('rule_name', 'critical');
SELECT rule_tag_add('rule_name', 'low-priority');
```

### Safe Deployments

```sql
-- 1. Save new version (doesn't activate)
SELECT rule_save('pricing_rules', '...', '2.0.0', ...);

-- 2. Test new version
SELECT rule_execute_by_name('pricing_rules', '{"test": "data"}', '2.0.0');

-- 3. Activate when ready
SELECT rule_activate('pricing_rules', '2.0.0');

-- 4. Rollback if needed
SELECT rule_activate('pricing_rules', '1.0.0');
```

### Production Patterns

```sql
-- Execute all production rules for an order
WITH production_rules AS (
    SELECT rd.name
    FROM rule_definitions rd
    JOIN rule_tags rt ON rt.rule_id = rd.id
    WHERE rt.tag = 'production' AND rd.is_active = true
)
SELECT 
    pr.name,
    rule_execute_by_name(pr.name, order_data::text, NULL) as result
FROM production_rules pr
CROSS JOIN orders
WHERE orders.id = 12345;
```

## Error Codes

- **RE-001**: Invalid rule name format
- **RE-002**: GRL content validation failed
- **RE-003**: Invalid semantic version format
- **RE-101**: Rule not found
- **RE-102**: Version not found
- **RE-201**: Cannot delete default version (activate another first)

## Limits

- Rule name: max 255 characters
- GRL content: max 1MB
- Tag name: max 100 characters
- Description: max 1000 characters
- Change notes: max 5000 characters

## Examples

### E-Commerce Pricing

```sql
-- Save discount rules
SELECT rule_save(
    'discount_calculator',
    'rule "VIP" salience 100 {
        when Customer.Tier == "VIP" && Order.Total > 100
        then Order.Discount = Order.Total * 0.20;
    }
    rule "Standard" salience 10 {
        when Order.Total > 50
        then Order.Discount = Order.Total * 0.10;
    }',
    '1.0.0',
    'Multi-tier discount system',
    'Initial version with VIP and standard tiers'
);

-- Tag it
SELECT rule_tag_add('discount_calculator', 'production');
SELECT rule_tag_add('discount_calculator', 'pricing');

-- Execute
SELECT rule_execute_by_name(
    'discount_calculator',
    '{"Customer": {"Tier": "VIP"}, "Order": {"Total": 150}}',
    NULL
);
-- Returns: {"Customer":{"Tier":"VIP"},"Order":{"Total":150,"Discount":30}}
```

### Validation Rules

```sql
-- Save validation rules
SELECT rule_save(
    'order_validation',
    'rule "MinAmount" {
        when Order.Amount < 10
        then Order.Valid = false; Order.Error = "Minimum order is $10";
    }
    rule "MaxAmount" {
        when Order.Amount > 10000
        then Order.NeedsApproval = true;
    }',
    '1.0.0',
    'Order validation rules',
    'Basic amount checks'
);

SELECT rule_tag_add('order_validation', 'validation');
SELECT rule_tag_add('order_validation', 'critical');

-- Use in trigger
CREATE OR REPLACE FUNCTION validate_order()
RETURNS TRIGGER AS $$
BEGIN
    NEW.data := rule_execute_by_name(
        'order_validation',
        NEW.data::text,
        NULL
    )::jsonb;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER order_validate
    BEFORE INSERT OR UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION validate_order();
```

## Migration from Legacy

If you were storing rules in your own table:

```sql
-- Old approach
CREATE TABLE business_rules (
    id SERIAL PRIMARY KEY,
    name TEXT,
    grl TEXT
);

-- Migrate to Rule Repository
INSERT INTO rule_definitions (name, description, created_by, updated_by, is_active)
SELECT name, 'Migrated from legacy', 'migration', 'migration', true
FROM business_rules;

INSERT INTO rule_versions (rule_id, version, grl_content, is_default, change_notes)
SELECT 
    rd.id,
    '1.0.0',
    br.grl,
    true,
    'Migrated from legacy business_rules table'
FROM business_rules br
JOIN rule_definitions rd ON rd.name = br.name;

-- Drop old table after verification
DROP TABLE business_rules;
```

## See Also

- [API Reference](../api-reference.md) - Complete function documentation
- [RFC-0001](../rfcs/0001-rule-repository.md) - Technical design document
- [README](../../README.md#rule-repository--versioning) - Main documentation
