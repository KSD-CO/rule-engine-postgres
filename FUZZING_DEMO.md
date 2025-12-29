# Fuzzing Demo & Examples

## 🎬 What Fuzzing Does (Visual Demo)

### Before Fuzzing (Manual Testing)

```bash
# Developer manually tests a few cases:
✅ Test 1: {"Order": {"total": 100}}      → Works
✅ Test 2: {"Order": {"total": 0}}        → Works
✅ Test 3: {"Order": {"total": -1}}       → Works
✅ Test 4: {"Order": {}}                  → Works

# Ship to production... 🚢
```

### After Fuzzing (Automated Testing)

```bash
# Fuzzer automatically tests MILLIONS of cases:
#1     {"Order": {"total": 100}}                    → ✅ OK
#2     {"Order": {"total": 0}}                      → ✅ OK
#3     {"Order": {"total": -1}}                     → ✅ OK
#4     {"Order": {}}                                → ✅ OK
#5     {"Order": {"total": 9e308}}                  → ✅ OK
#6     {"Order": {"total": Infinity}}               → ✅ OK
#7     {"Order": {"total": NaN}}                    → ✅ OK
#8     {"Order": {"total\u0000": 1}}                → ❌ CRASH! NULL BYTE BUG FOUND
#9     {"Order": {"a": {"b": {"c": ...1000x}}}}     → ❌ CRASH! STACK OVERFLOW FOUND
#10    {{{{{{{{{                                    → ✅ OK (graceful error)
...
#100000 ...                                         → Testing continues

# Fuzzer found 2 bugs we never thought of! 🐛
```

## 🔍 Real Examples of Bugs Fuzzing Can Find

### Example 1: Integer Overflow

**Code:**
```rust
fn calculate_discount(total: i64, percentage: i64) -> i64 {
    total * percentage / 100  // BUG: Can overflow!
}
```

**Manual test (looks fine):**
```rust
calculate_discount(100, 10);   // = 10 ✅
calculate_discount(1000, 20);  // = 200 ✅
```

**Fuzzer finds:**
```rust
calculate_discount(9223372036854775807, 100);  // OVERFLOW! ❌ CRASH
```

**Fix:**
```rust
fn calculate_discount(total: i64, percentage: i64) -> Result<i64, Error> {
    total.checked_mul(percentage)
         .and_then(|v| v.checked_div(100))
         .ok_or(Error::Overflow)
}
```

---

### Example 2: Null Byte Injection

**Code:**
```rust
fn validate_key(key: &str) -> bool {
    !key.is_empty() && key.chars().all(|c| c.is_alphanumeric())
}
```

**Manual test (looks fine):**
```rust
validate_key("Order");     // true ✅
validate_key("Customer");  // true ✅
validate_key("");          // false ✅
validate_key("!@#");       // false ✅
```

**Fuzzer finds:**
```rust
validate_key("Order\0DROP TABLE users;");
// Returns: true ✅ (only checks before \0)
// But later code may treat full string as valid! ❌ SQL INJECTION
```

**Fix:**
```rust
fn validate_key(key: &str) -> bool {
    !key.is_empty()
        && !key.contains('\0')  // Check for null bytes!
        && key.chars().all(|c| c.is_alphanumeric())
}
```

---

### Example 3: Stack Overflow (Deep Nesting)

**Code:**
```rust
fn count_nested_depth(json: &Value) -> usize {
    match json {
        Value::Object(map) => {
            map.values()
               .map(|v| count_nested_depth(v))  // BUG: Unbounded recursion
               .max()
               .unwrap_or(0) + 1
        }
        _ => 0
    }
}
```

**Manual test (looks fine):**
```json
{"a": {"b": {"c": 1}}}  // depth = 3 ✅
```

**Fuzzer finds:**
```json
{"a": {"a": {"a": {"a": ... 10000 times }}}}
// STACK OVERFLOW! ❌ CRASH
```

**Fix:**
```rust
fn count_nested_depth(json: &Value) -> Result<usize, Error> {
    count_nested_depth_impl(json, 0, MAX_DEPTH)
}

fn count_nested_depth_impl(json: &Value, current: usize, max: usize) -> Result<usize, Error> {
    if current > max {
        return Err(Error::TooDeep);
    }
    match json {
        Value::Object(map) => {
            map.values()
               .map(|v| count_nested_depth_impl(v, current + 1, max))
               .collect::<Result<Vec<_>, _>>()?
               .into_iter()
               .max()
               .unwrap_or(Ok(0))
               .map(|d| d + 1)
        }
        _ => Ok(0)
    }
}
```

---

### Example 4: Division by Zero

**Code:**
```rust
fn calculate_average(total: f64, count: u32) -> f64 {
    total / count as f64  // BUG: Division by zero
}
```

**Manual test (looks fine):**
```rust
calculate_average(100.0, 10);  // = 10.0 ✅
calculate_average(50.0, 5);    // = 10.0 ✅
```

**Fuzzer finds:**
```rust
calculate_average(100.0, 0);  // = Infinity ❌ or CRASH
```

**Fix:**
```rust
fn calculate_average(total: f64, count: u32) -> Result<f64, Error> {
    if count == 0 {
        return Err(Error::DivisionByZero);
    }
    Ok(total / count as f64)
}
```

---

### Example 5: Unicode Edge Cases

**Code:**
```rust
fn truncate_name(name: &str, max_len: usize) -> String {
    name.chars().take(max_len).collect()  // Looks OK
}
```

**Manual test (looks fine):**
```rust
truncate_name("John Doe", 4);     // "John" ✅
truncate_name("Alice Smith", 5);  // "Alice" ✅
```

**Fuzzer finds:**
```rust
truncate_name("🔥🚀💎", 2);
// Expected: "🔥🚀"
// Actual: May truncate mid-character! ❌ Invalid UTF-8
```

**Fix:**
```rust
fn truncate_name(name: &str, max_chars: usize) -> String {
    name.chars()
        .take(max_chars)
        .collect::<String>()
        .chars()  // Ensure valid UTF-8
        .collect()
}
```

---

## 🎯 How Fuzzing Works (Step-by-Step)

### Step 1: Initial Seed Inputs

Fuzzer starts with basic inputs:
```
Corpus:
1. {"Order": {"total": 100}}
2. {"Customer": {"tier": "Gold"}}
3. rule "Test" { when ... }
```

### Step 2: Mutation

Fuzzer mutates inputs randomly:
```
Original: {"Order": {"total": 100}}

Mutations:
→ {"Order": {"total": 0}}           (replace number)
→ {"Order": {"total": -100}}        (negate)
→ {"Order": {"total": 999999999}}   (make huge)
→ {"Order": {"total": NaN}}         (special value)
→ {"Order": {"total\0": 100}}       (inject null byte)
→ {"Order": {}}                     (remove field)
→ {{{{{                             (corrupt structure)
```

### Step 3: Coverage Feedback

Fuzzer tracks which inputs explore new code paths:
```
Input #1: {"total": 100}     → Coverage: 60%
Input #2: {"total": -1}      → Coverage: 65% ← NEW PATH (negative check)
Input #3: {"total": 0}       → Coverage: 70% ← NEW PATH (zero check)
Input #4: {"total": NaN}     → Coverage: 75% ← NEW PATH (NaN handling)
```

### Step 4: Crash Detection

When a crash is found:
```
Input #12345: {"total\0malicious": 100}
→ AddressSanitizer: heap-buffer-overflow
→ CRASH SAVED to: fuzz/artifacts/crash-abc123
```

### Step 5: Crash Minimization

Fuzzer reduces crash to minimal reproducer:
```
Original crash: {"Order": {"total\0malicious_long_string": 100, "extra": ...}}

Minimized: {"total\0": 1}  ← Smallest input that crashes
```

## 📊 Fuzzing Statistics Explained

When you run fuzzing, you see output like:
```
#12345 NEW    cov: 234 ft: 567 corp: 89/12Kb exec/s: 1234 rss: 67Mb
```

**What it means:**

| Field | Meaning | Example |
|-------|---------|---------|
| `#12345` | Test cases executed | 12,345 inputs tested |
| `NEW` | Found new coverage | This input explored new code |
| `cov: 234` | Code coverage | 234 code blocks covered |
| `ft: 567` | Features | 567 unique code paths found |
| `corp: 89/12Kb` | Corpus size | 89 interesting inputs, 12KB total |
| `exec/s: 1234` | Speed | 1,234 tests per second |
| `rss: 67Mb` | Memory | Using 67 MB RAM |

**Good signs:**
- ✅ `exec/s` increasing → Getting faster
- ✅ `cov` increasing → Finding new code paths
- ✅ No crashes → Code is robust

**Bad signs:**
- ❌ Crash found → Bug discovered (but good for fixing!)
- ❌ `rss` growing rapidly → Memory leak?
- ❌ `exec/s` very low → Performance issue?

## 🚀 Quick Fuzzing Workflow

### 1. Run Fuzzer
```bash
./run-fuzzing.sh 60  # Run for 1 minute
```

### 2. Check Results
```bash
# No crashes found
🎉 All fuzz targets passed!

# OR crashes found
⚠️  Crash found in fuzz_json_input
→ See: fuzz/artifacts/fuzz_json_input/crash-abc123
```

### 3. Reproduce Crash
```bash
# Reproduce the exact crash
cargo +nightly fuzz run fuzz_json_input fuzz/artifacts/fuzz_json_input/crash-abc123

# View the crashing input
cat fuzz/artifacts/fuzz_json_input/crash-abc123
```

### 4. Debug & Fix
```bash
# Add debug output, fix bug, then verify
cargo +nightly fuzz run fuzz_json_input fuzz/artifacts/fuzz_json_input/crash-abc123

# Should now pass!
✅ No crash
```

### 5. Add Regression Test
```rust
#[test]
fn test_fuzzer_crash_abc123() {
    // Ensure this input never crashes again
    let input = include_bytes!("../fuzz/artifacts/fuzz_json_input/crash-abc123");
    let result = parse_json(input);
    assert!(result.is_ok() || result.is_err());  // Must not panic
}
```

## 🎓 Learn More

- **Try it now:** `./run-fuzzing.sh`
- **Read full guide:** [FUZZING_GUIDE.md](FUZZING_GUIDE.md)
- **Project summary:** [FUZZING_SUMMARY.md](FUZZING_SUMMARY.md)

---

**Fuzzing = Automated bug hunting that never sleeps! 🐛🔍**
