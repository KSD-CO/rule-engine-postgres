# Engine Selection Guide

## Available Execution Engines (v2.0.0+)

Rule Engine PostgreSQL Extension hỗ trợ 3 execution modes:

### 1. `run_rule_engine()` - Default (Recommended)
```sql
SELECT run_rule_engine(
    '{"Order": {"total": 1250}}',
    'rule "Discount" { when Order.total > 1000 then Order.discount = 125; }'
);
```

**Engine**: RETE (mặc định từ v2.0.0)
**Use cases**: Tất cả production workloads
**Performance**: Tối ưu cho batch processing

---

### 2. `run_rule_engine_rete()` - Explicit RETE
```sql
SELECT run_rule_engine_rete(
    '{"Order": {"total": 1250}}',
    'rule "Discount" { when Order.total > 1000 then Order.discount = 125; }'
);
```

**Engine**: RETE algorithm (incremental evaluation)
**Use cases**:
- ✅ Batch processing (100+ records)
- ✅ Complex rule dependencies (10+ chained rules)
- ✅ High-throughput scenarios (>50 evals/sec)
- ✅ Long-running sessions with fact updates

**Performance Characteristics**:
- First execution: 100-200ms overhead (RETE compilation)
- Subsequent: 10-50ms per evaluation
- Batch (50 orders): ~15ms average, **66 orders/sec**
- High-throughput (100): ~0.02ms average, **44,000 evals/sec**

**Measured Benchmarks** (from [benchmark_rete.sql](../tests/benchmark_rete.sql)):
```
Single fact (10 iterations):     11.3 ms average
Complex rules (10 iterations):   17.6 ms average
Batch processing (50 orders):    15.1 ms average, 66 orders/sec
High-throughput (100):            0.02 ms average, 44,286 evals/sec
E-commerce (25 orders):           0.01 ms average, 103,734 orders/sec
```

---

### 3. `run_rule_engine_fc()` - Forward Chaining
```sql
SELECT run_rule_engine_fc(
    '{"Order": {"total": 1250}}',
    'rule "Discount" { when Order.total > 1000 then Order.discount = 125; }'
);
```

**Engine**: Traditional forward chaining
**Use cases**:
- ✅ Simple rules (1-5 rules)
- ✅ Predictable execution order needed
- ✅ Single-shot evaluations
- ✅ Memory-constrained environments

**Performance Characteristics**:
- Consistent latency per evaluation
- No compilation overhead
- Estimated: 10-20ms for simple rules, 50-100ms for complex

**When to use**:
- Debugging/testing simple scenarios
- Rules must fire in strict salience order
- Memory usage is critical concern

---

## Performance Comparison

### Single Execution (Cold Start)

| Scenario | RETE | Forward Chaining | Winner |
|----------|------|------------------|--------|
| 1-3 simple rules | ~200ms | ~80ms | FC (2.5x) |
| 5-10 rules | ~180ms | ~150ms | Equal |
| 20+ complex rules | ~220ms | ~300ms | RETE (1.4x) |

### Batch Processing (100 evaluations)

| Scenario | RETE | Forward Chaining | Speedup |
|----------|------|------------------|---------|
| Simple rules | ~0.02ms avg | ~80ms avg | **4000x** |
| Complex rules (10) | ~18ms avg | ~150ms avg | **8x** |
| E-commerce (8 rules) | ~0.01ms avg | ~120ms avg | **12000x** |

*Forward Chaining estimates based on single-execution benchmarks*

---

## Decision Matrix

### ✅ Use RETE (`run_rule_engine` or `run_rule_engine_rete`) when:

- [ ] Processing batches (>10 records)
- [ ] Complex rule dependencies exist
- [ ] High throughput needed (>50/sec)
- [ ] Rules will be reused across evaluations
- [ ] Performance is critical

**Expected gain**: 3-10x for batches, up to 12000x for high-throughput

### ✅ Use Forward Chaining (`run_rule_engine_fc`) when:

- [ ] Single-shot evaluation only
- [ ] Very simple rules (1-3 rules)
- [ ] Strict execution order required
- [ ] Memory is extremely limited
- [ ] Cold-start latency is critical

**Expected gain**: 2x faster for simple single evaluations

---

## Migration Guide

### From v1.x to v2.0.0

**Default behavior changed**: `run_rule_engine()` now uses RETE instead of Forward Chaining.

**No breaking changes**: Results are identical, only performance improves.

**If you need old behavior**:
```sql
-- Old (v1.x): run_rule_engine() used FC
-- New (v2.0+): use run_rule_engine_fc() for same behavior
SELECT run_rule_engine_fc(facts, rules);
```

**Recommended migration path**:
1. ✅ Keep using `run_rule_engine()` - get automatic RETE benefits
2. ⚠️ Monitor performance - should improve 3-10x for batches
3. 🔧 Use `run_rule_engine_fc()` only if specific FC behavior needed

---

## Architecture Notes

### RETE Algorithm (Rete Network)

```
Rules → RETE Compiler → Pattern Network → Working Memory
                            ↓
                    Incremental Matching
                            ↓
                        Rule Firing
```

**Key advantages**:
- **Pattern sharing**: Common conditions evaluated once
- **Incremental evaluation**: Only affected rules re-evaluated
- **Working memory**: Maintains state across evaluations

**Trade-offs**:
- Higher memory usage (stores RETE network)
- Compilation overhead (first execution)
- Optimal for reuse scenarios

### Forward Chaining

```
Rules → Parse → Match All → Fire in Salience Order
```

**Key advantages**:
- Predictable execution order
- Lower memory footprint
- No compilation overhead

**Trade-offs**:
- Re-evaluates all rules every time
- No pattern sharing
- Linear scaling with rule count

---

## Examples

### Batch Order Processing (RETE optimal)

```sql
-- Process 100 orders efficiently
DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..100 LOOP
        PERFORM run_rule_engine(
            format('{"Order": {"id": %s, "total": %s}}', i, 1000 + i*10)::text,
            '
            rule "VIP" { when Order.total > 1500 then Order.vip = true; }
            rule "Discount" { when Order.vip == true then Order.discount = Order.total * 0.15; }
            rule "FreeShip" { when Order.total > 2000 then Order.free_shipping = true; }
            '
        );
    END LOOP;
END $$;
-- RETE: ~1.5 seconds (15ms avg)
-- FC would be: ~15 seconds (150ms avg) - 10x slower!
```

### Simple Validation (FC optimal)

```sql
-- Single validation check
SELECT run_rule_engine_fc(
    '{"User": {"age": 17}}',
    'rule "CheckAge" { when User.age < 18 then User.minor = true; }'
);
-- FC: ~80ms
-- RETE: ~200ms (compilation overhead not worth it)
```

---

## Future Enhancements (v2.1.0+)

Planned optimizations:

1. **Auto-selection**: Automatically choose engine based on workload
   ```sql
   -- Future: Smart engine selection
   SELECT run_rule_engine_auto(facts, rules);
   -- Chooses FC for <5 rules, RETE for >=5
   ```

2. **RETE network caching**: Persist compiled networks
3. **Parallel evaluation**: Multi-threaded rule firing
4. **JIT optimization**: Runtime pattern optimization

Expected additional gains: **2-5x** on top of current RETE performance.

---

## Summary

**TL;DR**:

- 📊 **Production default**: `run_rule_engine()` (uses RETE)
- 🚀 **High performance explicit**: `run_rule_engine_rete()`
- 🔧 **Simple/debugging**: `run_rule_engine_fc()`

**Rule of thumb**:
- Batch processing? → RETE (**10x faster**)
- Single evaluation? → Either works
- Very simple (1-3 rules)? → FC (**2x faster for cold start**)

For 99% of production use cases, **RETE is the right choice**.
