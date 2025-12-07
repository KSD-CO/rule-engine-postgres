# Event Trigger Functions API Reference

Event Triggers enable automatic rule execution when database tables change.

## Overview

Event Triggers monitor INSERT, UPDATE, or DELETE operations on specified tables and automatically execute rules. This enables:

- **Real-time Processing**: Apply business logic instantly when data changes
- **Audit Trail**: Track all executions with OLD/NEW data snapshots
- **Decoupled Logic**: Keep business rules separate from application code
- **Performance**: ~1-5ms overhead per trigger execution

---

## rule_trigger_create()

Create a new event trigger to automatically execute a rule.

### Signature

```sql
rule_trigger_create(
    name TEXT,           -- Unique trigger name
    table_name TEXT,     -- Target table to monitor
    rule_name TEXT,      -- Rule to execute (from rule_definitions)
    event_type TEXT      -- 'INSERT', 'UPDATE', or 'DELETE'
) → INTEGER             -- Returns trigger_id
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | TEXT | Unique identifier for this trigger |
| `table_name` | TEXT | Name of the table to monitor (must exist) |
| `rule_name` | TEXT | Rule to execute (must exist in `rule_definitions`) |
| `event_type` | TEXT | Event type: `INSERT`, `UPDATE`, or `DELETE` |

### Returns

- **INTEGER**: Trigger ID for future operations

### Errors

| Code | Description |
|------|-------------|
| ERR_RT001 | Invalid event_type (must be INSERT, UPDATE, or DELETE) |
| ERR_RT002 | Rule not found in rule_definitions |
| ERR_RT003 | Table not found |

### Example

```sql
-- Create discount rule
SELECT rule_save(
    'order_discount',
    'rule "VIPDiscount" {
        when Order.total_amount > 100
        then Order.discount_amount = Order.total_amount * 0.1;
             Order.final_amount = Order.total_amount - Order.discount_amount;
    }',
    '1.0.0',
    'VIP discount rule',
    'Initial version'
);

-- Create trigger on orders table
SELECT rule_trigger_create(
    'order_discount_trigger',
    'orders',
    'order_discount',
    'INSERT'
) AS trigger_id;

-- Now INSERT operations automatically apply discounts!
INSERT INTO orders (customer_id, total_amount)
VALUES (123, 150.00);
-- discount_amount and final_amount calculated automatically
```

### Best Practices

1. **Use descriptive names**: `order_discount_trigger` not `trigger1`
2. **One rule per trigger**: Keep logic focused and testable
3. **Test before enabling**: Create disabled, test, then enable
4. **Monitor performance**: Check `rule_trigger_stats` regularly

---

## rule_trigger_enable()

Enable or disable a trigger without deleting it.

### Signature

```sql
rule_trigger_enable(
    trigger_id INTEGER,  -- ID of the trigger
    enabled BOOLEAN      -- TRUE to enable, FALSE to disable (default: TRUE)
) → BOOLEAN             -- Returns TRUE on success
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `trigger_id` | INTEGER | Required | ID of the trigger to enable/disable |
| `enabled` | BOOLEAN | TRUE | TRUE to enable, FALSE to disable |

### Returns

- **BOOLEAN**: TRUE if successful

### Errors

| Code | Description |
|------|-------------|
| ERR_RT004 | Trigger not found |

### Example

```sql
-- Disable trigger for maintenance
SELECT rule_trigger_enable(1, FALSE);

-- Perform bulk operations without triggers
INSERT INTO orders SELECT * FROM staging_orders;

-- Re-enable trigger
SELECT rule_trigger_enable(1, TRUE);
```

### Use Cases

- **Maintenance Windows**: Disable during bulk imports
- **A/B Testing**: Enable/disable to test impact
- **Debugging**: Temporarily disable problematic triggers
- **Staged Rollout**: Enable for subset of tables first

---

## rule_trigger_history()

View execution history for a trigger with timing and error details.

### Signature

```sql
rule_trigger_history(
    trigger_id INTEGER,                                    -- Trigger to query
    start_time TIMESTAMP WITH TIME ZONE DEFAULT NOW() - INTERVAL '1 day',
    end_time TIMESTAMP WITH TIME ZONE DEFAULT NOW()
) → JSON                                                   -- Returns JSON array
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `trigger_id` | INTEGER | Required | ID of the trigger |
| `start_time` | TIMESTAMPTZ | 1 day ago | Start of time range |
| `end_time` | TIMESTAMPTZ | Now | End of time range |

### Returns

JSON array with history records:

```json
[
  {
    "id": 1,
    "executed_at": "2025-12-07T10:30:00Z",
    "event_type": "INSERT",
    "success": true,
    "execution_time_ms": 2.45,
    "error_message": null,
    "result_summary": "{\"Order\": {\"discount_amount\": 15.00}}..."
  }
]
```

### Example

```sql
-- Get last 24 hours (default)
SELECT rule_trigger_history(1);

-- Get last week
SELECT rule_trigger_history(
    1,
    NOW() - INTERVAL '7 days',
    NOW()
);

-- Filter failures only
SELECT *
FROM json_array_elements(rule_trigger_history(1)::json)
WHERE (value->>'success')::boolean = false;

-- Average execution time
SELECT AVG((value->>'execution_time_ms')::numeric) AS avg_ms
FROM json_array_elements(rule_trigger_history(1)::json);
```

### Monitoring Queries

```sql
-- Recent failures
SELECT 
    value->>'executed_at' AS when,
    value->>'error_message' AS error
FROM json_array_elements(rule_trigger_history(1)::json)
WHERE (value->>'success')::boolean = false
ORDER BY value->>'executed_at' DESC
LIMIT 10;

-- Performance degradation
SELECT 
    date_trunc('hour', (value->>'executed_at')::timestamptz) AS hour,
    AVG((value->>'execution_time_ms')::numeric) AS avg_ms,
    MAX((value->>'execution_time_ms')::numeric) AS max_ms
FROM json_array_elements(rule_trigger_history(1, NOW() - INTERVAL '1 week', NOW())::json)
GROUP BY hour
ORDER BY hour DESC;
```

---

## rule_trigger_delete()

Delete a trigger and clean up associated PostgreSQL trigger.

### Signature

```sql
rule_trigger_delete(
    trigger_id INTEGER   -- ID of the trigger to delete
) → BOOLEAN             -- Returns TRUE on success
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `trigger_id` | INTEGER | ID of the trigger to delete |

### Returns

- **BOOLEAN**: TRUE if successful

### Errors

| Code | Description |
|------|-------------|
| ERR_RT005 | Trigger not found |

### Example

```sql
-- Delete trigger
SELECT rule_trigger_delete(1);

-- Verify deletion
SELECT * FROM rule_triggers WHERE id = 1;
-- Returns: (empty)
```

### Behavior

- **Cascade Delete**: History records are deleted automatically
- **PostgreSQL Trigger**: Underlying trigger is dropped if no other configs exist
- **Safe**: Cannot delete if trigger doesn't exist (returns error)

### Warning

⚠️ **Deletion is permanent**. Consider disabling instead of deleting if you might need to re-enable later.

---

## rule_trigger_stats (View)

Real-time statistics for all triggers.

### Schema

```sql
CREATE VIEW rule_trigger_stats AS
SELECT 
    trigger_id,
    trigger_name,
    table_name,
    rule_name,
    event_type,
    enabled,
    total_executions,
    successful_executions,
    failed_executions,
    avg_execution_time_ms,
    last_executed_at
FROM ...
```

### Example

```sql
-- View all trigger stats
SELECT * FROM rule_trigger_stats;

-- Find slow triggers
SELECT trigger_name, avg_execution_time_ms
FROM rule_trigger_stats
WHERE avg_execution_time_ms > 10
ORDER BY avg_execution_time_ms DESC;

-- Find failing triggers
SELECT trigger_name, failed_executions, 
       (failed_executions::float / total_executions * 100) AS failure_rate
FROM rule_trigger_stats
WHERE failed_executions > 0
ORDER BY failure_rate DESC;

-- Check inactive triggers
SELECT trigger_name, last_executed_at
FROM rule_trigger_stats
WHERE last_executed_at < NOW() - INTERVAL '1 day'
  AND enabled = true;
```

---

## Performance Considerations

### Overhead

- **Per Execution**: ~1-5ms overhead per trigger
- **Bulk Operations**: Consider disabling triggers during large imports
- **Multiple Triggers**: Each trigger adds ~1-5ms (cumulative)

### Optimization Tips

1. **Keep Rules Simple**: Complex rules = slower execution
2. **Use Indexes**: Ensure tables have proper indexes
3. **Batch Operations**: Group INSERTs when possible
4. **Monitor**: Use `rule_trigger_stats` to identify bottlenecks
5. **Disable When Needed**: Disable during maintenance windows

### Example: Bulk Import

```sql
-- Disable trigger
SELECT rule_trigger_enable(1, FALSE);

-- Bulk import
COPY orders FROM '/tmp/orders.csv' WITH CSV;

-- Re-enable trigger
SELECT rule_trigger_enable(1, TRUE);

-- Apply rules retroactively if needed
UPDATE orders SET total_amount = total_amount WHERE discount_amount IS NULL;
```

---

## Error Handling

Triggers **do not fail transactions**. If a rule execution fails:

1. Error is logged to `rule_trigger_history`
2. Warning is raised (visible in logs)
3. Transaction continues normally

### Example: Check for Errors

```sql
-- Recent errors
SELECT 
    value->>'executed_at' AS when,
    value->>'event_type' AS event,
    value->>'error_message' AS error
FROM json_array_elements(rule_trigger_history(1)::json)
WHERE (value->>'success')::boolean = false
ORDER BY value->>'executed_at' DESC;
```

---

## Complete Example: Order Processing

```sql
-- 1. Create orders table
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL,
    discount_amount NUMERIC(10, 2) DEFAULT 0,
    final_amount NUMERIC(10, 2),
    loyalty_points INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);

-- 2. Save discount rule
SELECT rule_save(
    'order_processing',
    'rule "VIPDiscount" salience 10 {
        when Order.total_amount > 100
        then Order.discount_amount = Order.total_amount * 0.1;
             Order.final_amount = Order.total_amount - Order.discount_amount;
             Order.loyalty_points = (Order.final_amount / 10)::int;
    }
    rule "RegularDiscount" salience 5 {
        when Order.total_amount > 50 && Order.total_amount <= 100
        then Order.discount_amount = Order.total_amount * 0.05;
             Order.final_amount = Order.total_amount - Order.discount_amount;
             Order.loyalty_points = (Order.final_amount / 20)::int;
    }',
    '1.0.0',
    'Order processing rules',
    'Initial version'
);

-- 3. Create trigger
SELECT rule_trigger_create(
    'order_processing_trigger',
    'orders',
    'order_processing',
    'INSERT'
) AS trigger_id \gset

-- 4. Test with orders
INSERT INTO orders (customer_id, total_amount) VALUES 
    (1, 150.00),   -- VIP discount: 15.00, final: 135.00, points: 13
    (2, 75.00),    -- Regular discount: 3.75, final: 71.25, points: 3
    (3, 30.00);    -- No discount

-- 5. View results
SELECT * FROM orders;

-- 6. Check stats
SELECT * FROM rule_trigger_stats WHERE trigger_id = :trigger_id;

-- 7. View history
SELECT rule_trigger_history(:trigger_id);
```

---

## See Also

- [Event Triggers Overview](Event-Triggers-Overview)
- [Creating Triggers](Creating-Triggers)
- [Trigger Monitoring](Trigger-Monitoring)
- [Rule Repository Functions](Repository-Functions)
