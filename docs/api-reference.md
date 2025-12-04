# API Reference

Complete reference for all PostgreSQL Rule Engine functions.

## Table of Contents

- [Forward Chaining](#forward-chaining-functions)
- [Backward Chaining](#backward-chaining-functions)
- [Utility Functions](#utility-functions)
- [Error Codes](#error-codes)
- [GRL Syntax](#grl-syntax-reference)

---

## Forward Chaining Functions

### `run_rule_engine(facts_json TEXT, rules_grl TEXT) → TEXT`

Execute GRL rules on JSON facts using forward chaining (data-driven).

**Parameters:**
- `facts_json` (TEXT): JSON string containing facts (nested objects supported)
- `rules_grl` (TEXT): GRL rule definitions (multiple rules separated by newlines)

**Returns:** JSON string with modified facts

**Size Limits:**
- Maximum 1MB for `facts_json`
- Maximum 1MB for `rules_grl`

**Example:**
```sql
SELECT run_rule_engine(
    '{"User": {"age": 30, "status": "active"}}',
    'rule "CheckAge" salience 10 {
        when User.age > 18
        then User.status = "adult";
    }'
);
-- Returns: {"User": {"age": 30, "status": "adult"}}
```

**Use Cases:**
- Event processing
- Data enrichment
- Automated actions
- Monitoring and alerts

---

## Backward Chaining Functions

### `query_backward_chaining(facts_json TEXT, rules_grl TEXT, goal TEXT) → JSON`

Query if a goal can be proven with full details and proof trace (goal-driven reasoning).

**Parameters:**
- `facts_json` (TEXT): JSON string containing initial facts
- `rules_grl` (TEXT): GRL rule definitions
- `goal` (TEXT): Goal query (e.g., `'User.CanBuy == true'`)

**Returns:** JSON object with the following structure:
```json
{
  "provable": true,
  "proof_trace": "Rule chain that proved the goal",
  "goals_explored": 5,
  "rules_evaluated": 3,
  "query_time_ms": 1.23
}
```

**Example:**
```sql
SELECT query_backward_chaining(
    '{"User": {"Age": 25}}',
    'rule "AgeCheck" {
        when User.Age >= 18
        then User.IsAdult = true;
    }',
    'User.IsAdult == true'
)::jsonb;

-- Returns:
-- {
--   "provable": true,
--   "proof_trace": "AgeCheck",
--   "goals_explored": 1,
--   "rules_evaluated": 1,
--   "query_time_ms": 0.85
-- }
```

**Use Cases:**
- Eligibility verification
- Decision explanation
- Debugging rule chains
- Compliance checking

---

### `query_backward_chaining_multi(facts_json TEXT, rules_grl TEXT, goals TEXT[]) → JSON[]`

Query multiple goals in one call for batch verification.

**Parameters:**
- `facts_json` (TEXT): JSON string containing initial facts
- `rules_grl` (TEXT): GRL rule definitions
- `goals` (TEXT[]): Array of goal queries

**Returns:** JSON array with results for each goal (same format as `query_backward_chaining`)

**Example:**
```sql
SELECT query_backward_chaining_multi(
    '{"User": {"Age": 25}}',
    'rule "Vote" { when User.Age >= 18 then User.CanVote = true; }
     rule "Retire" { when User.Age >= 65 then User.CanRetire = true; }',
    ARRAY['User.CanVote == true', 'User.CanRetire == true']
)::jsonb;

-- Returns array:
-- [
--   {"provable": true, "proof_trace": "Vote", ...},
--   {"provable": false, "proof_trace": "", ...}
-- ]
```

**Use Cases:**
- Batch verification
- Multi-requirement checks
- Feature access validation

---

### `can_prove_goal(facts_json TEXT, rules_grl TEXT, goal TEXT) → BOOLEAN`

Fast boolean check if goal is provable (production mode, no proof trace).

**Parameters:**
- `facts_json` (TEXT): JSON string containing initial facts
- `rules_grl` (TEXT): GRL rule definitions
- `goal` (TEXT): Goal query

**Returns:** `true` if provable, `false` otherwise

**Performance:** 2-3x faster than `query_backward_chaining` (no proof trace overhead)

**Example:**
```sql
SELECT can_prove_goal(
    '{"Order": {"Total": 100}}',
    'rule "Valid" { when Order.Total > 0 then Order.Valid = true; }',
    'Order.Valid == true'
);
-- Returns: true
```

**Use Cases:**
- High-throughput production checks
- Simple yes/no queries
- Performance-critical paths
- Trigger conditions

---

## Utility Functions

### `rule_engine_health_check() → TEXT`

Returns health status with version and timestamp.

**Returns:** JSON object
```json
{
  "status": "healthy",
  "extension": "rule_engine_postgre_extensions",
  "version": "1.0.0",
  "timestamp": "2025-01-18T10:00:00Z"
}
```

**Example:**
```sql
SELECT rule_engine_health_check();
```

**Use Cases:**
- Monitoring and health checks
- Deployment verification
- CI/CD pipelines

---

### `rule_engine_version() → TEXT`

Returns extension version string.

**Returns:** Version string (e.g., `"1.0.0"`)

**Example:**
```sql
SELECT rule_engine_version();
-- Returns: "1.0.0"
```

---

## Error Codes

All errors return JSON with `error`, `error_code`, and `timestamp` fields.

### Error Code Reference

| Code | Description | Common Cause |
|------|-------------|--------------|
| **ERR001** | Empty facts JSON | `facts_json` parameter is empty or whitespace |
| **ERR002** | Empty rules GRL | `rules_grl` parameter is empty or whitespace |
| **ERR003** | Facts JSON too large | `facts_json` exceeds 1MB limit |
| **ERR004** | Rules GRL too large | `rules_grl` exceeds 1MB limit |
| **ERR005** | Invalid JSON format (facts) | Malformed JSON in `facts_json` |
| **ERR006** | Invalid JSON format (rules parse) | JSON parsing error during rule processing |
| **ERR007** | No valid rules found | GRL syntax error or no rules defined |
| **ERR008** | Invalid GRL syntax | GRL parsing error (missing `when`/`then`, etc.) |
| **ERR009** | Rule parsing failed | GRL compilation error |
| **ERR010** | Rule validation failed | Semantic error in rule definitions |
| **ERR011** | Execution failed | Runtime error during rule execution |
| **ERR012** | Serialization failed | Error converting result to JSON |

### Example Error Response

```json
{
  "error": "Invalid JSON syntax: unexpected character at line 1 column 5",
  "error_code": "ERR005",
  "timestamp": "2025-01-18T10:00:00Z"
}
```

### Error Handling Example

```sql
DO $$
DECLARE
    result TEXT;
BEGIN
    result := run_rule_engine(
        '{"invalid json',
        'rule "test" { when true then User.x = 1; }'
    );

    -- Check for error
    IF result::jsonb ? 'error_code' THEN
        RAISE NOTICE 'Error: % (%)',
            result::jsonb->>'error',
            result::jsonb->>'error_code';
    END IF;
END $$;
```

---

## GRL Syntax Reference

### Basic Rule Structure

```grl
rule "RuleName" [attributes] {
    when
        [conditions]
    then
        [actions];
}
```

### Operators

#### Comparison Operators
- `==` - Equals
- `!=` - Not equals
- `>` - Greater than
- `>=` - Greater than or equal
- `<` - Less than
- `<=` - Less than or equal

#### Logical Operators
- `&&` - AND
- `||` - OR
- `!` - NOT

#### Collection Operators
- `contains` - Check if collection contains value
- `empty` - Check if collection is empty
- `not_empty` - Check if collection is not empty
- `count` - Get collection size
- `first` - Get first element
- `last` - Get last element
- `items[0]` - Index access
- `items[1:3]` - Slice access

### Rule Attributes

#### Salience (Priority)
Controls rule execution order. Higher salience executes first.

```grl
rule "HighPriority" salience 100 {
    when User.age > 18
    then User.adult = true;
}

rule "LowPriority" salience 10 {
    when User.adult == true
    then User.canVote = true;
}
```

**Default:** `salience 0`

#### No-Loop
Prevents infinite loops when rule modifies its own conditions.

```grl
rule "NoLoop" no-loop {
    when Order.total > 100
    then Order.total = Order.total * 0.9;  // Won't re-fire
}
```

#### Lock-On-Active
Prevents rule from firing again in the same execution cycle.

```grl
rule "OncePerCycle" lock-on-active {
    when User.status == "new"
    then User.status = "active";
}
```

### Complete Examples

#### Simple Condition
```grl
rule "AdultCheck" {
    when User.age >= 18
    then User.isAdult = true;
}
```

#### Multiple Conditions
```grl
rule "DiscountRule" salience 10 {
    when
        Order.total > 100 &&
        Customer.tier == "Gold" &&
        Order.items >= 5
    then
        Order.discount = 0.20;
        Order.status = "approved";
}
```

#### Nested Objects
```grl
rule "ShippingDiscount" {
    when
        Order.shipping.country == "US" &&
        Order.shipping.method == "express"
    then
        Order.shipping.discount = 10.0;
}
```

#### Array Operations
```grl
rule "CartDiscount" {
    when Order.items.count > 10
    then Order.bulkDiscount = true;
}
```

### Best Practices

1. **Use Salience Wisely**: Higher-level business rules should have lower salience
2. **Avoid Infinite Loops**: Use `no-loop` when modifying conditions
3. **Keep Rules Atomic**: One business decision per rule
4. **Name Rules Clearly**: Use descriptive names for debugging
5. **Document Complex Logic**: Add comments in rule storage tables

### Additional Resources

- [rust-rule-engine GRL Syntax Guide](https://github.com/KSD-CO/rust-rule-engine/wiki/03-GRL-Syntax-Guide)
- [Use Case Examples](examples/use-cases.md)
- [Integration Patterns](integration-patterns.md)

---

## Performance Characteristics

### Forward Chaining

| Scenario | Avg Time | Throughput |
|----------|----------|------------|
| Simple rule (1 condition) | 0.8ms | 1250 rules/sec |
| Complex rule (5 conditions) | 2.1ms | 476 rules/sec |
| Nested objects (3 levels) | 1.5ms | 667 rules/sec |

### Backward Chaining

| Function | Mode | Avg Time | Overhead |
|----------|------|----------|----------|
| `query_backward_chaining` | Dev | 2-3ms | Full trace |
| `query_backward_chaining_multi` | Dev | 5-8ms | Multiple goals |
| `can_prove_goal` | Prod | 0.5-1ms | Minimal |

**Benchmark Environment**: AMD Ryzen 9 5950X, PostgreSQL 17, 1000 executions

---

## Type Compatibility

### JSON/JSONB Support

Both `::TEXT` and `::JSONB` conversions are supported:

```sql
-- String input
SELECT run_rule_engine('{"x": 1}', 'rule "r" { when true then x = 2; }');

-- JSONB input
SELECT run_rule_engine(
    data::TEXT,
    rules_text
)::JSONB
FROM my_table;
```

### PostgreSQL Type Mapping

| GRL Type | PostgreSQL Type | Notes |
|----------|-----------------|-------|
| `true/false` | BOOLEAN | Direct mapping |
| Numbers | NUMERIC, INT | Precision preserved |
| Strings | TEXT, VARCHAR | Unicode supported |
| Arrays | JSON Array | Nested arrays supported |
| Objects | JSON Object | Deep nesting supported |
| `null` | NULL | Handled correctly |

---

## See Also

- [Getting Started Guide](../README.md#quick-start)
- [Backward Chaining Guide](guides/backward-chaining.md)
- [Use Case Examples](examples/use-cases.md)
- [Deployment Guide](deployment/docker.md)
