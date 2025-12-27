# Time-Travel Debugging Architecture (v2.0.0)

## Vision
**The world's first rule engine with event-sourced time-travel debugging.**

## Event Sourcing Approach

Instead of storing full snapshots, we store **immutable events** that describe every state change. State at any point can be reconstructed by replaying events from the beginning.

### Advantages:
- **Memory efficient**: Events are small (10-100 bytes each)
- **Complete audit trail**: Nothing is lost, perfect reproducibility
- **Timeline branching**: Easy to create "what-if" scenarios
- **Queryable history**: Can analyze patterns across time

---

## Core Event Types

Every state change in the RETE engine becomes an event:

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ReteEvent {
    // === Working Memory Events ===
    FactInserted {
        step: u64,
        timestamp: i64,
        handle: FactHandle,
        fact_type: String,
        data: serde_json::Value,
    },

    FactModified {
        step: u64,
        timestamp: i64,
        handle: FactHandle,
        old_data: serde_json::Value,
        new_data: serde_json::Value,
        changed_fields: Vec<String>,
    },

    FactRetracted {
        step: u64,
        timestamp: i64,
        handle: FactHandle,
        fact_type: String,
        data: serde_json::Value,  // Store for reconstruction
    },

    // === Rule Evaluation Events ===
    RuleEvaluated {
        step: u64,
        timestamp: i64,
        rule_name: String,
        rule_index: usize,
        matched: bool,
        reason: String,  // "All conditions matched" or "Condition 2 failed: Order.total = 500 < 1000"
        matched_facts: Vec<FactHandle>,
    },

    RuleActivated {
        step: u64,
        timestamp: i64,
        rule_name: String,
        activation_id: u64,
        salience: i32,
        matched_facts: Vec<FactHandle>,
    },

    RuleFired {
        step: u64,
        timestamp: i64,
        rule_name: String,
        activation_id: u64,
        matched_facts: Vec<FactHandle>,
        actions_executed: Vec<String>,  // ["Order.approved = true", "Order.discount = 10"]
    },

    RuleDeactivated {
        step: u64,
        timestamp: i64,
        rule_name: String,
        activation_id: u64,
        reason: String,  // "no-loop", "retracted fact", etc
    },

    // === RETE Network Events ===
    AlphaNodeMatched {
        step: u64,
        node_id: String,
        pattern: String,  // "Order.total > 1000"
        fact_handle: FactHandle,
        matched: bool,
    },

    BetaNodeJoined {
        step: u64,
        node_id: String,
        left_facts: Vec<FactHandle>,
        right_fact: FactHandle,
        joined: bool,
        reason: String,
    },

    // === Agenda Events ===
    AgendaStateSnapshot {
        step: u64,
        pending_activations: Vec<ActivationSnapshot>,
    },

    // === Meta Events ===
    ExecutionStarted {
        timestamp: i64,
        session_id: String,
        rules_count: usize,
        initial_facts_count: usize,
    },

    ExecutionCompleted {
        step: u64,
        timestamp: i64,
        total_rules_fired: usize,
        total_facts_modified: usize,
        duration_ms: i64,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActivationSnapshot {
    pub rule_name: String,
    pub salience: i32,
    pub matched_facts: Vec<FactHandle>,
}
```

---

## Event Store Schema

PostgreSQL tables to store events:

```sql
-- Main event log (append-only, immutable)
CREATE TABLE rule_execution_events (
    id BIGSERIAL PRIMARY KEY,
    session_id TEXT NOT NULL,
    step BIGINT NOT NULL,
    timestamp BIGINT NOT NULL,
    event_type TEXT NOT NULL,  -- 'FactInserted', 'RuleFired', etc
    event_data JSONB NOT NULL,

    -- Indexing for fast queries
    INDEX idx_session_step (session_id, step),
    INDEX idx_session_type (session_id, event_type),
    INDEX idx_timestamp (timestamp)
);

-- Sessions metadata
CREATE TABLE rule_execution_sessions (
    session_id TEXT PRIMARY KEY,
    started_at BIGINT NOT NULL,
    completed_at BIGINT,
    rules_grl TEXT NOT NULL,
    initial_facts JSONB NOT NULL,
    total_steps BIGINT,
    total_events BIGINT,
    status TEXT,  -- 'running', 'completed', 'error'

    INDEX idx_started (started_at)
);

-- Timeline branches (for what-if scenarios)
CREATE TABLE rule_execution_timelines (
    timeline_id TEXT PRIMARY KEY,
    parent_session_id TEXT NOT NULL,
    branched_at_step BIGINT NOT NULL,
    modifications JSONB NOT NULL,  -- {"step": 5, "fact": "Order.total", "value": 1500}
    created_at BIGINT NOT NULL,

    FOREIGN KEY (parent_session_id) REFERENCES rule_execution_sessions(session_id)
);
```

---

## State Reconstruction Algorithm

Rebuild complete engine state at any step by replaying events:

```rust
pub struct StateReconstructor {
    events: Vec<ReteEvent>,
}

impl StateReconstructor {
    /// Reconstruct state at specific step
    pub fn reconstruct_at_step(&self, target_step: u64) -> EngineState {
        let mut state = EngineState::new();

        for event in &self.events {
            if event.step() > target_step {
                break;
            }

            match event {
                ReteEvent::FactInserted { handle, fact_type, data, .. } => {
                    state.working_memory.insert(*handle, fact_type.clone(), data.clone());
                }

                ReteEvent::FactModified { handle, new_data, .. } => {
                    state.working_memory.update(*handle, new_data.clone());
                }

                ReteEvent::FactRetracted { handle, .. } => {
                    state.working_memory.retract(*handle);
                }

                ReteEvent::RuleFired { rule_name, matched_facts, .. } => {
                    state.fired_rules.push(rule_name.clone());
                    state.rule_firings.entry(rule_name.clone())
                        .or_insert_with(Vec::new)
                        .push(*matched_facts);
                }

                // ... handle other events
            }
        }

        state
    }

    /// Fast-forward from one step to another
    pub fn fast_forward(&self, from_state: &mut EngineState, from_step: u64, to_step: u64) {
        for event in &self.events {
            if event.step() <= from_step {
                continue;
            }
            if event.step() > to_step {
                break;
            }

            // Apply event to state
            self.apply_event(from_state, event);
        }
    }
}

#[derive(Debug, Clone)]
pub struct EngineState {
    pub working_memory: HashMap<FactHandle, (String, serde_json::Value)>,
    pub fired_rules: Vec<String>,
    pub rule_firings: HashMap<String, Vec<Vec<FactHandle>>>,
    pub current_step: u64,
}
```

---

## Debugging API (SQL Functions)

### 1. Execute with debugging enabled

```sql
-- New function with debugging
CREATE FUNCTION run_rule_engine_debug(
    facts_json TEXT,
    rules_grl TEXT
) RETURNS TABLE(
    session_id TEXT,
    total_steps BIGINT,
    total_events BIGINT,
    result JSONB
);

-- Example usage
SELECT * FROM run_rule_engine_debug(
    '{"Order": {"total": 500, "country": "US"}}',
    'rule "HighValue" { when Order.total > 1000 then Order.approved = true; }'
);
-- Returns: session_id = "abc123", total_steps = 3, total_events = 8
```

### 2. Query: Why didn't a rule fire?

```sql
CREATE FUNCTION debug_why_rule_not_fired(
    session_id TEXT,
    rule_name TEXT
) RETURNS TABLE(
    step BIGINT,
    condition_index INT,
    condition_text TEXT,
    matched BOOLEAN,
    reason TEXT
);

-- Example
SELECT * FROM debug_why_rule_not_fired('abc123', 'HighValue');
-- Returns:
-- step | condition_index | condition_text      | matched | reason
-- -----|-----------------|---------------------|---------|---------------------------
-- 1    | 0               | Order.total > 1000  | false   | Order.total = 500 < 1000
```

### 3. Query: Show execution timeline

```sql
CREATE FUNCTION debug_show_timeline(
    session_id TEXT,
    from_step BIGINT DEFAULT 0,
    to_step BIGINT DEFAULT NULL
) RETURNS TABLE(
    step BIGINT,
    event_type TEXT,
    description TEXT,
    details JSONB
);

-- Example
SELECT * FROM debug_show_timeline('abc123');
-- Returns:
-- step | event_type    | description                    | details
-- -----|---------------|--------------------------------|------------------
-- 0    | ExecutionStarted | Session started             | {"rules": 1, "facts": 1}
-- 1    | FactInserted  | Inserted Order fact            | {"total": 500}
-- 2    | RuleEvaluated | HighValue: NOT MATCHED         | {"reason": "total < 1000"}
-- 3    | ExecutionCompleted | Session completed         | {"duration_ms": 5}
```

### 4. Query: Show state at step

```sql
CREATE FUNCTION debug_state_at_step(
    session_id TEXT,
    step BIGINT
) RETURNS TABLE(
    working_memory JSONB,
    pending_activations JSONB,
    fired_rules TEXT[]
);

-- Example
SELECT * FROM debug_state_at_step('abc123', 2);
-- Returns full state reconstruction at step 2
```

### 5. Query: Compare two steps

```sql
CREATE FUNCTION debug_compare_steps(
    session_id TEXT,
    step_a BIGINT,
    step_b BIGINT
) RETURNS TABLE(
    field TEXT,
    value_at_step_a JSONB,
    value_at_step_b JSONB,
    changed BOOLEAN
);
```

### 6. What-if scenario: Branch timeline

```sql
CREATE FUNCTION debug_branch_timeline(
    parent_session_id TEXT,
    branch_at_step BIGINT,
    modifications JSONB  -- {"Order.total": 1500}
) RETURNS TEXT;  -- Returns new timeline_id

-- Example
SELECT debug_branch_timeline(
    'abc123',
    1,
    '{"Order.total": 1500}'::jsonb
);
-- Returns: "timeline_xyz456"

-- Then replay with modifications
SELECT * FROM debug_replay_timeline('timeline_xyz456');
-- Shows how execution would differ with Order.total = 1500
```

### 7. Replay in slow motion

```sql
CREATE FUNCTION debug_replay_slow(
    session_id TEXT,
    delay_ms INT DEFAULT 1000
) RETURNS TABLE(
    step BIGINT,
    event_type TEXT,
    description TEXT,
    state_snapshot JSONB
);

-- Returns one row per step, application can display step-by-step
```

---

## Implementation Plan

### Phase 1: Event Capture (Core)
**Files to create:**
- `src/debug/events.rs` - Event type definitions
- `src/debug/event_store.rs` - In-memory event storage
- `src/debug/mod.rs` - Module setup

**Files to modify:**
- `src/core/executor.rs` - Inject event recording
- `src/api/engine.rs` - Add `run_rule_engine_debug()` function

**What it does:**
- Capture all RETE events during execution
- Store in memory for now (PostgreSQL storage in Phase 2)
- Return events as JSONB array

### Phase 2: PostgreSQL Persistence
**Files to create:**
- `src/debug/pg_store.rs` - PostgreSQL event storage
- `migrations/rule_engine_postgre_extensions--1.7.0--2.0.0.sql`

**What it does:**
- Persist events to PostgreSQL tables
- Session management
- Event indexing for fast queries

### Phase 3: State Reconstruction
**Files to create:**
- `src/debug/reconstructor.rs` - State rebuilding from events
- `src/debug/state.rs` - EngineState structure

**Files to modify:**
- `src/api/debug.rs` - Debug query functions

**What it does:**
- Rebuild engine state at any step
- `debug_state_at_step()` SQL function
- `debug_compare_steps()` SQL function

### Phase 4: Rule Analysis
**Files to create:**
- `src/debug/analyzer.rs` - Analyze why rules fired/didn't fire

**SQL functions:**
- `debug_why_rule_not_fired()`
- `debug_show_timeline()`

### Phase 5: Timeline Branching
**Files to create:**
- `src/debug/timeline.rs` - Timeline branching logic

**SQL functions:**
- `debug_branch_timeline()`
- `debug_replay_timeline()`

### Phase 6: Testing & Documentation
- Comprehensive tests
- Wiki documentation
- Example use cases

---

## Performance Considerations

### Event Volume Estimation:
- **Simple rule execution** (10 facts, 5 rules): ~50-100 events
- **Complex execution** (1000 facts, 100 rules): ~10,000-50,000 events
- **Event size**: ~100-200 bytes each
- **Memory**: 1-10 MB per session (acceptable!)

### Optimization Strategies:
1. **Lazy loading**: Only load events when debugging is requested
2. **Event compaction**: Merge consecutive FactModified events
3. **Selective capture**: Capture only key events by default, detailed events on demand
4. **Compression**: Compress event_data JSONB in PostgreSQL
5. **Retention policy**: Auto-delete old sessions after 30 days

### Debug Mode Toggle:
```sql
-- Disable debugging for production (zero overhead)
SET rule_engine.debug_mode = 'off';

-- Enable detailed debugging
SET rule_engine.debug_mode = 'detailed';

-- Enable lightweight debugging (only key events)
SET rule_engine.debug_mode = 'lightweight';
```

---

## Example Use Case: Debugging a Loan Approval System

```sql
-- 1. Run with debugging
SELECT run_rule_engine_debug(
    '{"Applicant": {"age": 25, "income": 45000, "credit_score": 650}}',
    '
    rule "HighIncome" salience 100 {
        when Applicant.income > 50000
        then Applicant.approved = true;
    }
    rule "GoodCredit" salience 50 {
        when Applicant.credit_score > 700
        then Applicant.approved = true;
    }
    '
) AS result;
-- Returns: session_id = "loan_001"

-- 2. Check why applicant wasn't approved
SELECT * FROM debug_why_rule_not_fired('loan_001', 'HighIncome');
-- Returns: "Applicant.income = 45000 < 50000"

SELECT * FROM debug_why_rule_not_fired('loan_001', 'GoodCredit');
-- Returns: "Applicant.credit_score = 650 < 700"

-- 3. What if we lower income threshold?
SELECT debug_branch_timeline(
    'loan_001',
    0,
    '{"_rule_modification": {"HighIncome": {"condition": "Applicant.income > 40000"}}}'::jsonb
);
-- Returns: "timeline_loan_001_alt1"

SELECT * FROM debug_replay_timeline('timeline_loan_001_alt1');
-- Shows: HighIncome rule WOULD fire with lower threshold

-- 4. Show complete timeline
SELECT * FROM debug_show_timeline('loan_001');
```

---

## Future Enhancements (v2.1.0+)

1. **Visual Timeline UI**: Web-based UI to visualize execution
2. **Performance Profiling**: Track which rules are slowest
3. **Pattern Mining**: "Show me all sessions where rule X didn't fire"
4. **Distributed Tracing**: Correlate with external systems
5. **AI-Powered Analysis**: "Why was this applicant rejected?" → Natural language explanation

---

## Summary

This event sourcing approach provides:

✅ **Zero overhead when disabled**
✅ **Complete audit trail**
✅ **Time-travel to any point**
✅ **What-if scenario analysis**
✅ **Scalable to large rule sets**
✅ **SQL-queryable history**

**This will be the world's first rule engine with true time-travel debugging.**
