# v1.7.0 Release Notes - Built-in Functions Library

**Release Date**: TBD  
**Status**: ✅ Implementation Complete, Testing Complete

## 🎯 Overview

v1.7.0 introduces a comprehensive **Built-in Functions Library** with 24 functions across 4 categories, enabling powerful data transformations and validations directly in GRL rules.

## ✨ New Features

### Built-in Functions (24 total)

#### Date/Time Functions (5)
- `DaysSince(date)` - Calculate days elapsed since a specific date
- `AddDays(date, days)` - Add days to a date  
- `FormatDate(date, format)` - Format dates with custom patterns
- `Now()` - Get current timestamp
- `Today()` - Get current date

#### String Functions (8)
- `IsValidEmail(email)` - Email validation with regex
- `Contains(string, substring)` - Substring search
- `RegexMatch(string, pattern)` - Pattern matching
- `ToUpper(string)` / `ToLower(string)` - Case conversion
- `Trim(string)` - Whitespace removal
- `Length(string)` - String length
- `Substring(string, start, length)` - Extract substring

#### Math Functions (7)
- `Round(number, decimals)` - Precision rounding
- `Abs(number)` - Absolute value
- `Min(n1, n2, ...)` / `Max(n1, n2, ...)` - Min/Max of numbers
- `Floor(number)` / `Ceil(number)` - Floor/Ceiling
- `Sqrt(number)` - Square root

#### JSON Functions (4)
- `JsonParse(string)` - Parse JSON strings
- `JsonStringify(object)` - Serialize to JSON
- `JsonGet(object, path)` - Get nested values
- `JsonSet(object, path, value)` - Set nested values

### GRL Preprocessing Engine

Implemented intelligent preprocessing layer that:
- Automatically detects function calls in GRL
- Pre-evaluates functions before rule execution
- Injects computed values into facts
- Transforms GRL for seamless execution

## 📝 Usage Examples

### Email Validation Rule
```sql
SELECT run_rule_engine(
    '{"Customer": {"email": "user@example.com", "approved": false}}',
    'rule "ValidateEmail" {
        when IsValidEmail(Customer.email) == true
        then Customer.approved = true;
    }'
);
```

### Price Calculation with Rounding
```sql
SELECT run_rule_engine(
    '{"Order": {"subtotal": 99.99, "taxRate": 0.08, "needsReview": false}}',
    'rule "CheckTotal" {
        when Round(Order.subtotal * (1 + Order.taxRate), 2) > 100.0
        then Order.needsReview = true;
    }'
);
```

### Date-based Rules
```sql
SELECT run_rule_engine(
    '{"Order": {"createdAt": "2024-01-01", "isExpired": false}}',
    'rule "CheckExpiration" {
        when DaysSince(Order.createdAt) > 90
        then Order.isExpired = true;
    }'
);
```

## 🔧 Technical Details

### Architecture
- **Preprocessing Layer**: `src/functions/preprocessing.rs` (289 lines)
- **Function Modules**: `datetime.rs`, `string.rs`, `math.rs`, `json.rs`
- **Registry**: Lazy-static global function registry
- **Integration**: Seamless integration into `run_rule_engine()`

### Performance
- Functions are pre-evaluated before rule execution
- No runtime overhead during rule evaluation
- Computed values cached in facts with hidden fields

## ⚠️ Known Limitations

### Not Supported in v1.7.0
- Nested function calls: `Contains(ToUpper(name), "X")`
- Complex expressions as arguments: `Round(price * tax, 2)`
- Function calls in `then` assignments: `result = ToUpper(input)`

### Workarounds
- Use functions only in `when` conditions
- Use simple field references as function arguments
- Pre-compute complex values before rules

## 🆕 New SQL Functions

```sql
-- Execute a built-in function from SQL
SELECT rule_function_call('Round', '[3.14159, 2]'::jsonb);
-- Returns: 3.14

-- List all available functions
SELECT * FROM rule_function_list();
```

## 📦 Installation

```bash
# Build and install
cargo build --release --no-default-features --features pg17
./install.sh

# Or upgrade existing installation
psql -d your_database -c "
  ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.7.0';
"
```

## 🧪 Testing

Comprehensive test suite with 24+ test cases covering all functions.

```bash
# Run tests
psql -d postgres -f tests/test_builtin_functions_minimal.sql
```

## 📚 Documentation

- Full function reference: See Wiki
- Usage examples: See `examples/` directory
- API documentation: `docs/BUILTIN_FUNCTIONS.md`

## 🐛 Bug Fixes

None - this is a pure feature release.

## 🔄 Migration Guide

### From v1.6.0 to v1.7.0

No breaking changes! All existing GRL rules continue to work.

Simply add function calls to your rules:

**Before (v1.6.0):**
```grl
rule "ValidateEmail" {
    when Customer.email == "user@example.com"
    then Customer.valid = true;
}
```

**After (v1.7.0):**
```grl
rule "ValidateEmail" {
    when IsValidEmail(Customer.email) == true
    then Customer.valid = true;
}
```

## 🙏 Credits

- Implemented by: [Your Name]
- Inspired by: rust-rule-engine plugins system
- Approach: GRL preprocessing (see DESIGN_PREPROCESSING.md)

## 🔮 Roadmap (v1.8.0)

Planned enhancements:
- Support nested function calls
- Expression evaluation in function arguments
- Function calls in `then` clauses
- Additional functions (crypto, HTTP, etc.)

---

**Full Changelog**: v1.6.0...v1.7.0
