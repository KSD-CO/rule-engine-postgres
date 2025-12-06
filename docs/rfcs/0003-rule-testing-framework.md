# RFC-0003: Rule Testing Framework

- **Status:** Draft
- **Author:** Rule Engine Team
- **Created:** 2025-12-06
- **Updated:** 2025-12-06
- **Phase:** 2.1 (Developer Experience)
- **Priority:** P0 - Critical

---

## Summary

Implement a comprehensive testing framework for GRL rules, enabling developers to write, run, and maintain automated tests for their business logic directly within PostgreSQL.

---

## Motivation

Currently, testing rules requires:
- Manual execution with sample data
- External test frameworks
- No regression testing capability
- Difficult to validate rule changes
- No CI/CD integration

### Use Cases

1. **Regression Testing:** Ensure rule changes don't break existing behavior
2. **TDD for Rules:** Write tests before implementing rules
3. **Continuous Integration:** Automated test runs in CI/CD
4. **Documentation:** Tests serve as executable examples
5. **Refactoring Safety:** Confident refactoring with test coverage

---

## Detailed Design

### Database Schema

```sql
-- Test case definitions
CREATE TABLE rule_test_cases (
    id SERIAL PRIMARY KEY,
    test_name TEXT NOT NULL UNIQUE,
    rule_name TEXT NOT NULL, -- Can reference rule_definitions
    rule_version TEXT,
    
    -- Test definition
    description TEXT,
    input_facts JSONB NOT NULL,
    expected_output JSONB,
    expected_error TEXT, -- For negative tests
    
    -- Test configuration
    test_type TEXT NOT NULL DEFAULT 'equality', -- equality, contains, custom
    timeout_ms INTEGER DEFAULT 5000,
    tags TEXT[], -- For grouping tests
    
    -- Metadata
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_by TEXT,
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    is_active BOOLEAN NOT NULL DEFAULT true,
    
    CONSTRAINT valid_test_type CHECK (test_type IN ('equality', 'contains', 'custom', 'error'))
);

CREATE INDEX idx_test_cases_rule ON rule_test_cases(rule_name);
CREATE INDEX idx_test_cases_tags ON rule_test_cases USING GIN(tags);
CREATE INDEX idx_test_cases_active ON rule_test_cases(is_active);

-- Test execution results
CREATE TABLE rule_test_results (
    id BIGSERIAL PRIMARY KEY,
    test_case_id INTEGER NOT NULL REFERENCES rule_test_cases(id) ON DELETE CASCADE,
    
    -- Execution details
    executed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    passed BOOLEAN NOT NULL,
    duration_ms NUMERIC(10, 2) NOT NULL,
    
    -- Results
    actual_output JSONB,
    actual_error TEXT,
    assertion_details TEXT,
    
    -- Context
    rule_version_tested TEXT,
    execution_id UUID DEFAULT gen_random_uuid(),
    
    -- CI/CD integration
    ci_run_id TEXT,
    git_commit TEXT
);

CREATE INDEX idx_test_results_case ON rule_test_results(test_case_id);
CREATE INDEX idx_test_results_time ON rule_test_results(executed_at);
CREATE INDEX idx_test_results_ci ON rule_test_results(ci_run_id) WHERE ci_run_id IS NOT NULL;

-- Test suites (collections of tests)
CREATE TABLE rule_test_suites (
    id SERIAL PRIMARY KEY,
    suite_name TEXT NOT NULL UNIQUE,
    description TEXT,
    tags TEXT[],
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE rule_test_suite_members (
    suite_id INTEGER NOT NULL REFERENCES rule_test_suites(id) ON DELETE CASCADE,
    test_case_id INTEGER NOT NULL REFERENCES rule_test_cases(id) ON DELETE CASCADE,
    test_order INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (suite_id, test_case_id)
);

-- Test coverage tracking
CREATE VIEW rule_test_coverage AS
SELECT 
    rd.name as rule_name,
    rd.description,
    COUNT(DISTINCT rtc.id) as test_count,
    COUNT(DISTINCT rtc.id) FILTER (WHERE rtc.is_active) as active_test_count,
    MAX(rtr.executed_at) as last_tested,
    ROUND(100.0 * COUNT(rtr.id) FILTER (WHERE rtr.passed) / 
          NULLIF(COUNT(rtr.id), 0), 2) as pass_rate
FROM rule_definitions rd
LEFT JOIN rule_test_cases rtc ON rtc.rule_name = rd.name
LEFT JOIN rule_test_results rtr ON rtr.test_case_id = rtc.id
    AND rtr.executed_at > NOW() - INTERVAL '30 days'
GROUP BY rd.id, rd.name, rd.description;
```

### API Functions

#### Function 1: `rule_test_create(test_name TEXT, rule_name TEXT, input_facts JSONB, expected_output JSONB, description TEXT DEFAULT NULL) → INTEGER`

**Purpose:** Create a new test case

**Example:**
```sql
SELECT rule_test_create(
    'discount_over_100',
    'discount_calculator',
    '{"Order": {"Amount": 150}}',
    '{"Order": {"Amount": 150, "Discount": 15}}',
    'Test discount applied for orders over $100'
);
```

#### Function 2: `rule_test_run(test_id INTEGER) → JSON`

**Purpose:** Run a single test case

**Example:**
```sql
SELECT rule_test_run(1);

-- Returns:
{
  "test_id": 1,
  "test_name": "discount_over_100",
  "passed": true,
  "duration_ms": 1.23,
  "details": {
    "expected": {"Order": {"Amount": 150, "Discount": 15}},
    "actual": {"Order": {"Amount": 150, "Discount": 15}},
    "assertion": "Output matches expected"
  }
}
```

#### Function 3: `rule_test_run_all(rule_name TEXT DEFAULT NULL, tag TEXT DEFAULT NULL) → TABLE`

**Purpose:** Run all tests for a rule or tag

**Example:**
```sql
-- Run all tests for a rule
SELECT * FROM rule_test_run_all('discount_calculator');

-- Run all tests with a tag
SELECT * FROM rule_test_run_all(NULL, 'smoke_test');

-- Returns:
 test_name         | passed | duration_ms | error_message
-------------------+--------+-------------+--------------
 discount_over_100 | t      | 1.23        |
 discount_under_50 | t      | 0.98        |
 discount_negative | f      | 1.45        | Expected discount=0, got discount=-5
```

#### Function 4: `rule_test_suite_create(suite_name TEXT, test_ids INTEGER[]) → INTEGER`

**Purpose:** Create a test suite from multiple tests

**Example:**
```sql
SELECT rule_test_suite_create(
    'discount_smoke_tests',
    ARRAY[1, 2, 3, 4]
);
```

#### Function 5: `rule_test_suite_run(suite_name TEXT) → JSON`

**Purpose:** Run an entire test suite

**Example:**
```sql
SELECT rule_test_suite_run('discount_smoke_tests');

-- Returns:
{
  "suite_name": "discount_smoke_tests",
  "total_tests": 4,
  "passed": 3,
  "failed": 1,
  "duration_ms": 5.67,
  "pass_rate": 75.0,
  "failures": [
    {
      "test_name": "discount_negative",
      "error": "Expected discount=0, got discount=-5"
    }
  ]
}
```

#### Function 6: `rule_test_coverage(rule_name TEXT DEFAULT NULL) → JSON`

**Purpose:** Get test coverage report

**Example:**
```sql
SELECT rule_test_coverage('discount_calculator');

-- Returns:
{
  "rule_name": "discount_calculator",
  "test_count": 8,
  "active_tests": 7,
  "last_run": "2025-12-06T10:30:00Z",
  "pass_rate": 87.5,
  "uncovered_scenarios": [
    "Order amount = 0",
    "Order amount negative"
  ],
  "recommendation": "Add edge case tests"
}
```

#### Function 7: `rule_test_assert_contains(actual JSONB, expected_subset JSONB) → BOOLEAN`

**Purpose:** Assertion helper for partial matches

**Example:**
```sql
-- Test passes if actual contains all keys from expected
SELECT rule_test_assert_contains(
    '{"Order": {"Amount": 150, "Discount": 15, "Tax": 10}}',
    '{"Order": {"Discount": 15}}'
); -- Returns: true
```

#### Function 8: `rule_test_delete(test_name TEXT) → BOOLEAN`

**Purpose:** Delete a test case

#### Function 9: `rule_test_history(test_name TEXT, limit INTEGER DEFAULT 10) → TABLE`

**Purpose:** Get execution history for a test

---

## Internal Implementation

```rust
// src/testing/framework.rs
use serde_json::Value;

pub struct TestCase {
    pub id: i32,
    pub test_name: String,
    pub rule_name: String,
    pub input_facts: Value,
    pub expected_output: Option<Value>,
    pub expected_error: Option<String>,
    pub test_type: TestType,
}

pub enum TestType {
    Equality,
    Contains,
    Custom,
    Error,
}

pub struct TestResult {
    pub passed: bool,
    pub duration_ms: f64,
    pub actual_output: Option<Value>,
    pub actual_error: Option<String>,
    pub assertion_details: String,
}

#[pg_extern]
pub fn rule_test_run(test_id: i32) -> Result<String, RuleEngineError> {
    // 1. Load test case
    let test_case = load_test_case(test_id)?;
    
    // 2. Get rule GRL
    let grl = rule_get(&test_case.rule_name, None)?;
    
    // 3. Execute rule with timing
    let start = Instant::now();
    let execution_result = run_rule_engine_impl(
        &test_case.input_facts.to_string(),
        &grl,
    );
    let duration_ms = start.elapsed().as_secs_f64() * 1000.0;
    
    // 4. Evaluate assertions
    let test_result = match test_case.test_type {
        TestType::Equality => {
            evaluate_equality(execution_result, &test_case.expected_output)
        }
        TestType::Contains => {
            evaluate_contains(execution_result, &test_case.expected_output)
        }
        TestType::Error => {
            evaluate_error(execution_result, &test_case.expected_error)
        }
        TestType::Custom => {
            evaluate_custom(execution_result, &test_case)
        }
    };
    
    // 5. Record result
    record_test_result(test_id, &test_result)?;
    
    // 6. Return formatted result
    Ok(serde_json::to_string(&test_result)?)
}

fn evaluate_equality(
    actual: Result<String, RuleEngineError>,
    expected: &Option<Value>,
) -> TestResult {
    match (actual, expected) {
        (Ok(actual_str), Some(expected_val)) => {
            let actual_val: Value = serde_json::from_str(&actual_str).unwrap();
            let passed = actual_val == *expected_val;
            
            TestResult {
                passed,
                actual_output: Some(actual_val),
                assertion_details: if passed {
                    "Output matches expected".to_string()
                } else {
                    format!("Expected: {}, Actual: {}", expected_val, actual_str)
                },
                ..Default::default()
            }
        }
        (Err(e), None) => {
            TestResult {
                passed: false,
                actual_error: Some(e.to_string()),
                assertion_details: "Unexpected error".to_string(),
                ..Default::default()
            }
        }
        _ => TestResult::default(),
    }
}

// Run all tests for a rule
#[pg_extern]
pub fn rule_test_run_all(
    rule_name: Option<String>,
    tag: Option<String>,
) -> Result<Vec<(String, bool, f64, Option<String>)>, RuleEngineError> {
    let test_cases = load_test_cases(rule_name, tag)?;
    let mut results = Vec::new();
    
    for test_case in test_cases {
        let result = rule_test_run(test_case.id)?;
        let result_json: TestResult = serde_json::from_str(&result)?;
        
        results.push((
            test_case.test_name,
            result_json.passed,
            result_json.duration_ms,
            result_json.actual_error,
        ));
    }
    
    Ok(results)
}
```

---

## Examples

### Example 1: TDD Workflow

```sql
-- Step 1: Write failing test first
SELECT rule_test_create(
    'adult_age_check',
    'age_verification',
    '{"User": {"Age": 20}}',
    '{"User": {"Age": 20, "IsAdult": true}}',
    'User over 18 should be marked as adult'
);

-- Step 2: Run test (should fail - rule doesn't exist yet)
SELECT rule_test_run(1);
-- Returns: {"passed": false, "error": "Rule not found"}

-- Step 3: Implement rule
SELECT rule_save(
    'age_verification',
    'rule "AgeCheck" { when User.Age >= 18 then User.IsAdult = true; }',
    '1.0.0'
);

-- Step 4: Run test (should pass now)
SELECT rule_test_run(1);
-- Returns: {"passed": true, "duration_ms": 1.2}
```

### Example 2: Regression Testing

```sql
-- Create comprehensive test suite
SELECT rule_test_create('adult_18', 'age_verification', '{"User": {"Age": 18}}', '{"User": {"Age": 18, "IsAdult": true}}');
SELECT rule_test_create('adult_21', 'age_verification', '{"User": {"Age": 21}}', '{"User": {"Age": 21, "IsAdult": true}}');
SELECT rule_test_create('minor_17', 'age_verification', '{"User": {"Age": 17}}', '{"User": {"Age": 17, "IsAdult": null}}');
SELECT rule_test_create('minor_0', 'age_verification', '{"User": {"Age": 0}}', '{"User": {"Age": 0, "IsAdult": null}}');

-- Run all tests before making changes
SELECT * FROM rule_test_run_all('age_verification');

-- Make rule changes
SELECT rule_save('age_verification', 'rule "AgeCheck" { ... }', '2.0.0');

-- Run regression tests
SELECT * FROM rule_test_run_all('age_verification');
```

### Example 3: CI/CD Integration

```sql
-- In CI/CD pipeline
BEGIN;

-- Run all tests with tag 'smoke'
SELECT rule_test_suite_run('smoke_tests');

-- Check results
SELECT 
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE passed) as passed,
    COUNT(*) FILTER (WHERE NOT passed) as failed
FROM rule_test_results
WHERE ci_run_id = 'build-12345';

-- Rollback if tests failed
DO $$
DECLARE
    fail_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO fail_count
    FROM rule_test_results
    WHERE ci_run_id = 'build-12345' AND NOT passed;
    
    IF fail_count > 0 THEN
        RAISE EXCEPTION 'Tests failed: % failures', fail_count;
    END IF;
END $$;

COMMIT;
```

---

## Success Metrics

- **Adoption:** 60% of rules have at least 1 test within 6 months
- **Coverage:** Average 3+ tests per rule
- **CI Integration:** 40% of production deployments run tests in CI
- **Reliability:** Catch 80% of regressions before production

---

## Changelog

- **2025-12-06:** Initial draft
