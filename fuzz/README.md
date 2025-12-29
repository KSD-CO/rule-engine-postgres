# Fuzzing Tests

This directory contains fuzzing tests for the Rule Engine PostgreSQL extension.

## Quick Start

```bash
# Run all fuzz tests (10 seconds each)
./run-fuzzing.sh

# Run for 5 minutes each
./run-fuzzing.sh 300

# Run with custom duration and max input size
./run-fuzzing.sh 600 8192  # 10 minutes, 8KB max input
```

## Fuzz Targets

### 1. `fuzz_json_input`
Tests JSON parsing robustness with random and malformed inputs.

**Run:**
```bash
cargo +nightly fuzz run fuzz_json_input -- -max_total_time=10
```

### 2. `fuzz_grl_syntax`
Tests GRL syntax parsing with invalid rule definitions.

**Run:**
```bash
cargo +nightly fuzz run fuzz_grl_syntax -- -max_total_time=10
```

### 3. `fuzz_extreme_values`
Tests handling of extreme numeric values, very long strings, deep nesting, etc.

**Run:**
```bash
cargo +nightly fuzz run fuzz_extreme_values -- -max_total_time=10
```

## Directory Structure

```
fuzz/
├── Cargo.toml              # Fuzzing dependencies
├── fuzz_targets/           # Fuzz test implementations
│   ├── fuzz_json_input.rs
│   ├── fuzz_grl_syntax.rs
│   └── fuzz_extreme_values.rs
├── corpus/                 # Interesting inputs (auto-generated)
│   ├── fuzz_json_input/
│   ├── fuzz_grl_syntax/
│   └── fuzz_extreme_values/
└── artifacts/              # Crash artifacts (if any found)
    ├── fuzz_json_input/
    ├── fuzz_grl_syntax/
    └── fuzz_extreme_values/
```

## Documentation

See [FUZZING_GUIDE.md](../FUZZING_GUIDE.md) for complete documentation.

## CI Integration

Add to `.github/workflows/fuzzing.yml`:

```yaml
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
      - run: ./run-fuzzing.sh 300  # 5 minutes per target
```

## What Fuzzing Can Find

- 🐛 **Panics and crashes** from unexpected input
- 💥 **Memory safety issues** (buffer overflows, use-after-free)
- 🔒 **Security vulnerabilities** (injection attacks, DoS)
- 📊 **Performance issues** (algorithmic complexity attacks)
- ⚡ **Edge cases** that manual testing misses

## Examples of Bugs Fuzzing Discovers

1. **Integer overflow** - Large numbers causing arithmetic overflow
2. **Null byte injection** - Strings with embedded null bytes
3. **Stack overflow** - Deep recursion or nesting
4. **Division by zero** - Unhandled zero divisors
5. **Memory exhaustion** - Unbounded allocation
6. **Unicode issues** - Invalid UTF-8 or special characters
7. **Parser bugs** - Malformed syntax causing panics

## Best Practices

✅ Run fuzzing before major releases
✅ Add fuzzing to CI/CD pipeline
✅ Review and fix any crashes found
✅ Keep crash artifacts for regression tests
✅ Monitor code coverage improvements

## Troubleshooting

**Q: "Error: option Z is only accepted on nightly"**
A: Use `cargo +nightly fuzz` instead of `cargo fuzz`

**Q: "Out of memory"**
A: Limit input size: `-- -max_len=1024`

**Q: "Too slow"**
A: Reduce timeout: `-- -timeout=30`

---

For more details, see [FUZZING_GUIDE.md](../FUZZING_GUIDE.md)
