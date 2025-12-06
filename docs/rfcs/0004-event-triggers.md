# RFC-0004: Event Triggers - Automatic Rule Execution

- **Status:** Draft
- **Author:** Rule Engine Team
- **Created:** 2025-12-06
- **Updated:** 2025-12-06
- **Phase:** 4.1 (Integration & Scalability)
- **Priority:** P1 - High

---

## Summary

Implement automatic rule execution triggered by PostgreSQL events (INSERT, UPDATE, DELETE) on tables, enabling reactive business logic without application code changes.

---

## Motivation

Currently, rules must be executed explicitly via `run_rule_engine()` or `rule_execute_by_name()`. This requires:
- Application code to call rule engine
- Manual orchestration of when rules run
- Tight coupling between app and rule execution

### Use Cases

1. **Audit & Compliance:** Auto-calculate risk scores when customer data changes
2. **Data Enrichment:** Auto-populate derived fields when records inserted
3. **Real-time Alerts:** Trigger notifications when anomalies detected
4. **Workflow Automation:** Auto-assign tasks when order status changes
5. **Cache Invalidation:** Update materialized views when source data changes

---

## Detailed Design

### Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                   Application Layer                      │
│         (Inserts/Updates data as normal)                 │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│              PostgreSQL Table                            │
│         INSERT/UPDATE/DELETE operations                  │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼ (Trigger fires)
┌─────────────────────────────────────────────────────────┐
│           Rule Engine Trigger Handler                    │
│  - Fetch rule configuration                              │
│  - Build facts from NEW/OLD row                          │
│  - Execute rule                                           │
│  - Apply results back to row or side effects             │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│              Rule Execution Results                      │
│  - Modified row data                                     │
│  - Side effects (notifications, logs, etc.)              │
└─────────────────────────────────────────────────────────┘
```

### Database Schema

```sql
-- Rule trigger configurations
CREATE TABLE rule_triggers (
    id SERIAL PRIMARY KEY,
    trigger_name TEXT NOT NULL UNIQUE,
    table_name TEXT NOT NULL,
    rule_name TEXT NOT NULL REFERENCES rule_definitions(name) ON DELETE CASCADE,
    
    -- Trigger configuration
    trigger_event TEXT NOT NULL, -- 'INSERT', 'UPDATE', 'DELETE', 'INSERT OR UPDATE'
    trigger_timing TEXT NOT NULL DEFAULT 'BEFORE', -- 'BEFORE', 'AFTER'
    
    -- Fact mapping
    fact_mapping JSONB NOT NULL, -- Maps table columns to fact structure
    
    -- Execution mode
    execution_mode TEXT NOT NULL DEFAULT 'sync', -- 'sync', 'async'
    
    -- Result handling
    apply_changes_to_row BOOLEAN NOT NULL DEFAULT true, -- Apply rule results back to row
    side_effect_handler TEXT, -- Optional function to call with results
    
    -- Filtering
    when_condition TEXT, -- Optional SQL condition (e.g., 'NEW.amount > 100')
    
    -- Status
    is_enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_by TEXT,
    
    CONSTRAINT valid_event CHECK (trigger_event IN ('INSERT', 'UPDATE', 'DELETE', 'INSERT OR UPDATE', 'INSERT OR UPDATE OR DELETE')),
    CONSTRAINT valid_timing CHECK (trigger_timing IN ('BEFORE', 'AFTER')),
    CONSTRAINT valid_execution_mode CHECK (execution_mode IN ('sync', 'async'))
);

CREATE INDEX idx_rule_triggers_table ON rule_triggers(table_name);
CREATE INDEX idx_rule_triggers_enabled ON rule_triggers(is_enabled);

-- Trigger execution history
CREATE TABLE rule_trigger_executions (
    id BIGSERIAL PRIMARY KEY,
    trigger_id INTEGER NOT NULL REFERENCES rule_triggers(id) ON DELETE CASCADE,
    
    -- Execution details
    executed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    duration_ms NUMERIC(10, 2) NOT NULL,
    success BOOLEAN NOT NULL,
    error_message TEXT,
    
    -- Data snapshot
    facts_before JSONB,
    facts_after JSONB,
    
    -- Context
    table_operation TEXT, -- 'INSERT', 'UPDATE', 'DELETE'
    row_id TEXT, -- Primary key of affected row
    
    -- Performance tracking
    expires_at TIMESTAMP NOT NULL DEFAULT NOW() + INTERVAL '30 days'
);

CREATE INDEX idx_trigger_exec_trigger ON rule_trigger_executions(trigger_id);
CREATE INDEX idx_trigger_exec_time ON rule_trigger_executions(executed_at DESC);
CREATE INDEX idx_trigger_exec_expires ON rule_trigger_executions(expires_at);

-- Async execution queue (for async mode)
CREATE TABLE rule_trigger_queue (
    id BIGSERIAL PRIMARY KEY,
    trigger_id INTEGER NOT NULL REFERENCES rule_triggers(id) ON DELETE CASCADE,
    
    -- Queue status
    status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'processing', 'completed', 'failed'
    
    -- Execution data
    facts_json JSONB NOT NULL,
    table_operation TEXT NOT NULL,
    row_id TEXT,
    
    -- Scheduling
    queued_at TIMESTAMP NOT NULL DEFAULT NOW(),
    scheduled_for TIMESTAMP NOT NULL DEFAULT NOW(),
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    
    -- Retry logic
    retry_count INTEGER NOT NULL DEFAULT 0,
    max_retries INTEGER NOT NULL DEFAULT 3,
    error_message TEXT,
    
    CONSTRAINT valid_status CHECK (status IN ('pending', 'processing', 'completed', 'failed'))
);

CREATE INDEX idx_trigger_queue_status ON rule_trigger_queue(status, scheduled_for);
CREATE INDEX idx_trigger_queue_trigger ON rule_trigger_queue(trigger_id);
```

### Core Trigger Function

```sql
-- Main trigger handler function
CREATE OR REPLACE FUNCTION rule_engine_trigger_handler()
RETURNS TRIGGER AS $$
DECLARE
    trigger_config RECORD;
    facts JSONB;
    result JSONB;
    start_time TIMESTAMP;
    duration_ms NUMERIC;
    row_id TEXT;
BEGIN
    start_time := clock_timestamp();
    
    -- Get trigger configuration
    SELECT * INTO trigger_config
    FROM rule_triggers
    WHERE table_name = TG_TABLE_NAME
      AND trigger_event = TG_OP
      AND is_enabled = true
    LIMIT 1;
    
    -- No enabled trigger found
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;
    
    -- Check when condition if specified
    IF trigger_config.when_condition IS NOT NULL THEN
        EXECUTE format('SELECT (%s) FROM (SELECT $1.*) AS subq', trigger_config.when_condition)
        INTO STRICT result USING NEW;
        
        IF NOT (result->>0)::BOOLEAN THEN
            RETURN NEW;
        END IF;
    END IF;
    
    -- Build facts from row data using fact_mapping
    facts := rule_engine_build_facts(
        CASE TG_OP
            WHEN 'INSERT' THEN to_jsonb(NEW)
            WHEN 'UPDATE' THEN to_jsonb(NEW)
            WHEN 'DELETE' THEN to_jsonb(OLD)
        END,
        trigger_config.fact_mapping
    );
    
    -- Get row identifier
    row_id := COALESCE(NEW.id::TEXT, OLD.id::TEXT);
    
    -- Execute based on mode
    IF trigger_config.execution_mode = 'sync' THEN
        -- Synchronous execution
        BEGIN
            result := rule_execute_by_name(
                trigger_config.rule_name,
                facts::TEXT
            )::JSONB;
            
            duration_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
            
            -- Log execution
            INSERT INTO rule_trigger_executions (
                trigger_id, duration_ms, success, facts_before, facts_after,
                table_operation, row_id
            ) VALUES (
                trigger_config.id, duration_ms, true, facts, result,
                TG_OP, row_id
            );
            
            -- Apply changes back to row if configured
            IF trigger_config.apply_changes_to_row AND TG_OP IN ('INSERT', 'UPDATE') THEN
                NEW := rule_engine_apply_facts_to_row(NEW, result, trigger_config.fact_mapping);
            END IF;
            
            -- Call side effect handler if specified
            IF trigger_config.side_effect_handler IS NOT NULL THEN
                EXECUTE format('SELECT %s($1, $2)', trigger_config.side_effect_handler)
                USING facts, result;
            END IF;
            
        EXCEPTION WHEN OTHERS THEN
            duration_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
            
            -- Log failure
            INSERT INTO rule_trigger_executions (
                trigger_id, duration_ms, success, error_message, facts_before,
                table_operation, row_id
            ) VALUES (
                trigger_config.id, duration_ms, false, SQLERRM, facts,
                TG_OP, row_id
            );
            
            -- Re-raise error to fail transaction
            RAISE;
        END;
    ELSE
        -- Async execution - queue for later
        INSERT INTO rule_trigger_queue (
            trigger_id, facts_json, table_operation, row_id
        ) VALUES (
            trigger_config.id, facts, TG_OP, row_id
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Helper function to build facts from row data
CREATE OR REPLACE FUNCTION rule_engine_build_facts(
    row_data JSONB,
    mapping JSONB
) RETURNS JSONB AS $$
DECLARE
    facts JSONB := '{}';
    key TEXT;
    value JSONB;
BEGIN
    -- mapping format: {"Entity": {"field1": "column1", "field2": "column2"}}
    FOR key, value IN SELECT * FROM jsonb_each(mapping) LOOP
        facts := jsonb_set(
            facts,
            ARRAY[key],
            (SELECT jsonb_object_agg(fact_key, row_data->col_name)
             FROM jsonb_each_text(value) AS t(fact_key, col_name))
        );
    END LOOP;
    
    RETURN facts;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Helper function to apply facts back to row
CREATE OR REPLACE FUNCTION rule_engine_apply_facts_to_row(
    row_data ANYELEMENT,
    facts JSONB,
    mapping JSONB
) RETURNS ANYELEMENT AS $$
DECLARE
    result ANYELEMENT := row_data;
    entity_key TEXT;
    entity_mapping JSONB;
    fact_key TEXT;
    col_name TEXT;
BEGIN
    -- Reverse mapping: facts -> columns
    FOR entity_key, entity_mapping IN SELECT * FROM jsonb_each(mapping) LOOP
        FOR fact_key, col_name IN SELECT * FROM jsonb_each_text(entity_mapping) LOOP
            IF facts->entity_key->fact_key IS NOT NULL THEN
                -- Use dynamic SQL to set column value
                EXECUTE format('SELECT ($1::jsonb || jsonb_build_object(%L, $2->%L->%L))::text::%s',
                    col_name, entity_key, fact_key, pg_typeof(result))
                INTO result
                USING to_jsonb(result), facts;
            END IF;
        END LOOP;
    END LOOP;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Async worker function (to be called by pg_cron or external worker)
CREATE OR REPLACE FUNCTION rule_engine_process_queue(batch_size INTEGER DEFAULT 10)
RETURNS TABLE (processed INTEGER, succeeded INTEGER, failed INTEGER) AS $$
DECLARE
    queue_item RECORD;
    result JSONB;
    success_count INTEGER := 0;
    fail_count INTEGER := 0;
    total_count INTEGER := 0;
BEGIN
    -- Process batch of pending items
    FOR queue_item IN
        SELECT *
        FROM rule_trigger_queue
        WHERE status = 'pending'
          AND scheduled_for <= NOW()
        ORDER BY queued_at
        LIMIT batch_size
        FOR UPDATE SKIP LOCKED
    LOOP
        total_count := total_count + 1;
        
        -- Mark as processing
        UPDATE rule_trigger_queue
        SET status = 'processing', started_at = NOW()
        WHERE id = queue_item.id;
        
        BEGIN
            -- Execute rule
            SELECT rule_execute_by_name(
                (SELECT rule_name FROM rule_triggers WHERE id = queue_item.trigger_id),
                queue_item.facts_json::TEXT
            )::JSONB INTO result;
            
            -- Mark as completed
            UPDATE rule_trigger_queue
            SET status = 'completed', completed_at = NOW()
            WHERE id = queue_item.id;
            
            success_count := success_count + 1;
            
        EXCEPTION WHEN OTHERS THEN
            -- Handle failure with retry logic
            IF queue_item.retry_count < queue_item.max_retries THEN
                -- Retry with exponential backoff
                UPDATE rule_trigger_queue
                SET status = 'pending',
                    retry_count = retry_count + 1,
                    scheduled_for = NOW() + (POWER(2, retry_count + 1) || ' seconds')::INTERVAL,
                    error_message = SQLERRM
                WHERE id = queue_item.id;
            ELSE
                -- Max retries reached, mark as failed
                UPDATE rule_trigger_queue
                SET status = 'failed',
                    completed_at = NOW(),
                    error_message = SQLERRM
                WHERE id = queue_item.id;
                
                fail_count := fail_count + 1;
            END IF;
        END;
    END LOOP;
    
    RETURN QUERY SELECT total_count, success_count, fail_count;
END;
$$ LANGUAGE plpgsql;
```

### API Functions

#### Function 1: `rule_trigger_create(trigger_name TEXT, table_name TEXT, rule_name TEXT, trigger_event TEXT, fact_mapping JSONB, options JSONB DEFAULT '{}') → INTEGER`

**Purpose:** Create a new rule trigger

**Parameters:**
- `trigger_name` (TEXT): Unique trigger name
- `table_name` (TEXT): Target table name
- `rule_name` (TEXT): Rule to execute
- `trigger_event` (TEXT): Event type ('INSERT', 'UPDATE', 'DELETE', 'INSERT OR UPDATE')
- `fact_mapping` (JSONB): Column to fact mapping
- `options` (JSONB): Additional options (timing, execution_mode, when_condition, etc.)

**Example:**
```sql
-- Auto-calculate discount when order inserted/updated
SELECT rule_trigger_create(
    'auto_discount',
    'orders',
    'discount_calculator',
    'INSERT OR UPDATE',
    '{"Order": {"Amount": "amount", "Discount": "discount", "CustomerId": "customer_id"}}',
    '{"trigger_timing": "BEFORE", "execution_mode": "sync", "when_condition": "NEW.amount > 0"}'
);
```

#### Function 2: `rule_trigger_enable(trigger_name TEXT) → BOOLEAN`

**Purpose:** Enable a trigger

#### Function 3: `rule_trigger_disable(trigger_name TEXT) → BOOLEAN`

**Purpose:** Disable a trigger without deleting it

#### Function 4: `rule_trigger_delete(trigger_name TEXT) → BOOLEAN`

**Purpose:** Delete a trigger and its associated PostgreSQL trigger

#### Function 5: `rule_trigger_list(table_name TEXT DEFAULT NULL) → TABLE`

**Purpose:** List all triggers, optionally filtered by table

**Example:**
```sql
-- List all triggers
SELECT * FROM rule_trigger_list();

-- List triggers for specific table
SELECT * FROM rule_trigger_list('orders');
```

#### Function 6: `rule_trigger_stats(trigger_name TEXT, time_range INTERVAL DEFAULT '24 hours') → JSON`

**Purpose:** Get execution statistics for a trigger

**Example:**
```sql
SELECT rule_trigger_stats('auto_discount', '7 days');

-- Returns:
{
  "total_executions": 15420,
  "success_rate": 99.8,
  "avg_duration_ms": 2.5,
  "last_executed": "2025-12-06T10:30:00Z",
  "errors": 30
}
```

---

## Examples

### Example 1: Auto-Calculate Derived Fields

```sql
-- Create rule for tax calculation
SELECT rule_save(
    'tax_calculator',
    'rule "TaxCalc" {
        when Order.Subtotal > 0
        then Order.Tax = Order.Subtotal * 0.1;
             Order.Total = Order.Subtotal + Order.Tax;
    }',
    '1.0.0'
);

-- Create trigger on orders table
SELECT rule_trigger_create(
    'auto_tax',
    'orders',
    'tax_calculator',
    'INSERT OR UPDATE',
    '{
        "Order": {
            "Subtotal": "subtotal",
            "Tax": "tax",
            "Total": "total"
        }
    }',
    '{"trigger_timing": "BEFORE", "apply_changes_to_row": true}'
);

-- Now insertions auto-calculate tax and total
INSERT INTO orders (customer_id, subtotal)
VALUES (123, 100.00);
-- Row will have tax = 10.00 and total = 110.00 automatically!

SELECT * FROM orders WHERE customer_id = 123;
-- | id | customer_id | subtotal | tax   | total  |
-- | 1  | 123         | 100.00   | 10.00 | 110.00 |
```

### Example 2: Audit & Compliance

```sql
-- Create risk scoring rule
SELECT rule_save(
    'risk_scorer',
    'rule "HighRisk" {
        when Customer.TransactionAmount > 10000
        then Customer.RiskScore = "HIGH";
             Customer.RequiresReview = true;
    }',
    '1.0.0'
);

-- Trigger on customer transactions
SELECT rule_trigger_create(
    'risk_check',
    'transactions',
    'risk_scorer',
    'INSERT',
    '{
        "Customer": {
            "TransactionAmount": "amount",
            "RiskScore": "risk_score",
            "RequiresReview": "requires_review"
        }
    }',
    '{"execution_mode": "async"}'  -- Process asynchronously
);

-- High-value transactions automatically flagged for review
INSERT INTO transactions (customer_id, amount)
VALUES (456, 15000);

-- Check queue
SELECT * FROM rule_trigger_queue WHERE status = 'pending';
```

### Example 3: Real-time Notifications

```sql
-- Create side effect handler
CREATE OR REPLACE FUNCTION send_alert(facts_before JSONB, facts_after JSONB)
RETURNS VOID AS $$
BEGIN
    IF (facts_after->'Order'->>'Status')::TEXT = 'shipped' THEN
        -- Send notification (could call pg_notify, webhook, etc.)
        PERFORM pg_notify('order_shipped', jsonb_build_object(
            'order_id', facts_after->'Order'->>'Id',
            'customer_id', facts_after->'Order'->>'CustomerId'
        )::TEXT);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create rule
SELECT rule_save(
    'order_status_handler',
    'rule "StatusChange" {
        when Order.Status == "shipped"
        then Order.NotificationSent = true;
    }',
    '1.0.0'
);

-- Create trigger with side effect
SELECT rule_trigger_create(
    'order_notification',
    'orders',
    'order_status_handler',
    'UPDATE',
    '{"Order": {"Status": "status", "NotificationSent": "notification_sent"}}',
    jsonb_build_object(
        'side_effect_handler', 'send_alert',
        'when_condition', 'NEW.status != OLD.status'
    )
);
```

---

## Performance Considerations

- **Sync Mode:** < 5ms overhead per trigger
- **Async Mode:** < 1ms overhead (just queue insertion)
- **Queue Processing:** 1000+ items/second
- **Indexing:** Proper indexes on trigger configuration tables
- **Connection Pooling:** Reuse rule engine connections

---

## Security Considerations

- **Permissions:** Only superuser or table owner can create triggers
- **SQL Injection:** All user inputs sanitized
- **Resource Limits:** Max execution time per trigger
- **Audit Trail:** Complete history of trigger executions

---

## Migration Path

Existing applications continue to work. Triggers are opt-in.

```sql
-- Enable on specific tables gradually
SELECT rule_trigger_create(...) WHERE table = 'orders';
-- Test in production with small subset
-- Roll out to more tables
```

---

## Success Metrics

- **Adoption:** 30% of production tables use triggers within 6 months
- **Performance:** < 5ms overhead for sync triggers
- **Reliability:** 99.9% success rate
- **Developer Velocity:** 50% reduction in business logic code

---

## Open Questions

- [ ] Support for row-level vs statement-level triggers?
- [ ] Trigger ordering when multiple triggers on same table?
- [ ] Transaction isolation level handling?
- [ ] Cross-database trigger support?

---

## Changelog

- **2025-12-06:** Initial draft
