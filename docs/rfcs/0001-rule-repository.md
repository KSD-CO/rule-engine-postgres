# RFC-0001: Rule Repository & Versioning

- **Status:** Draft
- **Author:** Rule Engine Team
- **Created:** 2025-12-06
- **Updated:** 2025-12-06
- **Phase:** 1.1 (Foundation)
- **Priority:** P0 - Critical

---

## Summary

Implement a persistent storage system for GRL rules with semantic versioning, metadata management, and CRUD operations. This enables rules to be stored in the database rather than passed as text strings, supporting production workflows like version control, rollback, and rule governance.

---

## Motivation

Currently, users must pass GRL rules as text strings to `run_rule_engine()`. This approach has several limitations:

1. **No Persistence:** Rules exist only in application code or external files
2. **No Version History:** Cannot track rule changes over time
3. **No Reusability:** Same rules must be duplicated across calls
4. **No Governance:** No approval workflows or audit trails
5. **Deployment Complexity:** Rule changes require application deployment

### Use Cases

1. **Production Rule Management:** Store rules in database, deploy changes without code release
2. **A/B Testing:** Compare different versions of the same rule
3. **Audit Compliance:** Track who changed what rule when
4. **Rollback Capability:** Revert to previous rule versions
5. **Rule Marketplace:** Share and discover rules across teams/organizations

### Current Limitations

- Every `run_rule_engine()` call requires the full GRL text
- No way to reference rules by name
- No change history or rollback
- Difficult to share rules across applications
- No metadata (author, description, tags)

---

## Detailed Design

### Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                 Application Layer                    │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│              Rule Repository API                     │
│  rule_save()  rule_get()  rule_list()  rule_delete() │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│              Database Tables                         │
│  rule_definitions  │  rule_versions  │  rule_tags    │
└─────────────────────────────────────────────────────┘
```

### Database Schema

```sql
-- Core rule definitions
CREATE TABLE rule_definitions (
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

CREATE INDEX idx_rule_definitions_name ON rule_definitions(name);
CREATE INDEX idx_rule_definitions_active ON rule_definitions(is_active);

-- Rule versions with semantic versioning
CREATE TABLE rule_versions (
    id SERIAL PRIMARY KEY,
    rule_id INTEGER NOT NULL REFERENCES rule_definitions(id) ON DELETE CASCADE,
    version TEXT NOT NULL, -- Semantic version: 1.0.0
    grl_content TEXT NOT NULL,
    change_notes TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_by TEXT,
    is_default BOOLEAN NOT NULL DEFAULT false,
    
    CONSTRAINT rule_version_unique UNIQUE (rule_id, version),
    CONSTRAINT version_format_valid CHECK (version ~ '^\d+\.\d+\.\d+$'),
    CONSTRAINT grl_not_empty CHECK (length(grl_content) > 0),
    CONSTRAINT grl_size_limit CHECK (length(grl_content) <= 1048576) -- 1MB
);

CREATE INDEX idx_rule_versions_rule_id ON rule_versions(rule_id);
CREATE INDEX idx_rule_versions_default ON rule_versions(rule_id, is_default) WHERE is_default = true;

-- Tags for categorization
CREATE TABLE rule_tags (
    id SERIAL PRIMARY KEY,
    rule_id INTEGER NOT NULL REFERENCES rule_definitions(id) ON DELETE CASCADE,
    tag TEXT NOT NULL,
    
    CONSTRAINT rule_tag_unique UNIQUE (rule_id, tag)
);

CREATE INDEX idx_rule_tags_tag ON rule_tags(tag);
CREATE INDEX idx_rule_tags_rule_id ON rule_tags(rule_id);

-- Audit log (separate RFC, but referenced here)
CREATE TABLE rule_audit_log (
    id SERIAL PRIMARY KEY,
    rule_id INTEGER NOT NULL REFERENCES rule_definitions(id) ON DELETE CASCADE,
    action TEXT NOT NULL, -- 'create', 'update', 'delete', 'activate', 'deactivate'
    version_before TEXT,
    version_after TEXT,
    changed_by TEXT,
    changed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    change_details JSONB
);

CREATE INDEX idx_rule_audit_rule_id ON rule_audit_log(rule_id);
CREATE INDEX idx_rule_audit_changed_at ON rule_audit_log(changed_at);
```

### API Functions

#### Function 1: `rule_save(name TEXT, grl_content TEXT, version TEXT DEFAULT NULL, description TEXT DEFAULT NULL, change_notes TEXT DEFAULT NULL) → INTEGER`

**Purpose:** Save a new rule or create a new version of existing rule

**Parameters:**
- `name` (TEXT): Unique rule name (alphanumeric + underscore/hyphen)
- `grl_content` (TEXT): GRL rule definition
- `version` (TEXT, optional): Semantic version (auto-incremented if NULL)
- `description` (TEXT, optional): Rule description
- `change_notes` (TEXT, optional): What changed in this version

**Returns:** rule_id (INTEGER)

**Example:**
```sql
-- Create new rule
SELECT rule_save(
    'discount_calculator',
    'rule "StandardDiscount" { when Order.Amount > 100 then Order.Discount = 10; }',
    '1.0.0',
    'Calculate discount for orders over $100'
);
-- Returns: 1

-- Update with new version (auto-increment)
SELECT rule_save(
    'discount_calculator',
    'rule "StandardDiscount" { when Order.Amount > 100 then Order.Discount = 15; }',
    NULL,
    NULL,
    'Increased discount from 10% to 15%'
);
-- Returns: 1 (same rule, new version 1.0.1)
```

**Errors:**
- `RE-001`: Invalid rule name format
- `RE-002`: GRL content empty or too large
- `RE-003`: Invalid semantic version format
- `RE-004`: GRL syntax validation failed

#### Function 2: `rule_get(name TEXT, version TEXT DEFAULT NULL) → TEXT`

**Purpose:** Retrieve GRL content for a rule (default version if not specified)

**Parameters:**
- `name` (TEXT): Rule name
- `version` (TEXT, optional): Specific version (uses default if NULL)

**Returns:** GRL content (TEXT)

**Example:**
```sql
-- Get default version
SELECT rule_get('discount_calculator');
-- Returns: 'rule "StandardDiscount" { ... }'

-- Get specific version
SELECT rule_get('discount_calculator', '1.0.0');
```

**Errors:**
- `RE-101`: Rule not found
- `RE-102`: Version not found
- `RE-103`: Rule is inactive

#### Function 3: `rule_list(filter_tag TEXT DEFAULT NULL, include_inactive BOOLEAN DEFAULT false) → TABLE(id, name, description, version, created_at, is_active)`

**Purpose:** List all rules with optional filtering

**Parameters:**
- `filter_tag` (TEXT, optional): Filter by tag
- `include_inactive` (BOOLEAN): Include inactive rules

**Returns:** Table of rules with metadata

**Example:**
```sql
-- List all active rules
SELECT * FROM rule_list();

-- List rules with tag 'discount'
SELECT * FROM rule_list('discount');

-- Include inactive rules
SELECT * FROM rule_list(NULL, true);
```

#### Function 4: `rule_delete(name TEXT, version TEXT DEFAULT NULL) → BOOLEAN`

**Purpose:** Delete a rule or specific version (soft delete)

**Parameters:**
- `name` (TEXT): Rule name
- `version` (TEXT, optional): Specific version (deletes all if NULL)

**Returns:** Success (BOOLEAN)

**Example:**
```sql
-- Delete specific version
SELECT rule_delete('discount_calculator', '1.0.0');

-- Delete entire rule (all versions)
SELECT rule_delete('discount_calculator');
```

**Errors:**
- `RE-201`: Rule not found
- `RE-202`: Cannot delete default version
- `RE-203`: Rule is referenced by active rule sets

#### Function 5: `rule_activate(name TEXT, version TEXT) → BOOLEAN`

**Purpose:** Set a specific version as the default/active version

**Parameters:**
- `name` (TEXT): Rule name
- `version` (TEXT): Version to activate

**Returns:** Success (BOOLEAN)

**Example:**
```sql
-- Rollback to previous version
SELECT rule_activate('discount_calculator', '1.0.0');
```

#### Function 6: `rule_versions(name TEXT) → TABLE(version, created_at, created_by, is_default, change_notes)`

**Purpose:** List all versions of a rule

**Parameters:**
- `name` (TEXT): Rule name

**Returns:** Table of versions with metadata

**Example:**
```sql
SELECT * FROM rule_versions('discount_calculator')
ORDER BY created_at DESC;
```

#### Function 7: `rule_tag_add(name TEXT, tag TEXT) → BOOLEAN`

**Purpose:** Add a tag to a rule

#### Function 8: `rule_tag_remove(name TEXT, tag TEXT) → BOOLEAN`

**Purpose:** Remove a tag from a rule

#### Function 9: `rule_execute_by_name(name TEXT, facts_json TEXT, version TEXT DEFAULT NULL) → TEXT`

**Purpose:** Execute a stored rule by name (convenience function)

**Parameters:**
- `name` (TEXT): Rule name
- `facts_json` (TEXT): Input facts
- `version` (TEXT, optional): Specific version

**Returns:** Modified facts (TEXT)

**Example:**
```sql
SELECT rule_execute_by_name(
    'discount_calculator',
    '{"Order": {"Amount": 150}}',
    '1.0.0'
);
-- Returns: '{"Order": {"Amount": 150, "Discount": 10}}'
```

### Internal Implementation

```rust
// src/repository/mod.rs
pub mod rule_repository;
pub mod version;

// src/repository/rule_repository.rs
use crate::error::RuleEngineError;

pub struct RuleDefinition {
    pub id: i32,
    pub name: String,
    pub description: Option<String>,
    pub is_active: bool,
}

pub struct RuleVersion {
    pub id: i32,
    pub rule_id: i32,
    pub version: String,
    pub grl_content: String,
    pub is_default: bool,
}

// Save rule function
#[pg_extern]
pub fn rule_save(
    name: String,
    grl_content: String,
    version: Option<String>,
    description: Option<String>,
    change_notes: Option<String>,
) -> Result<i32, RuleEngineError> {
    // 1. Validate rule name
    validate_rule_name(&name)?;
    
    // 2. Validate GRL content
    validate_grl_content(&grl_content)?;
    
    // 3. Check if rule exists
    let rule_id = if let Some(id) = get_rule_id(&name) {
        id
    } else {
        // Create new rule definition
        create_rule_definition(&name, description)?
    };
    
    // 4. Determine version number
    let version_number = match version {
        Some(v) => validate_version(&v)?,
        None => auto_increment_version(rule_id)?,
    };
    
    // 5. Insert new version
    insert_rule_version(
        rule_id,
        &version_number,
        &grl_content,
        change_notes,
    )?;
    
    // 6. Log audit trail
    log_audit(rule_id, "update", &version_number)?;
    
    Ok(rule_id)
}

// Get rule function
#[pg_extern]
pub fn rule_get(
    name: String,
    version: Option<String>,
) -> Result<String, RuleEngineError> {
    let rule_id = get_rule_id(&name)
        .ok_or(RuleEngineError::RuleNotFound(name))?;
    
    let grl_content = if let Some(v) = version {
        get_rule_version_content(rule_id, &v)?
    } else {
        get_default_version_content(rule_id)?
    };
    
    Ok(grl_content)
}
```

### Performance Considerations

- **Indexing:** B-tree indexes on `name`, `version`, `is_active`
- **Caching:** Frequently accessed rules cached in shared memory (future RFC)
- **Query Optimization:** Use prepared statements for all queries
- **Version Lookup:** Separate index for default versions
- **Size Limits:** 1MB per rule to prevent memory issues

**Benchmark Targets:**
- `rule_save()`: < 5ms
- `rule_get()`: < 1ms (without cache), < 0.1ms (with cache)
- `rule_list()`: < 10ms for 1000 rules
- `rule_execute_by_name()`: < 2ms + execution time

### Security Considerations

- **SQL Injection:** All inputs parameterized
- **Row-Level Security:** Future RFC for multi-tenancy
- **Audit Logging:** All changes logged with user context
- **Permission Model:** Future RFC for RBAC

**Validation:**
- Rule names: alphanumeric + underscore/hyphen only
- GRL content: syntax validation before save
- Version format: strict semantic versioning
- Size limits: 1MB per rule

### Migration Path

Users can continue using existing `run_rule_engine(facts, grl)` pattern. New functions are additive only.

**Migration Example:**
```sql
-- Before (still works)
SELECT run_rule_engine(
    '{"Order": {"Amount": 150}}',
    'rule "Discount" { when Order.Amount > 100 then Order.Discount = 10; }'
);

-- After (migrate to repository)
-- Step 1: Save rule once
SELECT rule_save('discount', 'rule "Discount" { ... }', '1.0.0');

-- Step 2: Execute by name
SELECT rule_execute_by_name('discount', '{"Order": {"Amount": 150}}');
```

---

## Examples

### Example 1: Development Workflow

```sql
-- Create initial rule
SELECT rule_save(
    'age_verification',
    'rule "CheckAge" { when User.Age >= 18 then User.IsAdult = true; }',
    '1.0.0',
    'Basic age verification rule'
);

-- Test in development
SELECT rule_execute_by_name(
    'age_verification',
    '{"User": {"Age": 20}}'
);

-- Update rule with new logic
SELECT rule_save(
    'age_verification',
    'rule "CheckAge" { when User.Age >= 21 then User.IsAdult = true; }',
    '2.0.0',
    NULL,
    'Changed age threshold from 18 to 21 per new requirements'
);

-- Activate new version in production
SELECT rule_activate('age_verification', '2.0.0');
```

### Example 2: A/B Testing

```sql
-- Original rule (control)
SELECT rule_save('pricing', 'rule "Price" { ... }', '1.0.0');

-- Variant for testing
SELECT rule_save('pricing', 'rule "Price" { ... }', '1.1.0-beta');

-- Route 50% to each version in application logic
SELECT CASE 
    WHEN random() < 0.5 
    THEN rule_execute_by_name('pricing', facts, '1.0.0')
    ELSE rule_execute_by_name('pricing', facts, '1.1.0-beta')
END;
```

### Example 3: Rollback Scenario

```sql
-- Production incident: rule 2.0.0 has a bug
-- Quickly rollback to previous version
SELECT rule_activate('age_verification', '1.0.0');

-- Verify rollback
SELECT * FROM rule_versions('age_verification') WHERE is_default = true;
```

---

## Alternatives Considered

### Alternative 1: External Rule Repository (REST API)

**Description:** Store rules in external service, PostgreSQL calls API

**Pros:**
- Centralized rule management across databases
- Rich UI possibilities
- Language-agnostic

**Cons:**
- Network latency on every rule lookup
- Additional infrastructure complexity
- Requires external service maintenance
- Transaction consistency issues

**Why rejected:** Adds deployment complexity and latency; against the "rules in DB" philosophy

### Alternative 2: File-Based Storage with Git

**Description:** Rules stored as files, versioned with Git

**Pros:**
- Standard version control
- Easy code review
- Developer-friendly

**Cons:**
- Rules not queryable in SQL
- Deployment process unchanged
- No runtime rule updates
- Doesn't solve the core problem

**Why rejected:** Doesn't provide database-native rule management

### Alternative 3: JSON Column Storage (No Separate Versions Table)

**Description:** Store all versions as JSONB array in single row

**Pros:**
- Simpler schema
- Fewer tables

**Cons:**
- Poor query performance
- Difficult to index
- Size limits on single row
- Harder to manage relationships

**Why rejected:** Doesn't scale, poor PostgreSQL practices

---

## Drawbacks and Risks

### Technical Risks
- **Schema Evolution:** Must maintain backward compatibility
  - *Mitigation:* Use migration scripts, versioned schema
- **Storage Growth:** Versions accumulate over time
  - *Mitigation:* Implement archival/cleanup policies (future RFC)
- **Cache Invalidation:** Stale cached rules after updates
  - *Mitigation:* Event notifications on rule changes

### Maintenance Burden
- Additional tables to maintain
- More complex backup/restore procedures
- Testing all version scenarios

### Breaking Changes
- None - all new functions
- Existing `run_rule_engine()` unchanged

---

## Dependencies

### External Dependencies
- None (uses existing pgrx framework)

### Internal Dependencies
- Error codes system (already exists)
- Validation framework (already exists)

---

## Testing Strategy

### Unit Tests
```rust
#[cfg(test)]
mod tests {
    #[test]
    fn test_rule_save_new() {
        // Test creating new rule
    }
    
    #[test]
    fn test_rule_save_version_increment() {
        // Test auto version increment
    }
    
    #[test]
    fn test_rule_get_default_version() {
        // Test retrieving default version
    }
    
    #[test]
    fn test_invalid_rule_name() {
        // Test validation errors
    }
}
```

### Integration Tests
```sql
-- tests/test_rule_repository.sql
BEGIN;

-- Test 1: Save and retrieve rule
SELECT rule_save('test_rule', 'rule "Test" { ... }', '1.0.0');
SELECT rule_get('test_rule') = 'rule "Test" { ... }';

-- Test 2: Version management
SELECT rule_save('test_rule', 'rule "Test2" { ... }', '1.0.1');
SELECT rule_activate('test_rule', '1.0.0');
SELECT rule_get('test_rule') = 'rule "Test" { ... }';

-- Test 3: Delete
SELECT rule_delete('test_rule', '1.0.1');
SELECT COUNT(*) = 1 FROM rule_versions WHERE rule_id = 1;

ROLLBACK;
```

### Performance Tests
```sql
-- Benchmark rule_save with 1000 rules
\timing on
SELECT rule_save('rule_' || i::text, 'rule "R" { ... }', '1.0.0')
FROM generate_series(1, 1000) AS i;

-- Benchmark rule_get with 10000 queries
EXPLAIN ANALYZE
SELECT rule_get('rule_500')
FROM generate_series(1, 10000);
```

---

## Documentation Plan

- [x] API reference in docs/api-reference.md
- [ ] Tutorial: "Migrating from inline rules to repository"
- [ ] Guide: "Rule versioning best practices"
- [ ] Guide: "Production rule deployment workflow"
- [ ] FAQ: "When to use repository vs inline rules?"

---

## Rollout Plan

### Phase 1: Alpha (v1.1.0-alpha)
- Core tables and functions
- Basic validation
- Limited documentation
- Gather early feedback

### Phase 2: Beta (v1.1.0-beta)
- Performance optimization
- Full test coverage
- Complete documentation
- Migration guide

### Phase 3: GA (v1.1.0)
- Production ready
- Performance benchmarks met
- All documentation complete
- Adoption examples published

---

## Success Metrics

- **Adoption:** 30% of users migrate at least one rule to repository within 3 months
- **Performance:** All functions meet benchmark targets
- **Stability:** < 5 bugs reported in first month
- **Community:** Positive feedback, feature requests for rule sets (Phase 2)

---

## Open Questions

- [ ] Should we support rule branching (dev/staging/prod)?
- [ ] Auto-cleanup policy for old versions?
- [ ] Import/export functionality for rule migration?
- [ ] Support for rule namespaces (multi-tenancy)?

---

## References

- [Semantic Versioning](https://semver.org/)
- [PostgreSQL Versioning Best Practices](https://wiki.postgresql.org/wiki/Version_Control)
- [Drools Rule Repository](https://docs.drools.org/)

---

## Changelog

- **2025-12-06:** Initial draft
