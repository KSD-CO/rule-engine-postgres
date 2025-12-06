# Contributing to Rule Engine PostgreSQL

Thank you for your interest in contributing! This document provides guidelines and instructions for contributing to the project.

---

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Submitting Changes](#submitting-changes)
- [RFC Process](#rfc-process)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)
- [Documentation](#documentation)

---

## Code of Conduct

This project follows the [Rust Code of Conduct](https://www.rust-lang.org/policies/code-of-conduct). By participating, you are expected to uphold this code.

---

## How Can I Contribute?

### 🐛 Reporting Bugs

Before creating bug reports, please check existing issues. When creating a bug report, include:

- **Description:** Clear description of the bug
- **Steps to Reproduce:** Detailed steps to reproduce the issue
- **Expected Behavior:** What you expected to happen
- **Actual Behavior:** What actually happened
- **Environment:**
  - PostgreSQL version
  - Extension version
  - OS and version
  - Rust version (if building from source)
- **Logs/Errors:** Relevant error messages or logs
- **Minimal Example:** SQL code that demonstrates the issue

**Bug Report Template:**
```markdown
## Bug Description
[Clear description]

## Steps to Reproduce
1. Step 1
2. Step 2
3. Step 3

## Expected Behavior
[What should happen]

## Actual Behavior
[What actually happens]

## Environment
- PostgreSQL: 16.1
- Extension: 1.0.0
- OS: Ubuntu 22.04
- Rust: 1.75.0

## Logs
```
[Error messages]
```

## Minimal Example
```sql
SELECT run_rule_engine(...);
```
```

### 💡 Suggesting Features

Feature requests are welcome! Please:

1. Check if the feature is already in the [Roadmap](docs/ROADMAP.md)
2. Create an issue with the "enhancement" label
3. Describe:
   - **Use Case:** What problem does it solve?
   - **Proposed Solution:** How should it work?
   - **Alternatives:** Other approaches considered
   - **Examples:** Usage examples

For major features, consider writing an RFC (see [RFC Process](#rfc-process)).

### 🔧 Contributing Code

1. **Pick an Issue:** Find an issue labeled `good first issue` or `help wanted`
2. **Comment:** Comment on the issue that you'd like to work on it
3. **Fork & Branch:** Fork the repo and create a feature branch
4. **Implement:** Write code following our [Coding Standards](#coding-standards)
5. **Test:** Add tests and ensure all tests pass
6. **Document:** Update documentation as needed
7. **Submit PR:** Create a pull request with a clear description

---

## Development Setup

### Prerequisites

- **Rust:** 1.75.0 or later
- **PostgreSQL:** 16 or 17 (with dev packages)
- **cargo-pgrx:** 0.16.1
- **Git**

### Setup Steps

```bash
# 1. Clone the repository
git clone https://github.com/KSD-CO/rule-engine-postgres.git
cd rule-engine-postgres

# 2. Install cargo-pgrx
cargo install cargo-pgrx --version 0.16.1 --locked

# 3. Initialize pgrx (one-time setup)
cargo pgrx init --pg16 $(which pg_config)

# 4. Build and install the extension
cargo pgrx install --release

# 5. Run tests
cargo pgrx test
```

### Development Workflow

```bash
# Start development database
cargo pgrx run pg16

# In psql shell:
CREATE EXTENSION rule_engine_postgre_extensions;
SELECT rule_engine_version();

# Run specific tests
cargo test --test integration_tests

# Run integration tests in PostgreSQL
cargo pgrx test pg16

# Format code
cargo fmt

# Lint code
cargo clippy -- -D warnings

# Build documentation
cargo doc --no-deps --open
```

---

## Submitting Changes

### Pull Request Process

1. **Branch Naming:**
   - Feature: `feature/description`
   - Bug fix: `fix/description`
   - Documentation: `docs/description`
   - RFC implementation: `rfc-XXXX/description`

2. **Commit Messages:**
   - Use clear, descriptive commit messages
   - Start with a verb (Add, Fix, Update, Remove, etc.)
   - Reference issue numbers: `Fix #123: Description`
   - Examples:
     ```
     Add rule repository table schema
     Fix backward chaining infinite loop issue #45
     Update API documentation for rule_save function
     ```

3. **PR Description Template:**
   ```markdown
   ## Description
   [Clear description of changes]
   
   ## Motivation
   [Why is this change needed?]
   
   ## Changes
   - [ ] Change 1
   - [ ] Change 2
   
   ## Testing
   [How was this tested?]
   
   ## Checklist
   - [ ] Code follows style guidelines
   - [ ] Self-review completed
   - [ ] Tests added/updated
   - [ ] Documentation updated
   - [ ] No breaking changes (or documented)
   - [ ] All tests pass
   
   ## Related Issues
   Closes #123
   Related to #456
   ```

4. **Review Process:**
   - At least one maintainer approval required
   - All CI checks must pass
   - No unresolved comments
   - Squash commits before merge (optional)

---

## RFC Process

For major features or architectural changes, follow the RFC process:

### When to Write an RFC

Write an RFC for:
- New major features (see [Roadmap](docs/ROADMAP.md))
- Breaking API changes
- Significant architectural changes
- New dependencies or external integrations

### RFC Steps

1. **Copy Template:**
   ```bash
   cp docs/rfcs/0000-template.md docs/rfcs/XXXX-feature-name.md
   ```

2. **Write RFC:**
   - Fill out all sections thoroughly
   - Include examples and use cases
   - Consider alternatives
   - Address potential issues

3. **Submit for Discussion:**
   - Create PR with RFC
   - Open GitHub issue linking to RFC
   - Share in discussions

4. **Iterate:**
   - Address feedback
   - Update RFC based on discussion
   - Aim for consensus

5. **Decision:**
   - Maintainers approve/reject
   - Update RFC status
   - If approved, proceed to implementation

6. **Implementation:**
   - Create implementation PR
   - Reference RFC number in commits/PR
   - Update RFC with implementation notes

### RFC Template Sections

- **Summary:** One-paragraph overview
- **Motivation:** Why is this needed?
- **Detailed Design:** Technical specification
- **Examples:** Usage examples
- **Alternatives:** Other approaches considered
- **Drawbacks:** Potential issues
- **Dependencies:** What does this depend on?
- **Testing Strategy:** How will this be tested?

---

## Coding Standards

### Rust Style

- Follow [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/)
- Use `cargo fmt` for formatting
- Use `cargo clippy` for linting
- No warnings allowed (`-D warnings`)

### Code Organization

```
src/
  lib.rs           # Main entry point
  api/             # Public PostgreSQL functions
  core/            # Core business logic
  error/           # Error handling
  validation/      # Input validation
  repository/      # Rule repository (new)
  monitoring/      # Statistics & monitoring (new)
  testing/         # Testing framework (new)
```

### Naming Conventions

- **Functions:** `snake_case`
- **Types/Structs:** `PascalCase`
- **Constants:** `SCREAMING_SNAKE_CASE`
- **SQL Functions:** `snake_case` (e.g., `rule_save`)
- **SQL Tables:** `snake_case` (e.g., `rule_definitions`)

### Error Handling

```rust
// Use Result types for fallible operations
pub fn rule_save(name: &str) -> Result<i32, RuleEngineError> {
    validate_rule_name(name)?;
    // ...
}

// Use custom error types with codes
pub enum RuleEngineError {
    RuleNotFound(String),      // RE-101
    InvalidRuleName(String),   // RE-001
    ValidationFailed(String),  // RE-003
}
```

### Documentation

```rust
/// Save a rule to the repository with versioning.
///
/// # Arguments
/// * `name` - Unique rule name (alphanumeric + underscore/hyphen)
/// * `grl_content` - GRL rule definition
/// * `version` - Optional semantic version (auto-incremented if None)
///
/// # Returns
/// Rule ID on success
///
/// # Errors
/// * `RE-001` - Invalid rule name format
/// * `RE-002` - GRL content validation failed
///
/// # Example
/// ```rust
/// let rule_id = rule_save("discount_rule", "rule { ... }", Some("1.0.0"))?;
/// ```
#[pg_extern]
pub fn rule_save(...) -> Result<i32, RuleEngineError> {
    // Implementation
}
```

---

## Testing Guidelines

### Test Coverage Requirements

- **Unit Tests:** 80%+ coverage for new code
- **Integration Tests:** All public APIs
- **Performance Tests:** Benchmark critical paths
- **SQL Tests:** End-to-end scenarios

### Writing Tests

```rust
// Unit tests in src/
#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_rule_save_new() {
        let result = rule_save("test_rule", "rule { ... }", Some("1.0.0"));
        assert!(result.is_ok());
    }
    
    #[test]
    fn test_invalid_rule_name() {
        let result = rule_save("invalid name!", "rule { ... }", None);
        assert!(matches!(result, Err(RuleEngineError::InvalidRuleName(_))));
    }
}

// Integration tests in tests/
#[test]
fn test_rule_repository_workflow() {
    // Setup
    let mut conn = pgrx_tests::pg_test_connection();
    
    // Test
    conn.execute("SELECT rule_save('test', 'rule { ... }', '1.0.0')", &[]);
    let result = conn.query_one("SELECT rule_get('test')", &[]);
    
    // Assert
    assert_eq!(result.get::<_, String>(0), "rule { ... }");
}
```

### SQL Tests

```sql
-- tests/test_rule_repository.sql
BEGIN;

-- Test 1: Basic save and retrieve
SELECT rule_save('test_rule', 'rule "Test" { ... }', '1.0.0');
SELECT rule_get('test_rule') = 'rule "Test" { ... }' AS test_1_passed;

-- Test 2: Version management
SELECT rule_save('test_rule', 'rule "Test2" { ... }', '2.0.0');
SELECT COUNT(*) = 2 FROM rule_versions WHERE rule_id = 1 AS test_2_passed;

-- Test 3: Error handling
DO $$
BEGIN
    PERFORM rule_save('invalid name!', 'rule { ... }', '1.0.0');
    RAISE EXCEPTION 'Should have failed';
EXCEPTION
    WHEN OTHERS THEN
        -- Expected
END $$;

ROLLBACK;
```

### Running Tests

```bash
# All tests
cargo pgrx test

# Specific test
cargo test test_rule_save

# With output
cargo test -- --nocapture

# Integration tests only
cargo test --test integration_tests

# Benchmark tests
cargo bench
```

---

## Documentation

### Documentation Requirements

All contributions should include:

1. **Code Comments:** Document complex logic
2. **API Docs:** Rustdoc for all public functions
3. **SQL Docs:** Update `docs/api-reference.md`
4. **User Guides:** Add examples to relevant guides
5. **Changelog:** Update `CHANGELOG.md`

### Documentation Structure

```
docs/
  api-reference.md           # Complete API documentation
  ROADMAP.md                 # Product roadmap
  deployment/                # Deployment guides
  development/               # Development guides
  examples/                  # Usage examples
  guides/                    # Feature guides
  rfcs/                      # Design documents
```

### Writing Documentation

- **Clear and Concise:** Use simple language
- **Examples:** Include code examples
- **Complete:** Cover all parameters and return values
- **Errors:** Document all error conditions
- **Performance:** Note performance characteristics

### Updating API Reference

When adding new functions, update `docs/api-reference.md`:

```markdown
### `rule_save(name TEXT, grl_content TEXT, version TEXT) → INTEGER`

**Purpose:** Save a rule to the repository with versioning.

**Parameters:**
- `name` (TEXT): Unique rule name
- `grl_content` (TEXT): GRL rule definition
- `version` (TEXT): Semantic version

**Returns:** Rule ID (INTEGER)

**Example:**
```sql
SELECT rule_save('my_rule', 'rule "MyRule" { ... }', '1.0.0');
```

**Errors:**
- `RE-001`: Invalid rule name format
- `RE-002`: GRL validation failed
```

---

## Release Process

Maintainers will handle releases, but contributors should be aware:

1. **Version Bumping:** Follow [Semantic Versioning](https://semver.org/)
   - MAJOR: Breaking changes
   - MINOR: New features (backward compatible)
   - PATCH: Bug fixes

2. **Changelog:** Update `CHANGELOG.md` with all changes

3. **Release Notes:** Highlight major features/fixes

4. **Migration Guide:** Document any breaking changes

---

## Getting Help

- **Questions:** Open a [Discussion](https://github.com/KSD-CO/rule-engine-postgres/discussions)
- **Bugs:** Open an [Issue](https://github.com/KSD-CO/rule-engine-postgres/issues)
- **Chat:** Join our community (link TBD)

---

## Recognition

Contributors will be:
- Listed in `CONTRIBUTORS.md`
- Mentioned in release notes
- Credited in relevant documentation

Thank you for contributing! 🎉
