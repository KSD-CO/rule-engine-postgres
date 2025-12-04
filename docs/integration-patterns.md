# Integration Patterns

Best practices for integrating the PostgreSQL Rule Engine into your applications.

## Table of Contents

- [Database Triggers](#database-triggers)
- [JSONB Columns](#jsonb-columns)
- [Storing Rules in Database](#storing-rules-in-database)
- [Batch Processing](#batch-processing)
- [Performance Optimization](#performance-optimization)
- [Security Best Practices](#security-best-practices)

---

## Database Triggers

### Basic Trigger Pattern

Execute rules automatically when data changes:

```sql
CREATE OR REPLACE FUNCTION validate_with_rules()
RETURNS TRIGGER AS $$
BEGIN
    NEW.data := run_rule_engine(
        NEW.data::TEXT,
        (SELECT rules FROM rule_definitions WHERE active = TRUE)
    )::JSONB;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_order
    BEFORE INSERT OR UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION validate_with_rules();
```

### Conditional Trigger

Only run rules when specific conditions are met:

```sql
CREATE OR REPLACE FUNCTION conditional_rules()
RETURNS TRIGGER AS $$
BEGIN
    -- Only apply rules for pending orders
    IF NEW.status = 'pending' THEN
        NEW.data := run_rule_engine(
            NEW.data::TEXT,
            (SELECT string_agg(grl_rule, E'\n')
             FROM business_rules
             WHERE category = 'order_validation' AND active = TRUE)
        )::JSONB;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### Async Trigger (Non-Blocking)

Use AFTER trigger for non-critical rules:

```sql
CREATE OR REPLACE FUNCTION queue_rule_processing()
RETURNS TRIGGER AS $$
BEGIN
    -- Insert into processing queue
    INSERT INTO rule_processing_queue (order_id, data, status)
    VALUES (NEW.order_id, NEW.data, 'pending');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER async_rules
    AFTER INSERT ON events
    FOR EACH ROW
    EXECUTE FUNCTION queue_rule_processing();
```

---

## JSONB Columns

### Direct JSONB Update

Apply rules directly to JSONB columns:

```sql
UPDATE products
SET data = run_rule_engine(data::TEXT, $rules$
    rule "Discount" salience 10 {
        when Product.stock > 100
        then Product.onSale = true;
    }
$rules$)::JSONB
WHERE category = 'electronics';
```

### Conditional JSONB Processing

```sql
WITH rules_applied AS (
    SELECT
        product_id,
        run_rule_engine(
            data::TEXT,
            (SELECT rules FROM pricing_rules WHERE category = data->>'category')
        )::JSONB as new_data
    FROM products
    WHERE (data->>'stock')::INT > 0
)
UPDATE products p
SET data = ra.new_data
FROM rules_applied ra
WHERE p.product_id = ra.product_id;
```

### Nested JSONB Extraction

```sql
SELECT
    user_id,
    run_rule_engine(
        jsonb_build_object(
            'User', data->'profile',
            'Account', data->'account'
        )::TEXT,
        validation_rules
    )::JSONB
FROM users;
```

---

## Storing Rules in Database

### Basic Rules Table

```sql
CREATE TABLE business_rules (
    rule_id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    category TEXT,
    grl_definition TEXT NOT NULL,
    priority INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    version INT DEFAULT 1,
    created_by TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Create index for fast category lookup
CREATE INDEX idx_rules_category_active ON business_rules(category, is_active);
```

### Rule Version Control

```sql
CREATE TABLE rule_history (
    history_id SERIAL PRIMARY KEY,
    rule_id INT REFERENCES business_rules(rule_id),
    version INT,
    grl_definition TEXT,
    changed_by TEXT,
    changed_at TIMESTAMP DEFAULT NOW()
);

-- Trigger to maintain history
CREATE OR REPLACE FUNCTION track_rule_changes()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO rule_history (rule_id, version, grl_definition, changed_by)
    VALUES (OLD.rule_id, OLD.version, OLD.grl_definition, CURRENT_USER);

    NEW.version := OLD.version + 1;
    NEW.updated_at := NOW();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER rule_version_trigger
    BEFORE UPDATE ON business_rules
    FOR EACH ROW
    WHEN (OLD.grl_definition IS DISTINCT FROM NEW.grl_definition)
    EXECUTE FUNCTION track_rule_changes();
```

### Dynamic Rule Loading

```sql
-- Load and combine rules by category
CREATE OR REPLACE FUNCTION get_rules_by_category(p_category TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN (
        SELECT string_agg(grl_definition, E'\n' ORDER BY priority DESC)
        FROM business_rules
        WHERE category = p_category AND is_active = TRUE
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- Usage
SELECT run_rule_engine(
    order_data::TEXT,
    get_rules_by_category('pricing')
) FROM orders;
```

---

## Batch Processing

### Process Multiple Records Efficiently

```sql
-- Update all pending orders in one query
WITH order_rules AS (
    SELECT string_agg(grl_definition, E'\n' ORDER BY priority DESC) as rules
    FROM business_rules
    WHERE category = 'order_processing' AND is_active = TRUE
),
processed AS (
    SELECT
        order_id,
        run_rule_engine(data::TEXT, (SELECT rules FROM order_rules))::JSONB as result
    FROM orders
    WHERE status = 'pending'
)
UPDATE orders o
SET
    data = p.result,
    status = 'processed',
    updated_at = NOW()
FROM processed p
WHERE o.order_id = p.order_id;
```

### Parallel Batch Processing

```sql
-- Process in chunks to avoid long locks
DO $$
DECLARE
    batch_size INT := 1000;
    offset_val INT := 0;
    rows_affected INT;
BEGIN
    LOOP
        WITH batch AS (
            SELECT order_id
            FROM orders
            WHERE status = 'pending'
            ORDER BY order_id
            LIMIT batch_size OFFSET offset_val
        )
        UPDATE orders o
        SET data = run_rule_engine(o.data::TEXT, rules)::JSONB
        FROM batch b, business_rules
        WHERE o.order_id = b.order_id;

        GET DIAGNOSTICS rows_affected = ROW_COUNT;
        EXIT WHEN rows_affected = 0;

        offset_val := offset_val + batch_size;
        COMMIT;  -- Commit each batch
    END LOOP;
END $$;
```

---

## Performance Optimization

### 1. Connection Pooling

Use PgBouncer for high concurrency:

```bash
docker run -d \
  --name pgbouncer \
  -p 6432:6432 \
  -e DATABASES_HOST=postgres \
  -e DATABASES_PORT=5432 \
  -e DATABASES_USER=postgres \
  -e DATABASES_PASSWORD=password \
  pgbouncer/pgbouncer
```

### 2. Rule Caching

Cache frequently-used rules in materialized views:

```sql
CREATE MATERIALIZED VIEW cached_rules AS
SELECT
    category,
    string_agg(grl_definition, E'\n' ORDER BY priority DESC) as rules
FROM business_rules
WHERE is_active = TRUE
GROUP BY category;

CREATE INDEX idx_cached_rules_category ON cached_rules(category);

-- Refresh periodically
REFRESH MATERIALIZED VIEW cached_rules;
```

### 3. Indexed JSONB Columns

Index JSONB for faster trigger performance:

```sql
-- GIN index for general JSONB operations
CREATE INDEX idx_order_data ON orders USING GIN (data jsonb_path_ops);

-- Specific field indexes
CREATE INDEX idx_order_status ON orders ((data->>'status'));
CREATE INDEX idx_order_total ON orders (((data->>'total')::NUMERIC));
```

### 4. Prepared Statements

Use prepared statements in application code:

```python
# Python example with psycopg2
import psycopg2

conn = psycopg2.connect(database="mydb")
cursor = conn.cursor()

# Prepare statement
cursor.execute("""
    PREPARE rule_exec (TEXT, TEXT) AS
    SELECT run_rule_engine($1, $2)
""")

# Execute multiple times
for order in orders:
    cursor.execute("EXECUTE rule_exec(%s, %s)", (order_data, rules))
```

### 5. Monitoring Query Performance

```sql
-- Enable timing
\timing on

-- Analyze query plan
EXPLAIN ANALYZE
SELECT run_rule_engine(
    data::TEXT,
    (SELECT rules FROM cached_rules WHERE category = 'pricing')
)
FROM orders WHERE status = 'pending';

-- Create execution log
CREATE TABLE rule_execution_logs (
    log_id SERIAL PRIMARY KEY,
    execution_time_ms NUMERIC,
    rules_count INT,
    facts_size INT,
    created_at TIMESTAMP DEFAULT NOW()
);
```

---

## Security Best Practices

### Input Validation

The extension automatically validates inputs:

- ✅ Maximum size: 1MB for facts and rules
- ✅ JSON syntax validation
- ✅ GRL syntax validation
- ✅ SQL injection protection (parameterized queries)

### Role-Based Access Control

```sql
-- Create rule admin role
CREATE ROLE rule_admin;

-- Grant permissions
GRANT SELECT, INSERT, UPDATE ON business_rules TO rule_admin;
GRANT SELECT ON rule_history TO rule_admin;

-- Create read-only role
CREATE ROLE rule_executor;
GRANT SELECT ON business_rules TO rule_executor;
GRANT EXECUTE ON FUNCTION run_rule_engine(TEXT, TEXT) TO rule_executor;

-- Assign roles to users
GRANT rule_admin TO alice;
GRANT rule_executor TO bob;
```

### Audit Logging

```sql
CREATE TABLE rule_audit_log (
    log_id SERIAL PRIMARY KEY,
    user_name TEXT DEFAULT CURRENT_USER,
    rule_name TEXT,
    input_facts JSONB,
    output_facts JSONB,
    execution_time_ms NUMERIC,
    executed_at TIMESTAMP DEFAULT NOW()
);

-- Audit trigger
CREATE OR REPLACE FUNCTION audit_rule_execution()
RETURNS TRIGGER AS $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
BEGIN
    start_time := clock_timestamp();

    -- Execute rules
    NEW.data := run_rule_engine(NEW.data::TEXT, rules)::JSONB;

    end_time := clock_timestamp();

    -- Log execution
    INSERT INTO rule_audit_log (rule_name, input_facts, output_facts, execution_time_ms)
    VALUES (
        'order_rules',
        OLD.data,
        NEW.data,
        EXTRACT(EPOCH FROM (end_time - start_time)) * 1000
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### Restrict Rule Modifications

```sql
-- Prevent deletion of active rules
CREATE OR REPLACE FUNCTION prevent_rule_deletion()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.is_active = TRUE THEN
        RAISE EXCEPTION 'Cannot delete active rules. Deactivate first.';
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER no_delete_active_rules
    BEFORE DELETE ON business_rules
    FOR EACH ROW
    EXECUTE FUNCTION prevent_rule_deletion();
```

---

## Testing Patterns

### Unit Testing Rules

```sql
-- Test function
CREATE OR REPLACE FUNCTION test_pricing_rules()
RETURNS TABLE(test_name TEXT, passed BOOLEAN) AS $$
BEGIN
    -- Test 1: Volume discount
    RETURN QUERY
    SELECT
        'Volume discount applied'::TEXT,
        (run_rule_engine(
            '{"Order": {"items": 15, "discount": 0}}',
            'rule "Volume" { when Order.items >= 10 then Order.discount = 0.15; }'
        )::JSONB->'Order'->>'discount')::NUMERIC = 0.15;

    -- Test 2: No discount for small orders
    RETURN QUERY
    SELECT
        'No discount for small orders'::TEXT,
        (run_rule_engine(
            '{"Order": {"items": 5, "discount": 0}}',
            'rule "Volume" { when Order.items >= 10 then Order.discount = 0.15; }'
        )::JSONB->'Order'->>'discount')::NUMERIC = 0;
END;
$$ LANGUAGE plpgsql;

-- Run tests
SELECT * FROM test_pricing_rules();
```

### Integration Testing

```sql
-- Create test data
BEGIN;

INSERT INTO orders (data) VALUES
('{"User": {"tier": "Gold"}, "Order": {"total": 150}}'::JSONB),
('{"User": {"tier": "Silver"}, "Order": {"total": 50}}'::JSONB);

-- Apply rules
UPDATE orders SET data = run_rule_engine(data::TEXT, test_rules)::JSONB;

-- Verify results
SELECT
    (data->'Order'->>'discount')::NUMERIC as discount,
    (data->'Order'->>'total')::NUMERIC as total
FROM orders;

ROLLBACK;  -- Clean up test data
```

---

## See Also

- [API Reference](api-reference.md)
- [Use Case Examples](examples/use-cases.md)
- [Backward Chaining Guide](guides/backward-chaining.md)
- [Deployment Guide](deployment/docker.md)
