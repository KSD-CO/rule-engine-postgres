# Fuzzing Guide for Rule Engine PostgreSQL

## 🎯 What is Fuzzing?

Fuzzing (fuzz testing) is an automated testing technique that feeds **random, malformed, or unexpected inputs** to your code to find bugs, crashes, and security vulnerabilities that manual testing might miss.

### Why Fuzzing is Important

Traditional testing:
```sql
-- You manually test:
✅ {"Order": {"total": 100}}
✅ {"Order": {"total": 0}}
✅ {"Order": {"total": -1}}
```

Fuzzing automatically tests:
```sql
-- Fuzzer finds edge cases:
❌ {"Order": {"total": 9.999999999999999e+307}}  -- Overflow!
❌ {"Order": {"total\u0000": 100}}               -- Null byte crash!
❌ {"Order": {"a": {"b": {"c": ... 1000 levels}}} -- Stack overflow!
❌ rule "X" { when @@@@@@ then ... }             -- Invalid syntax
```

## 🛠️ Setup

### 1. Install Rust Nightly (Required)

```bash
rustup install nightly
```

### 2. Install cargo-fuzz

```bash
cargo install cargo-fuzz
```

### 3. Verify Setup

```bash
cargo fuzz list
# Should output:
# fuzz_extreme_values
# fuzz_grl_syntax
# fuzz_json_input
```

## 🚀 Running Fuzz Tests

### Quick Start (10 seconds each)

```bash
# Test JSON parsing
cargo +nightly fuzz run fuzz_json_input -- -max_total_time=10

# Test GRL syntax parsing
cargo +nightly fuzz run fuzz_grl_syntax -- -max_total_time=10

# Test extreme values
cargo +nightly fuzz run fuzz_extreme_values -- -max_total_time=10
```

### Extended Testing (Recommended for CI)

```bash
# Run for 5 minutes with limited input size
cargo +nightly fuzz run fuzz_json_input -- -max_total_time=300 -max_len=4096

# Run for 10 minutes with verbose output
cargo +nightly fuzz run fuzz_grl_syntax -- -max_total_time=600 -verbosity=2

# Run overnight for thorough testing
cargo +nightly fuzz run fuzz_extreme_values -- -max_total_time=28800
```

### Continuous Fuzzing

```bash
# Run until crash is found (Ctrl+C to stop)
cargo +nightly fuzz run fuzz_json_input
```

## 📊 Fuzz Targets

### 1. `fuzz_json_input` - JSON Parsing

**What it tests:**
- JSON parsing with malformed input
- Serialization/deserialization round-trips
- Handling of special characters and unicode
- Edge cases in JSON structure

**Example inputs it generates:**
```json
{{{{{                          // Malformed JSON
{"key": "\u0000"}             // Null bytes
{"🔥": "test"}                // Unicode/emoji
{"a": [[[[[1]]]]]}            // Deep nesting
```

### 2. `fuzz_grl_syntax` - GRL Parser

**What it tests:**
- GRL syntax parsing robustness
- Handling of invalid rule syntax
- Edge cases in rule structure
- Parser crash resistance

**Example inputs it generates:**
```grl
rule "X" { when when when ... }       // Duplicate keywords
rule "" { when ... }                  // Empty name
rule "X" { when @@@@@ then ... }     // Invalid operators
rule "X" { {{{{{{                    // Malformed braces
```

### 3. `fuzz_extreme_values` - Extreme Values

**What it tests:**
- Extreme numeric values (infinity, NaN, max/min)
- Very long strings (up to 10,000 chars)
- Deep nesting (up to 50 levels)
- Large arrays (up to 1,000 elements)
- Many object keys (up to 1,000 keys)
- Special characters and unicode

**Example test cases:**
```rust
f64::INFINITY           // Infinity
f64::NAN               // Not a Number
1.7976931348623157e+308 // Near max float
"x" * 10000            // Very long string
{"nested": {"nested": ...}}  // 50 levels deep
```

## 🔍 Understanding Results

### Success (No Crashes)

```
#12345 NEW    cov: 234 ft: 567 corp: 89/12Kb exec/s: 1234 rss: 67Mb
```

This means:
- `#12345`: 12,345 test cases run
- `NEW`: Found new code coverage
- `cov: 234`: 234 code paths covered
- `corp: 89/12Kb`: 89 interesting inputs saved (12KB total)
- `exec/s: 1234`: Running 1,234 tests per second

### Crash Found! 🐛

```
==12345==ERROR: AddressSanitizer: heap-buffer-overflow
```

When a crash is found:
1. Fuzzer saves the crashing input to `fuzz/artifacts/fuzz_target_name/crash-*`
2. Review the file to understand what input caused the crash
3. Create a regression test
4. Fix the bug
5. Re-run fuzzer to verify fix

## 📁 Fuzzing Artifacts

### Corpus (Interesting Inputs)

```
fuzz/corpus/fuzz_json_input/
```

These are inputs that increased code coverage. The fuzzer uses them as seeds for future mutations.

### Crashes

```
fuzz/artifacts/fuzz_json_input/crash-abc123
```

Inputs that caused crashes. **Keep these for regression tests!**

## 🧪 Example: What Fuzzing Can Find

### Real Bugs Fuzzing Typically Discovers:

1. **Integer Overflow**
```rust
// Bug: No check for overflow
let total = order.total * 1000000;  // Overflow with large values!
```

2. **Null Byte Injection**
```rust
// Bug: Null bytes in strings
let key = "total\0malicious";  // May bypass validation
```

3. **Stack Overflow**
```rust
// Bug: Unbounded recursion
fn parse_nested(value) {
    if value.is_object() {
        for (_, v) in value {
            parse_nested(v);  // 1000 levels = stack overflow!
        }
    }
}
```

4. **Division by Zero**
```rust
// Bug: No zero check
let discount = total / quantity;  // Crash if quantity = 0!
```

5. **Memory Exhaustion**
```rust
// Bug: Unbounded allocation
let large_string = "x".repeat(usize::MAX);  // OOM!
```

## 🎯 Best Practices

### 1. Run Before Commits

```bash
# Quick smoke test (30 seconds total)
cargo +nightly fuzz run fuzz_json_input -- -max_total_time=10
cargo +nightly fuzz run fuzz_grl_syntax -- -max_total_time=10
cargo +nightly fuzz run fuzz_extreme_values -- -max_total_time=10
```

### 2. Run in CI/CD

```yaml
# .github/workflows/fuzzing.yml
name: Fuzzing
on: [push, pull_request]
jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: actions-rs/toolchain@v1
        with:
          toolchain: nightly
      - run: cargo install cargo-fuzz
      - run: cargo +nightly fuzz run fuzz_json_input -- -max_total_time=300
      - run: cargo +nightly fuzz run fuzz_grl_syntax -- -max_total_time=300
```

### 3. Long-Running Fuzzing

For maximum coverage, run fuzzing overnight or continuously:

```bash
# Run in tmux/screen session
screen -S fuzzing
cargo +nightly fuzz run fuzz_json_input
# Detach: Ctrl+A, D
```

### 4. Reproduce Crashes

```bash
# Reproduce a specific crash
cargo +nightly fuzz run fuzz_json_input fuzz/artifacts/fuzz_json_input/crash-abc123
```

## 📊 Measuring Coverage

```bash
# Generate coverage report
cargo +nightly fuzz coverage fuzz_json_input

# View coverage (requires lcov)
lcov --list fuzz/coverage/fuzz_json_input/coverage.profdata
```

## 🔧 Troubleshooting

### "Error: option Z is only accepted on nightly"

**Solution:** Use `cargo +nightly` instead of `cargo`:
```bash
cargo +nightly fuzz run fuzz_json_input
```

### "Out of Memory"

**Solution:** Limit max input size:
```bash
cargo +nightly fuzz run fuzz_json_input -- -max_len=1024
```

### "Too Slow"

**Solution:** Increase timeout or reduce complexity:
```bash
cargo +nightly fuzz run fuzz_json_input -- -timeout=60
```

## 📚 Learn More

- [Rust Fuzz Book](https://rust-fuzz.github.io/book/)
- [libFuzzer Documentation](https://llvm.org/docs/LibFuzzer.html)
- [AFL (American Fuzzy Lop)](https://github.com/google/AFL)

## 🎉 Benefits for Rule Engine

Fuzzing helps ensure:
- ✅ **Robust JSON parsing** - Handles malformed input gracefully
- ✅ **Safe GRL parsing** - No crashes on invalid syntax
- ✅ **Security** - Finds injection vulnerabilities
- ✅ **Reliability** - Discovers edge cases before production
- ✅ **Performance** - Identifies DoS vulnerabilities
- ✅ **Compliance** - Proves thorough testing for audits

---

**Run fuzzing regularly to keep your rule engine rock-solid! 🚀**
