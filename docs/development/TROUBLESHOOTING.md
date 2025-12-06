# Common Build Issues and Solutions

## Error: "Failed to find a pgrx_embed binary"

### Problem
```
Discovered 16 SQL entities: 0 schemas (0 unique), 16 functions...
Error: 
   0: Failed to find a pgrx_embed binary.
```

This error occurs when running `cargo pgrx package` because it needs the `pgrx_embed` tool to generate SQL schema files.

### Root Cause
`cargo pgrx package` expects `pgrx_embed` to be built and available, but it's not automatically built. This is a known limitation in pgrx 0.16.x.

### Solutions

#### Solution 1: Build pgrx_embed first (Recommended for CI/CD)
```bash
# Build pgrx_embed
cargo build --release --bin pgrx_embed --no-default-features --features pg17

# Now package will work
cargo pgrx package --pg-config /path/to/pg_config
```

This is the approach used in our `build-deb.sh` script.

#### Solution 2: Use cargo pgrx install instead
```bash
# Install directly (no pgrx_embed needed)
cargo pgrx install --pg-config /path/to/pg_config --release
```

This is the approach used in our `install.sh` script.

#### Solution 3: Use regular cargo build + manual copy
```bash
# Build the extension
cargo build --release --no-default-features --features pg17

# Manually copy files
sudo cp target/release/librule_engine_postgre_extensions.so \
  /usr/lib/postgresql/17/lib/rule_engine_postgre_extensions.so

sudo cp *.control *.sql /usr/share/postgresql/17/extension/
```

### Where This is Fixed

- ✅ **install.sh**: Uses `cargo pgrx install` (no pgrx_embed needed)
- ✅ **build-deb.sh**: Builds pgrx_embed before running package
- ✅ **CI workflow (.github/workflows/ci.yml)**: Uses regular `cargo build`
- ✅ **Release workflow (.github/workflows/release.yml)**: Initializes pgrx properly

---

## Error: "pg_config not found"

### Problem
```
❌ Error: pg_config not found for PostgreSQL 17
```

### Solutions

**Ubuntu/Debian:**
```bash
sudo apt-get install postgresql-server-dev-17
```

**macOS (Homebrew):**
```bash
brew install postgresql@17
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
```

**Verify:**
```bash
which pg_config
pg_config --version
```

---

## Error: Clippy warnings in CI

### Problem
CI fails with:
```
error: field `0` is never read
  --> src/repository/version.rs:13:11
```

### Solution
Use pre-commit hooks to catch issues before pushing:

```bash
# Automatic check on every commit
git commit -m "your changes"  # Runs fmt + clippy automatically

# Manual check
./check-before-commit.sh      # Full check (PG 16 & 17)
./quick-check.sh               # Quick check (PG 17 only)

# Auto-fix
cargo fmt --all
cargo clippy --no-default-features --features pg17 --fix -- -D warnings
```

Pre-commit hook is automatically installed in `.git/hooks/pre-commit`.

---

## Error: "cannot find -lpq"

### Problem
```
error: linking with `cc` failed
note: /usr/bin/ld: cannot find -lpq
```

### Solution
Install PostgreSQL development libraries:

**Ubuntu/Debian:**
```bash
sudo apt-get install libpq-dev
```

**macOS:**
```bash
brew install libpq
export LIBRARY_PATH="/opt/homebrew/opt/libpq/lib:$LIBRARY_PATH"
```

---

## Build Performance Issues

### Slow cargo pgrx package
Use regular build for development:
```bash
# Development (faster)
cargo build --no-default-features --features pg17

# CI/Production (complete)
cargo pgrx package --pg-config /path/to/pg_config
```

### Cache in CI
GitHub Actions caches are configured in `.github/workflows/ci.yml`:
```yaml
- name: Cache cargo
  uses: actions/cache@v4
  with:
    path: |
      ~/.cargo/registry
      ~/.cargo/git
      target
    key: ${{ runner.os }}-cargo-pg${{ matrix.pg_version }}-${{ hashFiles('**/Cargo.lock') }}
```

---

## Testing Issues

### pgrx tests fail
Make sure pgrx is initialized:
```bash
cargo pgrx init --pg17 /usr/lib/postgresql/17/bin/pg_config
cargo pgrx test pg17
```

### Regular tests fail
```bash
# Run with specific feature
cargo test --no-default-features --features pg17
```

---

## Version Mismatch

### Problem
Different versions across files (Cargo.toml, control file, SQL, README).

### Solution
Use version management scripts:
```bash
# Check consistency
./version.sh

# Update all files at once
./bump-version.sh 1.2.0
```

These scripts ensure single source of truth from `Cargo.toml`.
