# Rule Engine PostgreSQL - Refactoring & Enhancement Plan

## Overview
Refactor single-file architecture into modular structure and add high-value features for production use.

**Current State:** 197 lines in single `src/lib.rs`
**Target State:** Modular architecture with 10+ modules, 3 new major features

## 📁 New Project Structure

```
src/
├── lib.rs                          # Entry point + pg_module_magic (minimal)
├── api/
│   ├── mod.rs                      # Public API module
│   ├── health.rs                   # Health check & version functions
│   └── engine.rs                   # Main engine API functions
├── core/
│   ├── mod.rs                      # Core logic module
│   ├── facts.rs                    # Facts <-> JSON conversion
│   ├── rules.rs                    # Rule parsing & validation
│   └── executor.rs                 # Engine execution logic
├── cache/
│   ├── mod.rs                      # Caching module
│   └── rule_cache.rs               # Thread-safe rule cache (LRU)
├── monitoring/
│   ├── mod.rs                      # Monitoring module
│   ├── metrics.rs                  # Performance metrics tracking
│   └── stats.rs                    # Statistics aggregation
├── validation/
│   ├── mod.rs                      # Validation module
│   ├── input.rs                    # Input validation logic
│   └── limits.rs                   # Size limits & constraints
├── batch/
│   ├── mod.rs                      # Batch processing module
│   └── processor.rs                # Batch execution logic
└── error/
    ├── mod.rs                      # Error handling module
    └── codes.rs                    # Error codes & formatting
```

## 🎯 Phase 1: Foundation Refactoring (Week 1)

### Task 1.1: Extract Error Handling Module
**Duration:** 2-3 hours
**Priority:** HIGH

**Steps:**
1. Create `src/error/` directory structure
2. Move error codes to `src/error/codes.rs`
3. Move `create_error_response` to `src/error/mod.rs`
4. Add error types enum for better type safety
5. Update imports in `lib.rs`

**New Functions:**
```rust
// src/error/codes.rs
pub struct ErrorCode {
    pub code: &'static str,
    pub default_message: &'static str,
}

pub const EMPTY_FACTS: ErrorCode = ErrorCode { ... };
```

### Task 1.2: Extract Core Logic Module
**Duration:** 4-6 hours
**Priority:** HIGH

**Steps:**
1. Create `src/core/` directory structure
2. Extract facts conversion to `src/core/facts.rs`:
   - `engine_value_to_json()`
   - `facts_to_json()`
   - `json_to_facts()`
3. Extract rule parsing to `src/core/rules.rs`:
   - Rule parsing logic
   - Rule validation
4. Extract execution to `src/core/executor.rs`:
   - Engine initialization
   - Action handlers
   - Rule execution
5. Update imports

**New Module Interfaces:**
```rust
// src/core/facts.rs
pub fn json_to_facts(json_str: &str) -> Result<Facts, String>
pub fn facts_to_json(facts: &Facts) -> Result<String, String>

// src/core/rules.rs
pub fn parse_and_validate_rules(grl: &str) -> Result<Vec<Rule>, String>

// src/core/executor.rs
pub fn execute_rules(facts: &Facts, rules: Vec<Rule>) -> Result<(), String>
```

### Task 1.3: Extract API Layer
**Duration:** 2-3 hours
**Priority:** HIGH

**Steps:**
1. Create `src/api/` directory structure
2. Move health check functions to `src/api/health.rs`:
   - `rule_engine_health_check()`
   - `rule_engine_version()`
3. Move main function to `src/api/engine.rs`:
   - `run_rule_engine()`
4. Update `src/lib.rs` to re-export functions

**New Structure:**
```rust
// src/lib.rs (simplified)
mod api;
mod core;
mod error;

pub use api::health::*;
pub use api::engine::*;

pgrx::pg_module_magic!();
```

### Task 1.4: Extract Validation Module
**Duration:** 2-3 hours
**Priority:** MEDIUM

**Steps:**
1. Create `src/validation/` directory
2. Extract validation logic to `src/validation/input.rs`
3. Extract size limits to `src/validation/limits.rs`
4. Add reusable validation functions

**New Functions:**
```rust
// src/validation/input.rs
pub fn validate_facts_input(json: &str) -> Result<(), String>
pub fn validate_rules_input(grl: &str) -> Result<(), String>

// src/validation/limits.rs
pub const MAX_INPUT_SIZE: usize = 1_000_000;
pub fn check_size_limit(input: &str, limit: usize) -> Result<(), String>
```

## 🚀 Phase 2: Performance Features (Week 2)

### Task 2.1: Implement Rule Caching
**Duration:** 6-8 hours
**Priority:** HIGH
**Impact:** 10-50x performance improvement for repeated rules

**Steps:**
1. Create `src/cache/` directory
2. Implement LRU cache in `src/cache/rule_cache.rs`:
   - Thread-safe cache using `Arc<Mutex<LruCache>>`
   - Cache key: SHA256 hash of GRL rules
   - Cache value: Parsed rules
   - Max cache size: 100 entries
3. Add cache statistics tracking
4. Implement cache invalidation

**New Dependencies:**
```toml
lru = "0.12"
sha2 = "0.10"
```

**New Functions:**
```rust
#[pgrx::pg_extern]
pub fn run_rule_engine_cached(
    facts_json: &str,
    rules_grl: &str,
    cache_key: Option<&str>
) -> String

#[pgrx::pg_extern]
pub fn clear_rule_cache() -> String

#[pgrx::pg_extern]
pub fn rule_cache_stats() -> String
// Returns: { "size": 45, "hits": 1234, "misses": 56, "hit_rate": 0.95 }
```

**Benefits:**
- Avoid re-parsing same rules multiple times
- Significant speedup for trigger-based usage
- Memory efficient with LRU eviction

### Task 2.2: Implement Batch Processing
**Duration:** 6-8 hours
**Priority:** HIGH
**Impact:** 5-10x throughput for bulk operations

**Steps:**
1. Create `src/batch/` directory
2. Implement batch processor in `src/batch/processor.rs`:
   - Parse rules once, apply to multiple facts
   - Parallel processing with Rayon (optional)
   - Error isolation (one failure doesn't stop batch)
3. Add batch result aggregation

**New Dependencies:**
```toml
rayon = { version = "1.8", optional = true }
```

**New Functions:**
```rust
#[pgrx::pg_extern]
pub fn run_rule_engine_batch(
    facts_array: Vec<String>,
    rules_grl: &str
) -> Vec<String>

#[pgrx::pg_extern]
pub fn run_rule_engine_batch_parallel(
    facts_array: Vec<String>,
    rules_grl: &str,
    thread_count: i32
) -> Vec<String>
```

**SQL Usage:**
```sql
-- Process 1000 records in one call
SELECT run_rule_engine_batch(
    ARRAY(SELECT data::TEXT FROM orders WHERE status = 'pending' LIMIT 1000),
    (SELECT rules FROM rule_definitions WHERE name = 'order_validation')
);
```

### Task 2.3: Add Performance Monitoring
**Duration:** 4-6 hours
**Priority:** MEDIUM
**Impact:** Observability for production debugging

**Steps:**
1. Create `src/monitoring/` directory
2. Implement metrics tracking in `src/monitoring/metrics.rs`:
   - Execution count
   - Average/min/max execution time
   - Error rate
   - Cache statistics
3. Implement stats aggregation in `src/monitoring/stats.rs`
4. Add thread-safe global metrics collector

**New Dependencies:**
```toml
lazy_static = "1.4"
```

**New Functions:**
```rust
#[pgrx::pg_extern]
pub fn rule_engine_stats() -> String
// Returns: {
//   "total_executions": 12345,
//   "avg_time_ms": 2.3,
//   "max_time_ms": 45.2,
//   "error_rate": 0.02,
//   "cache_hit_rate": 0.85
// }

#[pgrx::pg_extern]
pub fn rule_engine_stats_detailed() -> pgrx::TableIterator<'static, (
    name: String,
    executions: i64,
    avg_time_ms: f64,
    errors: i64
)>

#[pgrx::pg_extern]
pub fn reset_rule_engine_stats() -> String
```

## 🎨 Phase 3: Developer Experience (Week 3)

### Task 3.1: Rule Validation Function
**Duration:** 3-4 hours
**Priority:** HIGH
**Impact:** Catch errors before runtime

**Steps:**
1. Add validation in `src/core/rules.rs`
2. Implement syntax checking
3. Add semantic validation (undefined variables, etc.)

**New Functions:**
```rust
#[pgrx::pg_extern]
pub fn validate_grl_rules(rules_grl: &str) -> String
// Returns: {
//   "valid": true,
//   "rule_count": 5,
//   "warnings": ["Rule 'Discount' has no salience"],
//   "errors": []
// }

#[pgrx::pg_extern]
pub fn validate_grl_syntax(rules_grl: &str) -> bool
```

**SQL Usage:**
```sql
-- Validate before inserting
INSERT INTO business_rules (name, grl_definition)
SELECT 'NewRule', $rule$
  rule "Test" { when x > 5 then y = 10; }
$rule$
WHERE (validate_grl_rules($rule$...$rule$)::jsonb->>'valid')::boolean;
```

### Task 3.2: Rule Execution Explainer
**Duration:** 6-8 hours
**Priority:** MEDIUM
**Impact:** Debugging and understanding rule behavior

**Steps:**
1. Add execution tracing in `src/core/executor.rs`
2. Capture rule firing order
3. Record fact changes per rule
4. Build execution report

**New Functions:**
```rust
#[pgrx::pg_extern]
pub fn explain_rule_execution(
    facts_json: &str,
    rules_grl: &str
) -> String
// Returns: {
//   "rules_parsed": 3,
//   "rules_fired": 2,
//   "execution_order": ["HighPriority", "Standard"],
//   "changes": {
//     "HighPriority": {"Order.discount": {"from": 0, "to": 0.15}},
//     "Standard": {"Order.status": {"from": "pending", "to": "approved"}}
//   },
//   "rules_not_fired": ["LowPriority"],
//   "execution_time_ms": 1.23
// }
```

### Task 3.3: Enhanced Error Messages
**Duration:** 2-3 hours
**Priority:** MEDIUM

**Steps:**
1. Add detailed error context in `src/error/mod.rs`
2. Include line numbers for GRL syntax errors
3. Add helpful suggestions for common mistakes

**Example:**
```json
{
  "error": "Invalid GRL syntax: unexpected token 'thne' at line 3",
  "error_code": "ERR008",
  "line": 3,
  "column": 5,
  "suggestion": "Did you mean 'then'?",
  "context": "rule \"Test\" { when x > 5 thne y = 10; }",
  "timestamp": "2025-12-03T10:00:00Z"
}
```

## 🔧 Phase 4: Advanced Features (Week 4)

### Task 4.1: Rule Timeout Protection
**Duration:** 4-5 hours
**Priority:** HIGH
**Impact:** Prevent infinite loops/long-running rules

**Steps:**
1. Implement timeout wrapper in `src/core/executor.rs`
2. Use thread with timeout or tokio runtime
3. Add configurable default timeout

**New Functions:**
```rust
#[pgrx::pg_extern]
pub fn run_rule_engine_with_timeout(
    facts_json: &str,
    rules_grl: &str,
    timeout_ms: i32
) -> String
// Returns error after timeout or normal result

#[pgrx::pg_extern]
pub fn set_default_timeout(timeout_ms: i32) -> String
```

### Task 4.2: JSONB Native Support
**Duration:** 3-4 hours
**Priority:** MEDIUM
**Impact:** Better PostgreSQL integration

**Steps:**
1. Add JSONB input/output support
2. Optimize for JSONB columns (no string conversion)

**New Functions:**
```rust
#[pgrx::pg_extern]
pub fn run_rule_engine_jsonb(
    facts_jsonb: pgrx::JsonB,
    rules_grl: &str
) -> pgrx::JsonB

#[pgrx::pg_extern]
pub fn run_rule_engine_batch_jsonb(
    facts_array: Vec<pgrx::JsonB>,
    rules_grl: &str
) -> Vec<pgrx::JsonB>
```

**SQL Usage:**
```sql
-- Direct JSONB usage (no casting)
UPDATE orders
SET data = run_rule_engine_jsonb(data, $rules$...$rules$)
WHERE status = 'pending';
```

### Task 4.3: Rule Testing Framework
**Duration:** 6-8 hours
**Priority:** LOW
**Impact:** Quality assurance for business rules

**Steps:**
1. Create `src/testing/` module
2. Implement test case runner
3. Add assertion framework

**New Functions:**
```rust
#[pgrx::pg_extern]
pub fn test_rule(
    rule_grl: &str,
    test_cases: &str // JSON: [{"input": {...}, "expected": {...}}, ...]
) -> String
// Returns: {
//   "passed": 4,
//   "failed": 1,
//   "results": [
//     {"case": 1, "passed": true},
//     {"case": 2, "passed": false, "diff": {...}}
//   ]
// }
```

## 📊 Phase 5: Testing & Documentation (Week 5)

### Task 5.1: Unit Tests
**Duration:** 8-10 hours
**Priority:** HIGH

**Coverage:**
- Each module with >80% coverage
- Integration tests for new features
- Performance benchmarks

**Files to create:**
```
tests/
├── unit/
│   ├── error_tests.rs
│   ├── facts_tests.rs
│   ├── rules_tests.rs
│   ├── cache_tests.rs
│   └── batch_tests.rs
├── integration/
│   ├── end_to_end_tests.rs
│   └── performance_tests.rs
└── fixtures/
    ├── sample_rules.grl
    └── sample_facts.json
```

### Task 5.2: Update Documentation
**Duration:** 4-6 hours
**Priority:** HIGH

**Updates needed:**
1. Update [README.md](README.md) with new functions
2. Create `MIGRATION_GUIDE.md` for v1.x to v2.0
3. Add performance tuning guide
4. Add examples for each new feature

### Task 5.3: Benchmarks
**Duration:** 3-4 hours
**Priority:** MEDIUM

**Benchmarks to add:**
- Cache hit vs miss performance
- Batch vs sequential processing
- Single-threaded vs parallel batch
- Before/after refactoring comparison

## 📦 Dependencies Updates

### New Dependencies
```toml
[dependencies]
# Existing
pgrx = { version = "0.16.1", features = ["pg16"] }
rust-rule-engine = "1.6"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
chrono = { version = "0.4", features = ["serde"] }

# New
lru = "0.12"                      # LRU cache
sha2 = "0.10"                     # Cache key hashing
lazy_static = "1.4"               # Global metrics
parking_lot = "0.12"              # Better mutexes

# Optional
rayon = { version = "1.8", optional = true }  # Parallel processing

[features]
default = ["pg16"]
pg13 = ["pgrx/pg13"]
pg14 = ["pgrx/pg14"]
pg15 = ["pgrx/pg15"]
pg16 = ["pgrx/pg16"]
pg17 = ["pgrx/pg17"]
parallel = ["rayon"]              # Enable parallel batch processing
pg_test = []
```

## 🎯 Success Metrics

### Performance Targets
- **Cache hit ratio**: >80% for typical workloads
- **Batch processing**: 5-10x faster than sequential
- **Memory usage**: <50MB for cache + metrics
- **Rule parsing**: <1ms for cached rules

### Code Quality Targets
- **Test coverage**: >80%
- **Compilation time**: <60s
- **Binary size**: <5MB
- **Module count**: 15-20 modules

### Feature Adoption
- Provide migration examples for each new feature
- Document performance improvements
- Create SQL examples for common patterns

## 🚨 Breaking Changes (v2.0.0)

### None Expected
All new features are additive. Existing `run_rule_engine()` function remains unchanged.

### Optional Breaking Changes (Consider for v3.0)
- Make JSONB the default input type (breaking for TEXT users)
- Remove string-based APIs in favor of JSONB
- Add required timeout parameter

## 📅 Timeline Summary

| Phase | Duration | Key Deliverables |
|-------|----------|------------------|
| Phase 1: Foundation | Week 1 | Modular structure, clean separation |
| Phase 2: Performance | Week 2 | Caching, batch processing, monitoring |
| Phase 3: DX | Week 3 | Validation, debugging, better errors |
| Phase 4: Advanced | Week 4 | Timeouts, JSONB, testing framework |
| Phase 5: Polish | Week 5 | Tests, docs, benchmarks |

**Total Time:** 5 weeks (part-time) or 2-3 weeks (full-time)

## 🔄 Migration Strategy

### For Users

**v1.0.0 → v2.0.0 (No breaking changes)**
```sql
-- Existing code works as-is
SELECT run_rule_engine(...);

-- Opt-in to new features
SELECT run_rule_engine_cached(...);
SELECT run_rule_engine_batch(...);
```

### For Developers

**Build Process**
```bash
# Before: Single file compilation
cargo build

# After: Multi-module compilation (same command)
cargo build

# New: Enable parallel features
cargo build --features parallel
```

## 🎓 Learning Opportunities

1. **Rust module system**: Proper separation of concerns
2. **PostgreSQL extension APIs**: Advanced pgrx features
3. **Caching strategies**: LRU implementation
4. **Performance optimization**: Batch processing patterns
5. **Observability**: Metrics collection in Rust

## ✅ Sign-off Checklist

Before considering refactoring complete:

- [ ] All modules compile without warnings
- [ ] All existing tests pass
- [ ] New tests added for new features
- [ ] Documentation updated
- [ ] Performance benchmarks show improvement
- [ ] Code reviewed
- [ ] Migration guide created
- [ ] Example SQL queries updated
- [ ] CI/CD pipeline updated
- [ ] Release notes drafted

---

**Version**: 2.0.0-plan
**Created**: 2025-12-03
**Author**: Ton That Vu
**Status**: Draft
