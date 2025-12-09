# Phase 2: Developer Experience (v1.4.0)

**Status:** ✅ Complete
**Released:** December 9, 2025

## Overview

Phase 2 introduces a comprehensive suite of developer tools to make rule development faster, more reliable, and easier to maintain. This release adds testing frameworks, validation tools, debugging capabilities, and reusable templates.

## Features

### 2.1 Rule Testing Framework ✅

A complete testing framework for creating, running, and tracking tests for your rules.

#### Tables

- **`rule_test_cases`** - Stores test definitions
- **`rule_test_results`** - Stores test execution results
- **`rule_test_coverage`** - Tracks test coverage per rule

#### Functions

##### `rule_test_create()`
Creates a new test case for a rule.

```sql
rule_test_create(
    p_test_name TEXT,
    p_rule_name TEXT,
    p_input_facts JSONB,
    p_expected_output JSONB DEFAULT NULL,
    p_rule_version TEXT DEFAULT 'latest',
    p_description TEXT DEFAULT NULL,
    p_assertions JSONB DEFAULT NULL
) RETURNS INTEGER
```

**Example:**
```sql
-- Simple output comparison
SELECT rule_test_create(
    'test_discount_gold_tier',
    'discount_rules',
    '{"customer": {"tier": "gold", "total_spent": 5000}}'::JSONB,
    '{"customer": {"tier": "gold", "total_spent": 5000, "discount": 0.15}}'::JSONB,
    'latest',
    'Test gold tier discount application'
);

-- With assertions
SELECT rule_test_create(
    'test_with_assertions',
    'pricing_rule',
    '{"price": 100, "quantity": 5}'::JSONB,
    NULL,
    'latest',
    'Test with multiple assertions',
    '[
        {"type": "equals", "path": "total", "value": 500},
        {"type": "greater_than", "path": "discount", "value": 0},
        {"type": "exists", "path": "final_price"}
    ]'::JSONB
);
```

**Assertion Types:**
- `equals` - Exact match
- `not_equals` - Not equal
- `exists` - Field exists
- `not_exists` - Field doesn't exist
- `contains` - Contains value
- `greater_than` - Greater than
- `less_than` - Less than

##### `rule_test_run()`
Runs a single test case by ID.

```sql
rule_test_run(p_test_id INTEGER) RETURNS JSON
```

**Example:**
```sql
SELECT rule_test_run(1);

-- Returns:
-- {
--   "test_id": 1,
--   "test_name": "test_discount_gold_tier",
--   "passed": true,
--   "execution_time_ms": 1.234,
--   "actual_output": {...},
--   "expected_output": {...},
--   "error_message": null,
--   "assertion_results": {...}
-- }
```

##### `rule_test_run_all()`
Runs all tests for a specific rule or all rules.

```sql
rule_test_run_all(p_rule_name TEXT DEFAULT NULL)
RETURNS TABLE (
    test_id INTEGER,
    test_name TEXT,
    rule_name TEXT,
    passed BOOLEAN,
    execution_time_ms NUMERIC,
    error_message TEXT
)
```

**Example:**
```sql
-- Run all tests
SELECT * FROM rule_test_run_all();

-- Run tests for specific rule
SELECT * FROM rule_test_run_all('discount_rules');
```

##### `rule_test_coverage()`
Returns test coverage statistics for a rule.

```sql
rule_test_coverage(p_rule_name TEXT) RETURNS JSON
```

**Example:**
```sql
SELECT rule_test_coverage('discount_rules');

-- Returns:
-- {
--   "rule_name": "discount_rules",
--   "total_tests": 5,
--   "passing_tests": 4,
--   "failing_tests": 1,
--   "coverage_score": 80.0,
--   "last_test_run": "2025-12-09T10:30:00Z"
-- }
```

#### Views

##### `test_suite_summary`
Overview of all test suites.

```sql
SELECT * FROM test_suite_summary;

-- Returns:
--  rule_name      | total_tests | enabled_tests | passing_tests | last_run            | avg_execution_time_ms
-- ----------------+-------------+---------------+---------------+---------------------+-----------------------
--  discount_rules |           5 |             5 |             4 | 2025-12-09 10:30:00 |                  1.23
--  pricing_rule   |           3 |             3 |             3 | 2025-12-09 09:15:00 |                  0.89
```

##### `recent_test_failures`
Shows recent test failures for debugging.

```sql
SELECT * FROM recent_test_failures LIMIT 10;
```

---

### 2.2 Rule Validation & Linting ✅

Validate GRL syntax and check for best practices before saving rules.

#### Functions

##### `rule_validate()`
Validates GRL syntax and basic structure.

```sql
rule_validate(p_grl TEXT) RETURNS JSON
```

**Example:**
```sql
SELECT rule_validate('
    rule MyRule "A simple rule" salience 10 {
        when
            customer.age > 18
        then
            customer.is_adult = true;
            Retract("MyRule");
    }
');

-- Returns:
-- {
--   "valid": true,
--   "errors": [],
--   "warnings": [],
--   "error_count": 0,
--   "warning_count": 0
-- }
```

**Validation Checks:**
- ✓ Syntax compilation
- ✓ Non-empty rule
- ✓ Basic GRL structure
- ✓ Complex condition warnings
- ✓ Deep nesting warnings

##### `rule_lint()`
Performs detailed linting with best practices check.

```sql
rule_lint(
    p_grl TEXT,
    p_strict_mode BOOLEAN DEFAULT false
) RETURNS JSON
```

**Example:**
```sql
SELECT rule_lint('
    rule ComplexRule "Complex rule" {
        when
            a > 1 && b > 2 && c > 3 && d > 4 && e > 5 && f > 6
        then
            result = true;
    }
', false);

-- Returns:
-- {
--   "passed": false,
--   "issue_count": 2,
--   "issues": [
--     {
--       "type": "warning",
--       "category": "performance",
--       "message": "Complex condition: More than 5 AND operators may impact performance"
--     },
--     {
--       "type": "info",
--       "category": "best_practice",
--       "message": "Consider adding salience for rule prioritization"
--     }
--   ],
--   "validation": {...}
-- }
```

**Linting Checks:**
- Syntax validation
- Unused variable detection
- Line length (strict mode)
- TODO/FIXME comments
- Best practices recommendations
- Performance warnings

---

### 2.3 Rule Debugging Tools ✅

Debug rule execution with step-by-step tracing and variable inspection.

#### Tables

- **`rule_debug_traces`** - Stores execution traces

#### Functions

##### `rule_debug_execute()`
Executes rules with detailed step-by-step tracing.

```sql
rule_debug_execute(
    p_facts JSONB,
    p_rules TEXT,
    p_session_id TEXT DEFAULT NULL
) RETURNS JSON
```

**Example:**
```sql
SELECT rule_debug_execute(
    '{"customer": {"age": 25, "country": "US"}}'::JSONB,
    'rule AgeCheck "Check age" salience 10 {
        when
            customer.age >= 21
        then
            customer.can_drink = true;
            Retract("AgeCheck");
    }',
    'debug_session_001'
);

-- Returns:
-- {
--   "session_id": "debug_session_001",
--   "result": {...},
--   "trace_count": 5,
--   "message": "Debug session completed. Use rule_trace_get() to retrieve detailed trace."
-- }
```

##### `rule_trace_get()`
Retrieves execution trace for a debug session.

```sql
rule_trace_get(p_session_id TEXT)
RETURNS TABLE (
    step_number INTEGER,
    step_type TEXT,
    description TEXT,
    before_facts JSONB,
    after_facts JSONB,
    traced_at TIMESTAMPTZ
)
```

**Example:**
```sql
SELECT * FROM rule_trace_get('debug_session_001');

-- Returns step-by-step execution trace:
--  step_number | step_type  | description               | before_facts | after_facts | traced_at
-- -------------+------------+---------------------------+--------------+-------------+------------------------
--            1 | execution  | Rule execution completed  | {...}        | {...}       | 2025-12-09 10:30:00.123
```

---

### 2.4 Rule Templates ✅

Create and reuse rule templates with parameter substitution.

#### Tables

- **`rule_templates`** - Stores template definitions
- **`rule_template_instances`** - Tracks created instances

#### Functions

##### `rule_template_create()`
Creates a new rule template.

```sql
rule_template_create(
    p_template_name TEXT,
    p_grl_template TEXT,
    p_parameters JSONB,
    p_description TEXT DEFAULT NULL,
    p_category TEXT DEFAULT NULL
) RETURNS INTEGER
```

**Example:**
```sql
SELECT rule_template_create(
    'threshold_check',
    'rule ThresholdCheck_{{name}} "Check if {{field}} exceeds {{threshold}}" salience 10 {
        when
            {{field}} > {{threshold}}
        then
            Result.triggered = true;
            Result.message = "{{field}} exceeded threshold of {{threshold}}";
            Retract("ThresholdCheck_{{name}}");
    }',
    '[
        {"name": "name", "type": "string", "description": "Rule instance name"},
        {"name": "field", "type": "string", "description": "Field path to check"},
        {"name": "threshold", "type": "number", "description": "Threshold value"}
    ]'::JSONB,
    'Checks if a numeric value exceeds a threshold',
    'validation'
);
```

**Parameter Format:**
```json
[
    {
        "name": "param_name",
        "type": "string|number|boolean",
        "description": "Parameter description",
        "default": "optional_default_value"
    }
]
```

##### `rule_template_instantiate()`
Creates a rule instance from a template.

```sql
rule_template_instantiate(
    p_template_id INTEGER,
    p_parameter_values JSONB,
    p_rule_name TEXT DEFAULT NULL
) RETURNS TEXT
```

**Example:**
```sql
SELECT rule_template_instantiate(
    1,  -- template_id
    '{"name": "temp_alert", "field": "temperature", "threshold": "100"}'::JSONB,
    'temperature_alert_rule'
);

-- Returns the instantiated GRL:
-- rule ThresholdCheck_temp_alert "Check if temperature exceeds 100" salience 10 {
--     when
--         temperature > 100
--     then
--         Result.triggered = true;
--         Result.message = "temperature exceeded threshold of 100";
--         Retract("ThresholdCheck_temp_alert");
-- }
```

##### `rule_template_list()`
Lists all available templates.

```sql
rule_template_list(p_category TEXT DEFAULT NULL)
RETURNS TABLE (
    template_id INTEGER,
    template_name TEXT,
    description TEXT,
    category TEXT,
    parameters JSONB,
    usage_count INTEGER,
    created_at TIMESTAMPTZ
)
```

**Example:**
```sql
-- List all templates
SELECT * FROM rule_template_list();

-- List by category
SELECT * FROM rule_template_list('validation');
SELECT * FROM rule_template_list('pricing');
```

##### `rule_template_get()`
Gets a specific template by ID or name.

```sql
rule_template_get(p_identifier TEXT) RETURNS JSON
```

**Example:**
```sql
-- By name
SELECT rule_template_get('threshold_check');

-- By ID
SELECT rule_template_get('1');
```

#### Views

##### `template_usage_stats`
Template popularity and usage statistics.

```sql
SELECT * FROM template_usage_stats;

-- Returns:
--  template_name    | category       | usage_count | total_instances | last_used           | created_at
-- ------------------+----------------+-------------+-----------------+---------------------+------------------------
--  threshold_check  | validation     |          25 |              25 | 2025-12-09 10:30:00 | 2025-12-09 08:00:00
--  tier_assignment  | classification |          12 |              12 | 2025-12-09 09:15:00 | 2025-12-09 08:00:00
```

#### Built-in Templates

Phase 2 includes 3 pre-built templates:

1. **`threshold_check`** (validation)
   - Checks if a numeric value exceeds a threshold
   - Parameters: `field`, `threshold`

2. **`tier_assignment`** (classification)
   - Assigns tier based on value ranges
   - Parameters: `metric`, `tier1_min`, `tier2_min`, `tier1_name`

3. **`discount_rule`** (pricing)
   - Applies discount based on conditions
   - Parameters: `condition`, `discount_pct`

---

## Integration Example

Complete workflow demonstrating all Phase 2 features:

```sql
-- Step 1: Create a rule from template
SELECT rule_template_instantiate(
    (SELECT template_id FROM rule_templates WHERE template_name = 'discount_rule'),
    '{"condition": "customer.loyalty_years > 5", "discount_pct": "20"}'::JSONB,
    'loyalty_discount_rule'
);

-- Step 2: Validate the rule
SELECT rule_validate('rule LoyaltyDiscount "Apply 20% discount when customer.loyalty_years > 5" ...');

-- Step 3: Lint the rule
SELECT rule_lint('rule LoyaltyDiscount ...', false);

-- Step 4: Create test cases
SELECT rule_test_create(
    'test_loyalty_5_years',
    'loyalty_discount_rule',
    '{"customer": {"loyalty_years": 6}}'::JSONB,
    '{"customer": {"loyalty_years": 6}, "Result": {"discount": 20}}'::JSONB
);

-- Step 5: Run tests
SELECT * FROM rule_test_run_all('loyalty_discount_rule');

-- Step 6: Check coverage
SELECT * FROM test_suite_summary WHERE rule_name = 'loyalty_discount_rule';

-- Step 7: Debug if needed
SELECT rule_debug_execute(
    '{"customer": {"loyalty_years": 6}}'::JSONB,
    'rule LoyaltyDiscount ...',
    'debug_loyalty'
);

SELECT * FROM rule_trace_get('debug_loyalty');
```

---

## Performance Metrics

Based on Phase 2 test suite:

| Operation | Average Time | Notes |
|-----------|--------------|-------|
| Rule Validation | ~0.034 ms | 100 validations in 3.38ms |
| Template Instantiation | ~0.153 ms | 50 instantiations in 7.67ms |
| Test Execution | ~1-5 ms | Depends on rule complexity |
| Debug Trace Creation | <1 ms | Minimal overhead |

---

## Migration

To apply Phase 2 to your database:

```bash
# Apply main migration
psql -d your_database -f migrations/004_developer_experience.sql

# Apply fixes (if needed)
psql -d your_database -f migrations/004_fix.sql

# Run tests
psql -d your_database -f tests/test_phase2_developer_experience.sql
```

See [PHASE2_INSTALLATION.md](../PHASE2_INSTALLATION.md) for detailed installation instructions.

---

## Database Schema

### New Tables (6)

1. `rule_test_cases` - Test definitions
2. `rule_test_results` - Test execution history
3. `rule_test_coverage` - Coverage tracking
4. `rule_debug_traces` - Debug execution traces
5. `rule_templates` - Template definitions
6. `rule_template_instances` - Template instance tracking

### New Views (3)

1. `test_suite_summary` - Test suite overview
2. `recent_test_failures` - Recent failures for debugging
3. `template_usage_stats` - Template usage analytics

### New Functions (12)

**Testing (4):**
- `rule_test_create()`
- `rule_test_run()`
- `rule_test_run_all()`
- `rule_test_coverage()`

**Validation (2):**
- `rule_validate()`
- `rule_lint()`

**Debugging (2):**
- `rule_debug_execute()`
- `rule_trace_get()`

**Templates (4):**
- `rule_template_create()`
- `rule_template_instantiate()`
- `rule_template_list()`
- `rule_template_get()`

---

## Best Practices

### Testing

1. **Create tests for every rule** - Aim for 100% coverage
2. **Use assertions** - More flexible than output comparison
3. **Test edge cases** - Boundary conditions, empty inputs, nulls
4. **Run tests before deployment** - Catch regressions early

### Validation

1. **Validate before saving** - Catch syntax errors immediately
2. **Lint in CI/CD** - Enforce code quality standards
3. **Address warnings** - Performance and maintainability issues
4. **Use strict mode** - For production-quality code

### Debugging

1. **Use debug sessions** - For complex rule interactions
2. **Name sessions clearly** - Easy to identify later
3. **Review traces** - Understand execution flow
4. **Clean up old traces** - Prevent table bloat

### Templates

1. **Document parameters** - Clear descriptions and types
2. **Provide defaults** - When sensible
3. **Categorize templates** - Easy discovery
4. **Version templates** - Track changes over time

---

## Troubleshooting

### Test Execution Fails

**Issue:** `function run_rule_engine(jsonb, text) does not exist`

**Solution:** Ensure the Rust extension is installed:
```sql
CREATE EXTENSION IF NOT EXISTS rule_engine;
```

### Validation Always Fails

**Issue:** Rules fail validation even when syntax looks correct

**Solution:** The validation function tries to compile rules. Ensure:
- Extension is loaded
- GRL syntax is valid
- No missing semicolons or braces

### Template Instantiation Error

**Issue:** `Required parameter not provided`

**Solution:** Check template parameters:
```sql
SELECT parameters FROM rule_templates WHERE template_name = 'your_template';
```

Ensure all required parameters (without defaults) are provided.

---

## Next Steps

With Phase 2 complete, you can now:

1. ✅ Write comprehensive test suites for all rules
2. ✅ Validate rules before deployment
3. ✅ Debug complex rule interactions
4. ✅ Create reusable rule templates
5. 🚀 Move to Phase 3: Advanced Features (Temporal Rules, Caching, A/B Testing)

---

## API Reference

For complete API documentation, see:
- Testing: [`rule_test_*` functions](#21-rule-testing-framework-)
- Validation: [`rule_validate`, `rule_lint`](#22-rule-validation--linting-)
- Debugging: [`rule_debug_*` functions](#23-rule-debugging-tools-)
- Templates: [`rule_template_*` functions](#24-rule-templates-)

---

## Changelog

**v1.4.0 - December 9, 2025**
- ✅ Rule Testing Framework (2.1)
- ✅ Rule Validation & Linting (2.2)
- ✅ Rule Debugging Tools (2.3)
- ✅ Rule Templates (2.4)
- ✅ 6 new tables, 3 views, 12 functions
- ✅ 3 built-in templates
- ✅ Comprehensive test suite

---

**Questions or Issues?**

- 📖 [ROADMAP](ROADMAP.md) - Future plans
- 🐛 [GitHub Issues](https://github.com/yourusername/rule-engine-postgre-extensions/issues)
- 📝 [README](../README.md) - Getting started
