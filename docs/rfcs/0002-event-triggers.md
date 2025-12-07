# RFC-0002: Event Triggers Integration

**Status:** Draft  
**Author:** System  
**Created:** 2025-12-07  
**Updated:** 2025-12-07

---

## Summary

Enable automatic rule execution when database tables change (INSERT, UPDATE, DELETE) by creating PostgreSQL triggers that invoke stored rules from the Rule Repository.

---

## Motivation

**Problem:**
- Users need to run business rules automatically when data changes
- Manual rule execution requires application code
- No built-in way to react to database events with rules

**Use Cases:**
1. **Order Validation:** Validate orders when inserted, apply discounts automatically
2. **Audit Trail:** Log changes and apply compliance rules
3. **Data Enrichment:** Auto-populate calculated fields based on rules
4. **Notification:** Trigger alerts when certain conditions are met

---

## Design

### 1. Database Schema

```sql
-- Rule trigger configurations
CREATE TABLE rule_triggers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    table_name VARCHAR(255) NOT NULL,
    rule_name VARCHAR(255) NOT NULL REFERENCES rule_definitions(name),
    event_type VARCHAR(10) NOT NULL CHECK (event_type IN ('INSERT', 'UPDATE', 'DELETE')),
    enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW(),
    created_by VARCHAR(255) DEFAULT CURRENT_USER,
    updated_at TIMESTAMP DEFAULT NOW(),
    updated_by VARCHAR(255) DEFAULT CURRENT_USER,
    CONSTRAINT unique_trigger UNIQUE (table_name, event_type, rule_name)
);

-- Trigger execution history
CREATE TABLE rule_trigger_history (
    id BIGSERIAL PRIMARY KEY,
    trigger_id INTEGER REFERENCES rule_triggers(id) ON DELETE CASCADE,
    executed_at TIMESTAMP DEFAULT NOW(),
    event_type VARCHAR(10) NOT NULL,
    old_data JSONB,
    new_data JSONB,
    result_data JSONB,
    success BOOLEAN NOT NULL,
    error_message TEXT,
    execution_time_ms NUMERIC(10, 2)
);

-- Indexes for performance
CREATE INDEX idx_trigger_history_trigger_id ON rule_trigger_history(trigger_id);
CREATE INDEX idx_trigger_history_executed_at ON rule_trigger_history(executed_at);
CREATE INDEX idx_triggers_table_name ON rule_triggers(table_name);
```

### 2. Trigger Function

Generic trigger function that executes rules:

```sql
CREATE OR REPLACE FUNCTION execute_rule_trigger()
RETURNS TRIGGER AS $$
DECLARE
    trigger_config RECORD;
    facts_json TEXT;
    result_json TEXT;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    execution_ms NUMERIC;
BEGIN
    start_time := clock_timestamp();
    
    -- Find all enabled triggers for this table and event
    FOR trigger_config IN
        SELECT rt.id, rt.rule_name
        FROM rule_triggers rt
        WHERE rt.table_name = TG_TABLE_NAME
          AND rt.event_type = TG_OP
          AND rt.enabled = TRUE
    LOOP
        BEGIN
            -- Build facts JSON based on event type
            IF TG_OP = 'DELETE' THEN
                facts_json := row_to_json(OLD)::TEXT;
            ELSE
                facts_json := row_to_json(NEW)::TEXT;
            END IF;
            
            -- Execute rule by name
            result_json := rule_execute_by_name(
                trigger_config.rule_name,
                facts_json,
                NULL  -- Use default version
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
            
            -- Update NEW with modified data (for INSERT/UPDATE)
            IF TG_OP IN ('INSERT', 'UPDATE') THEN
                NEW := jsonb_populate_record(NEW, result_json::JSONB);
            END IF;
            
        EXCEPTION WHEN OTHERS THEN
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
            
            -- Don't fail the transaction, just log the error
            RAISE WARNING 'Rule trigger failed: %', SQLERRM;
        END;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### 3. API Functions

#### 3.1 Create Trigger

```sql
CREATE OR REPLACE FUNCTION rule_trigger_create(
    p_name TEXT,
    p_table_name TEXT,
    p_rule_name TEXT,
    p_event_type TEXT
) RETURNS INTEGER AS $$
DECLARE
    v_trigger_id INTEGER;
    v_trigger_name TEXT;
BEGIN
    -- Validate inputs
    IF p_event_type NOT IN ('INSERT', 'UPDATE', 'DELETE') THEN
        RAISE EXCEPTION 'Invalid event_type. Must be INSERT, UPDATE, or DELETE';
    END IF;
    
    -- Check if rule exists
    IF NOT EXISTS (SELECT 1 FROM rule_definitions WHERE name = p_rule_name) THEN
        RAISE EXCEPTION 'Rule not found: %', p_rule_name;
    END IF;
    
    -- Insert trigger config
    INSERT INTO rule_triggers (name, table_name, rule_name, event_type)
    VALUES (p_name, p_table_name, p_rule_name, p_event_type)
    RETURNING id INTO v_trigger_id;
    
    -- Create PostgreSQL trigger if not exists
    v_trigger_name := 'rule_trigger_' || p_table_name || '_' || lower(p_event_type);
    
    EXECUTE format(
        'CREATE TRIGGER IF NOT EXISTS %I
         BEFORE %s ON %I
         FOR EACH ROW
         EXECUTE FUNCTION execute_rule_trigger()',
        v_trigger_name,
        p_event_type,
        p_table_name
    );
    
    RETURN v_trigger_id;
END;
$$ LANGUAGE plpgsql;
```

#### 3.2 Enable/Disable Trigger

```sql
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
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;
```

#### 3.3 Get Trigger History

```sql
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
    error_message TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        rth.id,
        rth.executed_at,
        rth.event_type,
        rth.success,
        rth.execution_time_ms,
        rth.error_message
    FROM rule_trigger_history rth
    WHERE rth.trigger_id = p_trigger_id
      AND rth.executed_at BETWEEN p_start_time AND p_end_time
    ORDER BY rth.executed_at DESC;
END;
$$ LANGUAGE plpgsql;
```

#### 3.4 Delete Trigger

```sql
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
        RETURN FALSE;
    END IF;
    
    -- Delete trigger config (cascade deletes history)
    DELETE FROM rule_triggers WHERE id = p_trigger_id;
    
    -- Check if other triggers exist for this table/event
    SELECT EXISTS (
        SELECT 1 FROM rule_triggers
        WHERE table_name = v_trigger.table_name
          AND event_type = v_trigger.event_type
    ) INTO v_has_others;
    
    -- Drop PostgreSQL trigger if no more configs
    IF NOT v_has_others THEN
        v_trigger_name := 'rule_trigger_' || v_trigger.table_name || '_' || lower(v_trigger.event_type);
        
        EXECUTE format(
            'DROP TRIGGER IF EXISTS %I ON %I',
            v_trigger_name,
            v_trigger.table_name
        );
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
```

### 4. Usage Example

```sql
-- 1. Create a discount rule
SELECT rule_save(
    'order_discount',
    'rule "ApplyDiscount" {
        when Order.total > 1000
        then Order.discount = 0.10;
    }',
    '1.0.0',
    'Apply 10% discount for orders over $1000',
    'Initial version'
);

-- 2. Create trigger to auto-apply discount on INSERT
SELECT rule_trigger_create(
    'order_discount_trigger',
    'orders',
    'order_discount',
    'INSERT'
);

-- 3. Insert order - discount applied automatically
INSERT INTO orders (customer_id, total)
VALUES (123, 1500);
-- Order will have discount = 0.10 automatically

-- 4. View trigger history
SELECT * FROM rule_trigger_history(1, NOW() - INTERVAL '1 hour', NOW());

-- 5. Disable trigger temporarily
SELECT rule_trigger_enable(1, FALSE);

-- 6. Re-enable
SELECT rule_trigger_enable(1, TRUE);

-- 7. Delete trigger
SELECT rule_trigger_delete(1);
```

---

## Performance Considerations

1. **Trigger Overhead:** ~1-5ms per trigger execution
2. **History Table:** Can grow large - implement retention policy
3. **Error Handling:** Errors logged but don't fail transaction
4. **Indexing:** History table indexed on trigger_id and executed_at

### Optimization Strategies

- Archive old history data (>30 days)
- Use materialized views for analytics
- Consider async execution for non-critical triggers (future enhancement)

---

## Security

1. **Permissions:** Only superuser/owner can create triggers
2. **Rule Validation:** Verify rule exists before creating trigger
3. **SQL Injection:** Use parameterized queries, `format()` with identifiers
4. **Audit:** All trigger actions logged in history table

---

## Testing

```sql
-- Test: Basic trigger creation
SELECT rule_trigger_create('test_trigger', 'test_table', 'test_rule', 'INSERT');

-- Test: Enable/disable
SELECT rule_trigger_enable(1, FALSE);
SELECT rule_trigger_enable(1, TRUE);

-- Test: History retrieval
SELECT * FROM rule_trigger_history(1, NOW() - INTERVAL '1 day', NOW());

-- Test: Delete trigger
SELECT rule_trigger_delete(1);

-- Test: Error handling
-- (Insert invalid rule, verify error logged in history)
```

---

## Migration Path

Users can migrate from manual rule execution:

**Before:**
```sql
-- Application code
SELECT rule_execute_by_name('order_discount', order_data::TEXT, NULL);
```

**After:**
```sql
-- One-time setup
SELECT rule_trigger_create('order_discount_trigger', 'orders', 'order_discount', 'INSERT');

-- Automatic execution on every INSERT
INSERT INTO orders (...) VALUES (...);
```

---

## Future Enhancements

1. **Async Execution:** Queue-based triggers for non-blocking operations
2. **Conditional Triggers:** Only fire when certain conditions met
3. **Batch Processing:** Execute rules on multiple rows efficiently
4. **Trigger Priority:** Control execution order when multiple triggers exist
5. **Event Filters:** Fire only when specific columns change

---

## Alternatives Considered

1. **Application-level triggers:** More flexible but requires app changes
2. **Polling-based:** Check for changes periodically - higher latency
3. **Message queue:** Async but adds infrastructure complexity

Chose database triggers for:
- Real-time execution
- No application changes needed
- Built-in PostgreSQL features
- Atomic with transaction

---

## References

- PostgreSQL Trigger Documentation
- [RFC-0001: Rule Repository](0001-rule-repository.md)
- Event-Driven Architecture patterns

---

## Status

- [ ] RFC Approved
- [ ] Implementation Complete
- [ ] Tests Passing
- [ ] Documentation Updated
- [ ] Released in v1.2.0
