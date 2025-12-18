# Load Testing Suite for PostgreSQL Rule Engine

Comprehensive load testing suite using pgbench to validate performance and scalability of the rule engine.

## 🎯 Quick Start

### 1. Prerequisites

- PostgreSQL 16+ with `rule_engine_postgre_extensions` installed
- `pgbench` command-line tool (comes with PostgreSQL)
- Internet access (tests use httpbin.org and jsonplaceholder.typicode.com)

### 2. Run Tests

```bash
cd load-tests

# Basic run (10 clients, 60 seconds)
./run_loadtest.sh

# Custom configuration
CLIENTS=50 DURATION=120 ./run_loadtest.sh

# Different database
DB_HOST=myserver.com DB_NAME=production DB_PASSWORD=secret ./run_loadtest.sh
```

### 3. View Results

Results are saved to `results/loadtest_TIMESTAMP.txt` with detailed metrics.

**📊 Latest Benchmark Results:** See [BENCHMARK_RESULTS.md](BENCHMARK_RESULTS.md) for comprehensive performance analysis!

---

## 📊 Test Scenarios

### Test 01: Simple Rule (Forward Chaining) ⚡
**Result: 48,589 TPS | 0.101ms latency**
**File:** `01_simple_rule.sql`
**Description:** Tests basic forward chaining with 1 condition
**Target Performance:** 800-1250 TPS (transactions per second)

```sql
-- Example rule tested
rule "SimpleDiscount" {
    when Order.total > 100
    then Order.discount = Order.total * 0.10;
}
```

**What it measures:**
- Basic rule parsing performance
- Single condition evaluation
- Fact modification speed

---

### Test 02: Complex Rules (Multiple Conditions) 🎯
**Result: 1,802 TPS | 5.5ms latency**
**File:** `02_complex_rule.sql`
**Description:** Tests multiple rules with complex conditions and salience
**Target Performance:** 350-476 TPS

```sql
-- 4 rules with varying complexity
- GoldTier (salience 10)
- BulkDiscount (salience 8)
- SeniorDiscount (salience 7)
- SilverTier (salience 5)
```

**What it measures:**
- Multi-rule execution order (salience)
- Complex condition evaluation (&&, multiple fields)
- Rule chaining and fact updates

---

### Test 03: Repository Save (Concurrent Writes)
**File:** `03_repository_save.sql`
**Description:** Tests concurrent rule saves with versioning
**Target Performance:** 200-400 TPS

**What it measures:**
- Rule versioning system performance
- Concurrent write handling
- Database transaction throughput

---

### Test 04: Repository Execute (By Name)
**File:** `04_repository_execute.sql`
**Description:** Executes pre-saved rules by name
**Target Performance:** 600-1000 TPS

**What it measures:**
- Rule lookup performance
- Rule cache efficiency
- Named rule execution overhead vs inline

---

### Test 05: Webhook Calls (HTTP Callouts)
**File:** `05_webhook_call.sql`
**Description:** Tests HTTP callouts to external APIs
**Target Performance:** 100-200 TPS
**External API:** https://httpbin.org/post (free test service)

**What it measures:**
- HTTP client performance
- Queue processing
- Retry logic overhead
- Network latency impact

---

### Test 06: Datasource Fetch (API Integration)
**File:** `06_datasource_fetch.sql`
**Description:** Fetches data from external REST API with caching
**Target Performance:** 500-1000 TPS (with cache hits)
**External API:** https://jsonplaceholder.typicode.com (free test API)

**What it measures:**
- HTTP request performance
- Cache hit rate (should be 85%+)
- Connection pooling efficiency
- API rate limiting

---

### Test 07: Stress Test (100 Rules) 🔥
**Result: 61.76 TPS | 161.7ms latency | NEW!**
**File:** `07_stress_100_rules.sql`
**Description:** Enterprise-scale stress test with 100 business rules
**Target Performance:** N/A (extreme stress test)

**Rules Covered:**
- 100 realistic business rules
- VIP programs, loyalty tiers, regional promos
- Shipping calculations, tax rates, discount stacking
- Salience range: 100 (highest priority) to 1 (lowest)

**What it measures:**
- Rule engine scalability
- Performance with enterprise-scale rulesets
- Linear scaling validation
- Memory and CPU under stress
- Realistic multi-tier business logic

**Key Findings:**
- ✅ **Linear scaling:** ~1.62ms per rule
- ✅ **0% failures:** Rock-solid stability
- ✅ **Predictable performance:** No bottlenecks
- ✅ **Production-ready:** Can handle 100-1000 rules

**Run individually:**
```bash
pgbench -h localhost -U postgres -d postgres \
    -c 10 -j 4 -T 30 \
    -f 07_stress_100_rules.sql
```

---

## ⚙️ Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_HOST` | localhost | Database host |
| `DB_PORT` | 5432 | Database port |
| `DB_NAME` | postgres | Database name |
| `DB_USER` | postgres | Database user |
| `DB_PASSWORD` | postgres | Database password |
| `CLIENTS` | 10 | Number of concurrent clients |
| `THREADS` | 4 | Number of pgbench threads |
| `DURATION` | 60 | Test duration in seconds |
| `RATE` | 0 | Rate limit (0 = unlimited) |

### Example Configurations

**Light Load (Development)**
```bash
CLIENTS=5 DURATION=30 ./run_loadtest.sh
```

**Medium Load (Staging)**
```bash
CLIENTS=25 DURATION=120 ./run_loadtest.sh
```

**Heavy Load (Production Simulation)**
```bash
CLIENTS=100 THREADS=8 DURATION=300 ./run_loadtest.sh
```

**Rate-Limited Test**
```bash
CLIENTS=50 RATE=500 DURATION=120 ./run_loadtest.sh
# Limits throughput to 500 TPS to test sustained load
```

---

## 📈 Performance Targets

Based on the benchmarks from the main README:

| Test Scenario | Target TPS | Target Latency | Notes |
|--------------|-----------|----------------|-------|
| Simple rule (1 condition) | 800-1250 | < 1ms | Sub-millisecond expected |
| Complex rules (5 conditions) | 350-476 | 2-3ms | Multiple rule evaluations |
| Repository save | 200-400 | 3-5ms | Includes DB writes |
| Repository execute | 600-1000 | 1-2ms | With rule caching |
| Webhook calls | 100-200 | 50-100ms | Network-bound |
| Datasource fetch (cached) | 500-1000 | 1-5ms | High cache hit rate |
| Datasource fetch (uncached) | 50-100 | 50-200ms | External API call |

### Performance Tiers

**Excellent** (Production-ready)
- Simple rules: > 1000 TPS
- Complex rules: > 400 TPS
- Webhooks: > 150 TPS with < 100ms p95 latency

**Good** (Acceptable)
- Simple rules: 600-1000 TPS
- Complex rules: 300-400 TPS
- Webhooks: 100-150 TPS

**Needs Improvement**
- Simple rules: < 600 TPS
- Complex rules: < 300 TPS
- Webhooks: < 100 TPS

---

## 🔍 Interpreting Results

### pgbench Output Explained

```
transaction type: 01_simple_rule.sql
scaling factor: 1
query mode: simple
number of clients: 10
number of threads: 4
duration: 60 s
number of transactions actually processed: 75324
latency average = 7.963 ms
latency stddev = 2.134 ms
tps = 1255.392873 (including connections establishing)
tps = 1255.718394 (excluding connections establishing)
```

**Key Metrics:**

1. **TPS (Transactions Per Second)**
   - Primary performance indicator
   - "including connections" = real-world scenario
   - Compare against targets above

2. **Latency Average**
   - Mean response time
   - Should be < 10ms for most operations
   - Webhooks/datasources will be higher (network)

3. **Latency Stddev**
   - Consistency indicator
   - Lower is better (more predictable)
   - High stddev may indicate contention

4. **Transactions Processed**
   - Total operations completed
   - Higher is better

### Red Flags

⚠️ **Performance Issues:**
- TPS < 50% of target
- Latency average > 20ms (for non-network ops)
- Latency stddev > 50% of average
- High number of failed transactions

⚠️ **Possible Causes:**
- Insufficient database resources (CPU, RAM)
- Network latency (for webhooks/datasources)
- Database locks/contention
- Unoptimized queries
- External API rate limiting

---

## 🛠️ Troubleshooting

### Test Setup Fails

**Error:** "Cannot connect to database"
```bash
# Check connection manually
psql -h localhost -p 5432 -U postgres -d postgres

# Try with explicit password
PGPASSWORD=yourpassword psql -h localhost -U postgres
```

**Error:** "Rule engine extension not installed"
```sql
-- Connect to database
psql -U postgres -d your_database

-- Install extension
CREATE EXTENSION rule_engine_postgre_extensions;

-- Verify
SELECT rule_engine_version();
```

### Low Performance

**Problem:** TPS much lower than expected

**Solutions:**

1. **Check database resources**
```sql
-- Check active connections
SELECT count(*) FROM pg_stat_activity;

-- Check locks
SELECT * FROM pg_locks WHERE NOT granted;

-- Check slow queries
SELECT * FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;
```

2. **Tune PostgreSQL**
```bash
# Edit postgresql.conf
max_connections = 100
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 16MB
```

3. **Adjust test parameters**
```bash
# Reduce clients if database is overwhelmed
CLIENTS=5 ./run_loadtest.sh

# Increase threads if CPU is underutilized
THREADS=8 ./run_loadtest.sh
```

### Webhook/Datasource Failures

**Problem:** High failure rate for tests 05-06

**Solutions:**

1. **Check internet connectivity**
```bash
curl -v https://httpbin.org/post
curl -v https://jsonplaceholder.typicode.com/users/1
```

2. **Use local mock server** (recommended for isolated testing)
```bash
# Install json-server (Node.js required)
npm install -g json-server

# Create mock data
echo '{"users": [{"id": 1, "name": "Test"}]}' > db.json

# Start mock server
json-server --watch db.json --port 3000

# Update setup.sql to use localhost:3000
```

3. **Increase timeout values**
```sql
-- In setup.sql, increase timeout
SELECT rule_webhook_register(
    'loadtest_webhook',
    'https://httpbin.org/post',
    'POST',
    '{"Content-Type": "application/json"}'::JSONB,
    'Load test webhook',
    30000,  -- Increase from 10s to 30s
    3
);
```

---

## 📊 Advanced Usage

### Custom Test Scripts

Create your own test script:

```sql
-- load-tests/07_custom_test.sql
\set my_variable random(1, 100)

SELECT run_rule_engine(
    format('{"MyData": {"value": %s}}', :my_variable),
    'rule "Custom" { when MyData.value > 50 then MyData.result = true; }'
)::jsonb;
```

Run it:
```bash
pgbench -h localhost -U postgres -d postgres \
    -c 10 -j 4 -T 60 \
    -f 07_custom_test.sql
```

### Monitoring During Tests

**Terminal 1: Run tests**
```bash
./run_loadtest.sh
```

**Terminal 2: Monitor database**
```sql
-- Watch active queries
SELECT pid, usename, state, query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start;

-- Watch performance views
SELECT * FROM rule_performance_summary;
SELECT * FROM webhook_status_summary;
SELECT * FROM datasource_performance_stats;
```

### CI/CD Integration

Add to your CI pipeline:

```yaml
# .github/workflows/loadtest.yml
name: Load Test
on: [push]

jobs:
  loadtest:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: jamesvu/rule-engine-postgres:latest
        env:
          POSTGRES_PASSWORD: postgres
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v3

      - name: Run Load Tests
        env:
          DB_PASSWORD: postgres
          CLIENTS: 10
          DURATION: 30
        run: |
          cd load-tests
          ./run_loadtest.sh

      - name: Check Results
        run: |
          # Fail if TPS < threshold
          grep "tps =" load-tests/results/loadtest_*.txt | \
            awk '{if ($3 < 500) exit 1}'
```

---

## 📝 Best Practices

### Before Running Tests

1. ✅ Test on non-production database
2. ✅ Ensure adequate database resources
3. ✅ Check network connectivity for webhook/datasource tests
4. ✅ Run setup.sql successfully
5. ✅ Review cleanup.sql to understand what will be deleted

### During Tests

1. ✅ Monitor database CPU/memory/disk
2. ✅ Watch for errors in PostgreSQL logs
3. ✅ Keep an eye on external API rate limits
4. ✅ Check network latency if testing remote database

### After Tests

1. ✅ Run cleanup.sql to remove test data
2. ✅ Review results file for anomalies
3. ✅ Compare against baseline/previous runs
4. ✅ Document any performance degradation
5. ✅ Archive results for historical comparison

### Production Testing

⚠️ **If testing against production:**

1. Use read replicas if possible
2. Start with low client count (CLIENTS=5)
3. Schedule during low-traffic periods
4. Monitor impact on production queries
5. Have rollback plan ready
6. Gradually increase load

---

## 🎯 Performance Tuning Tips

### Database Level

```sql
-- Increase connection pool
ALTER SYSTEM SET max_connections = 200;

-- Increase work memory
ALTER SYSTEM SET work_mem = '64MB';

-- Enable parallel queries
ALTER SYSTEM SET max_parallel_workers_per_gather = 4;

-- Reload configuration
SELECT pg_reload_conf();
```

### Application Level

```sql
-- Pre-compile frequently used rules
SELECT rule_save('hot_path_rule', '...', '1.0.0', 'Hot path', 'Optimized');

-- Enable rule caching (if implemented)
-- Use rule_execute_by_name instead of inline GRL

-- Batch webhook calls
SELECT rule_webhook_enqueue(...);  -- Queue instead of immediate call
```

### pgbench Tuning

```bash
# Use prepared statements for faster execution
pgbench -M prepared ...

# Disable progress reports for faster execution
pgbench -P 0 ...

# Use multiple pgbench instances for higher concurrency
pgbench -c 50 ... &
pgbench -c 50 ... &
wait
```

---

## 📚 Related Documentation

- [Main README](../README.md) - Project overview
- [Usage Guide](../docs/USAGE_GUIDE.md) - Feature documentation
- [Webhooks Guide](../docs/WEBHOOKS.md) - Webhook configuration
- [External Data Sources](../docs/EXTERNAL_DATASOURCES.md) - API integration
- [API Reference](../docs/api-reference.md) - Function reference

---

## 🤝 Contributing

Found a performance issue? Have a new test scenario?

1. Create an issue with benchmark results
2. Submit PR with new test scripts
3. Share your tuning tips

---

## 📄 License

MIT License - Same as main project

---

**Happy Load Testing! 🚀**

For questions or issues, please open a GitHub issue.
