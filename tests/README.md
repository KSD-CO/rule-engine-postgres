# Test Suite for Rule Engine PostgreSQL Extension

## Overview
Comprehensive test suite covering real-world use cases and edge cases for the rule engine extension.

## Test Categories

### 1. Integration Tests (Rust)
**File**: `tests/integration_tests.rs`

Run with:
```bash
cargo test
```

Tests include:
- E-commerce pricing rules
- Banking loan approval
- SaaS billing tiers
- Healthcare patient risk assessment
- Error handling (empty inputs, invalid JSON/GRL)
- Nested objects
- Rule execution order (salience)
- Health check and version

### 2. SQL Tests (PostgreSQL)
**File**: `tests/test_case_studies.sql`

Run with:
```bash
# Start PostgreSQL with extension loaded
cargo pgrx run pg17

# In psql session:
\i tests/test_case_studies.sql
```

Or directly:
```bash
psql -d test_db -f tests/test_case_studies.sql
```

Tests include:
- All integration test scenarios
- Performance measurements
- Complex discount stacking
- Real-world case studies from README

### 3. Test Fixtures
**Directory**: `tests/fixtures/`

JSON and GRL files for each use case:
- `ecommerce_pricing.json` / `ecommerce_pricing.grl`
- `loan_approval.json` / `loan_approval.grl`
- `billing_tiers.json` / `billing_tiers.grl`
- `patient_risk.json` / `patient_risk.grl`

## Running Tests

### Prerequisites
```bash
# Install cargo-pgrx
cargo install cargo-pgrx --version 0.16.1 --locked

# Initialize pgrx
cargo pgrx init

# Or initialize with specific PostgreSQL
cargo pgrx init --pg17 /path/to/pg_config
```

### Run All Tests
```bash
# Rust integration tests
cargo test

# PostgreSQL tests (requires running PostgreSQL instance)
cargo pgrx run pg17
# Then in psql:
# \i tests/test_case_studies.sql
```

### Run Specific Tests
```bash
# Run single test
cargo test test_ecommerce_pricing_rules

# Run tests matching pattern
cargo test loan_approval

# Run with output
cargo test -- --nocapture
```

## Expected Results

### Test 3: E-Commerce Pricing
```json
{
  "Order": {
    "discount": 0.20  // 20% from LoyaltyBonus (highest salience)
  },
  "Product": {
    "discount": 0.25  // 25% from FlashSale
  }
}
```

### Test 4: Loan Approval
```json
{
  "Applicant": {
    "approved": true,
    "maxAmount": 225000,  // income * 3
    "interestRate": 3.5
  }
}
```

### Test 5: SaaS Billing
```json
{
  "Usage": {
    "tier": "pro",
    "baseCharge": 99,
    "overageCharge": 27.5  // (75-50)*0.1 + (15-10)*5
  }
}
```

### Test 6: Patient Risk
```json
{
  "Patient": {
    "riskScore": 90,     // 15+20+25+30
    "riskLevel": "high"  // >= 60
  }
}
```

## Performance Benchmarks

Expected performance on modern hardware:
- Simple rule (1 condition): < 1ms
- Complex rule (5+ conditions): < 3ms
- Multiple rules (10 rules): < 5ms
- Nested objects (3 levels): < 2ms

## Error Code Testing

All error codes should be tested:
- **ERR001**: Empty facts JSON
- **ERR002**: Empty rules GRL
- **ERR003**: Facts too large (>1MB)
- **ERR004**: Rules too large (>1MB)
- **ERR005**: Invalid JSON syntax
- **ERR006**: Non-object JSON
- **ERR007**: Fact add failed
- **ERR008**: Invalid GRL syntax
- **ERR009**: No rules found
- **ERR010**: Rule add failed
- **ERR011**: Execution failed
- **ERR012**: Serialization failed

## Adding New Tests

### 1. Create Test Fixtures
```bash
# Add JSON facts
cat > tests/fixtures/my_test.json <<EOF
{
  "MyObject": {
    "field": "value"
  }
}
EOF

# Add GRL rules
cat > tests/fixtures/my_test.grl <<EOF
rule "MyRule" salience 10 {
    when
        MyObject.field == "value"
    then
        MyObject.result = "success";
}
EOF
```

### 2. Add Integration Test
```rust
#[test]
fn test_my_feature() {
    let facts = fs::read_to_string("tests/fixtures/my_test.json")
        .expect("Failed to read my_test.json");
    let rules = fs::read_to_string("tests/fixtures/my_test.grl")
        .expect("Failed to read my_test.grl");

    let result_json = run_rule_engine(&facts, &rules);
    let result: serde_json::Value = serde_json::from_str(&result_json)
        .expect("Failed to parse result");

    assert_eq!(result["MyObject"]["result"], "success");
}
```

### 3. Add SQL Test
```sql
\echo 'Test: My Feature'
SELECT run_rule_engine(
    '{"MyObject": {"field": "value"}}',
    'rule "MyRule" { when MyObject.field == "value" then MyObject.result = "success"; }'
)::jsonb AS my_test_result;
```

## CI/CD Integration

### GitHub Actions
```yaml
- name: Run tests
  run: |
    cargo test --all-features
    cargo pgrx test pg17
```

### Docker
```bash
docker-compose up -d postgres
docker-compose exec postgres psql -U postgres -d test_db -f /tests/test_case_studies.sql
```

## Troubleshooting

### Tests fail to compile
```bash
cargo clean
cargo build
```

### PostgreSQL connection errors
```bash
# Check if PostgreSQL is running
cargo pgrx status

# Restart PostgreSQL
cargo pgrx stop
cargo pgrx start pg17
```

### Fixture files not found
```bash
# Ensure you're in project root
cd /path/to/rule-engine-postgres
cargo test
```

## Coverage

Generate test coverage report:
```bash
cargo install cargo-tarpaulin
cargo tarpaulin --out Html --output-dir coverage
```

Target: >80% code coverage

## Contributing

When adding new features:
1. ✅ Add test fixtures
2. ✅ Add integration tests
3. ✅ Add SQL tests
4. ✅ Update this README
5. ✅ Ensure all tests pass

---

**Last Updated**: 2025-12-03
**Test Count**: 14 integration tests + 14 SQL tests
**Coverage**: Target 80%+
