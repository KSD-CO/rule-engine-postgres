# Load Test Results - Quick Summary

**Date:** January 26, 2026 | **Version:** 2.0.0 + rust-rule-engine v1.18.26 | **Platform:** PostgreSQL on Linux

---

## 🚀 Performance at a Glance - rust-rule-engine v1.18.26

**Benchmark Configuration:**
- Duration: 30 seconds per test
- Clients: 10 concurrent
- Threads: 4
- Test focus: Repository execute (saved rules)

| Version | Mean TPS | StdDev | Improvement vs v1.17.0 | Status |
|---------|----------|--------|------------------------|--------|
| **v1.18.26** | **13,505** | 3,068 | **+19.5%** | ⭐⭐⭐⭐⭐ Recommended |
| v1.18.0-alpha | 11,388 | 1,304 | +0.8% | ⚠️ Alpha |
| v1.17.0 | 11,298 | 1,801 | Baseline | - |

**TPS** = Transactions Per Second

### 🎯 Recommendation

**Use v1.18.26** - Provides the best performance (15.7% faster than v1.18.0-alpha, 19.5% faster than v1.17.0) with stable release quality.

---

## 📊 Historical Results (Previous Tests)

### ⚡ Speed
- **Fastest:** 0.101ms (simple rule)
- **Realistic:** 5.5ms (complex business logic)
- **Enterprise:** 162ms (100-rule stress test)
- **Extreme:** 420ms (500-rule batch processing) 🆕

### 💪 Reliability
- **Failure Rate:** 0.000% (all tests)
- **Transactions:** 505,559 total
- **Success Rate:** 100%

### 📈 Scalability
- **Sub-linear scaling:** ~0.84ms per rule (at 500 rules!)
- **No bottlenecks** up to 500 rules tested
- **Better than expected** - optimizes large rulesets
- **Predictable performance**

---

## ✅ Production Ready?

### YES! Here's why:

1. **38x faster** than target for simple rules
2. **3.8x faster** than target for complex rules
3. **100% success rate** under load
4. **Linear scaling** - predictable performance
5. **Handles enterprise scenarios** (100+ rules)

---

## 🎯 Use Cases & Recommendations

### Real-Time APIs (< 10ms)
✅ **Use 1-10 rules**
- Expected: 1,000-10,000 TPS
- Perfect for: API endpoints, webhooks, validations

### Business Workflows (< 100ms)
✅ **Use 10-50 rules**
- Expected: 100-1,000 TPS
- Perfect for: Order processing, pricing engines, approvals

### Batch Processing (< 1s)
✅ **Use 100-1000 rules**
- Expected: 10-100 TPS
- Perfect for: Nightly jobs, analytics, reporting

---

## 📈 Comparison to Alternatives

| Solution | Latency | Notes |
|----------|---------|-------|
| **This Engine** | **0.1-5ms** | ✅ In-database, no network |
| Drools (JVM) | 10-50ms | ❌ Separate service, JVM warmup |
| External API | 50-200ms | ❌ Network overhead |
| Microservice | 20-100ms | ❌ Extra hops, serialization |

**Advantage:** **10-100x faster** than typical solutions!

---

## 🔬 Test Details

### Configuration
```yaml
Clients: 10 concurrent
Threads: 4
Duration: 10-30 seconds per test
Database: PostgreSQL 17.7
Hardware: Apple Silicon (M-series)
```

### Tests Run
- ✅ Simple rule (1 condition)
- ✅ Complex rules (4 rules, multiple conditions)
- ✅ Stress test (100 enterprise rules)
- ✅ Extreme test (500 rules) 🆕

---

## 💡 Bottom Line

This rule engine is **exceptionally fast** and **production-ready**.

**You can:**
- ✅ Handle high-traffic APIs (48k+ req/sec)
- ✅ Process complex business logic (1.8k+ req/sec)
- ✅ Run enterprise-scale rulesets (60+ req/sec)
- ✅ Deploy with confidence (0% failures)

**Next steps:**
1. Review [BENCHMARK_RESULTS.md](BENCHMARK_RESULTS.md) for detailed analysis
2. Run your own tests with [load-tests suite](.)
3. Deploy to production! 🚀

---

**Questions?** See full documentation in [README.md](README.md)
