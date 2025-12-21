# GRL Preprocessing Design - Built-in Functions

## Overview

Transform GRL code with function calls into standard GRL by pre-computing function results and injecting into facts.

## Algorithm

### Step 1: Parse Function Calls

Regex pattern to find function calls:
```regex
(\w+)\(([^)]+)\)
```

Example matches:
- `IsValidEmail(Customer.email)` → function=`IsValidEmail`, args=`Customer.email`
- `DaysSince("2024-01-01")` → function=`DaysSince`, args=`"2024-01-01"`
- `Round(Price * 1.08, 2)` → function=`Round`, args=`Price * 1.08, 2`

### Step 2: Generate Unique Field Names

For each function call, create computed field:
```
IsValidEmail(Customer.email) → Customer.__func_0_isValidEmail
DaysSince(Order.date) → Order.__func_1_daysSince
```

### Step 3: Transform GRL Code

Replace function calls with computed fields:

**Input:**
```grl
rule "EmailCheck" {
    when IsValidEmail(Customer.email) == false
    then Customer.error = "Bad email";
}
```

**Output:**
```grl
rule "EmailCheck" {
    when Customer.__func_0_isValidEmail == false
    then Customer.error = "Bad email";
}
```

### Step 4: Compute Function Values

Before executing rule, evaluate all functions and inject into facts:

**Original Facts:**
```json
{
  "Customer": {
    "email": "invalid-email"
  }
}
```

**Enhanced Facts:**
```json
{
  "Customer": {
    "email": "invalid-email",
    "__func_0_isValidEmail": false  // ← Computed
  }
}
```

### Step 5: Execute Rule

Now execute transformed GRL with enhanced facts using standard `run_rule_engine()`.

## Implementation

### Pseudo-code

```rust
pub fn execute_rule_with_functions(
    grl_code: &str,
    facts: &mut Value
) -> Result<Value, String> {
    // 1. Find all function calls
    let function_calls = parse_function_calls(grl_code)?;

    // 2. Transform GRL code
    let mut transformed_grl = grl_code.to_string();
    let mut computed_fields = Vec::new();

    for (index, func_call) in function_calls.iter().enumerate() {
        // Generate unique field name
        let field_name = format!("__func_{}_{}", index, func_call.name.to_lowercase());

        // Replace in GRL
        transformed_grl = transformed_grl.replace(
            &func_call.original_text,
            &format!("{}.{}", func_call.context_object, field_name)
        );

        computed_fields.push((field_name, func_call));
    }

    // 3. Evaluate functions and inject into facts
    for (field_name, func_call) in computed_fields {
        // Evaluate function with current facts
        let result = evaluate_function(func_call, facts)?;

        // Inject into facts
        inject_computed_field(facts, &func_call.context_object, &field_name, result)?;
    }

    // 4. Execute transformed rule
    run_rule_engine(&transformed_grl, &serde_json::to_string(facts)?)
}
```

### Data Structures

```rust
struct FunctionCall {
    /// Original text: "IsValidEmail(Customer.email)"
    original_text: String,

    /// Function name: "IsValidEmail"
    name: String,

    /// Raw arguments: "Customer.email"
    raw_args: String,

    /// Parsed arguments: ["Customer.email"]
    args: Vec<FunctionArg>,

    /// Context object: "Customer"
    context_object: String,
}

enum FunctionArg {
    FieldAccess(String),      // Customer.email
    Literal(Value),           // "2024-01-01", 123, true
    Expression(String),       // Price * 1.08 (complex)
}
```

## Challenges

### Challenge 1: Nested Function Calls

```grl
Round(Abs(Price - 100), 2)
```

**Solution:** Parse inside-out, evaluate inner functions first.

### Challenge 2: Field Context Detection

```grl
when IsValidEmail(Customer.email) == false
```

Need to know field belongs to `Customer` object to inject `Customer.__func_0_isValidEmail`.

**Solution:** Parse arguments, extract root object (`Customer` from `Customer.email`).

### Challenge 3: Expression Arguments

```grl
Round(Price * 1.08, 2)
```

`Price * 1.08` is an expression, not a simple field.

**Solution:**
- Option A: Evaluate expression first using facts (complex)
- Option B: Limit to simple field/literal arguments for v1.7.0

### Challenge 4: Function Call in `then` Clause

```grl
then Customer.total = Round(subtotal + tax, 2);
```

Can't pre-compute because `subtotal + tax` not known before rule fires.

**Solution:**
- For v1.7.0: Only support functions in `when` conditions
- For v1.8.0: Add post-processing for `then` clauses

## Example Walkthrough

### Input

```grl
rule "ComplexRule" {
    salience 10;
    when
        IsValidEmail(Customer.email) == true &&
        DaysSince(Order.createdAt) > 30
    then
        Order.status = "overdue";
}
```

**Facts:**
```json
{
  "Customer": {"email": "user@example.com"},
  "Order": {"createdAt": "2024-01-01"}
}
```

### Step 1: Parse Functions

Found 2 function calls:
1. `IsValidEmail(Customer.email)`
2. `DaysSince(Order.createdAt)`

### Step 2: Transform GRL

```grl
rule "ComplexRule" {
    salience 10;
    when
        Customer.__func_0_isvalidemail == true &&
        Order.__func_1_dayssince > 30
    then
        Order.status = "overdue";
}
```

### Step 3: Compute Functions

```rust
// Evaluate IsValidEmail
let email = get_field(facts, "Customer.email"); // "user@example.com"
let valid = functions::execute_function("IsValidEmail", &[email])?;
// valid = true

// Evaluate DaysSince
let date = get_field(facts, "Order.createdAt"); // "2024-01-01"
let days = functions::execute_function("DaysSince", &[date])?;
// days = 354 (example)
```

### Step 4: Inject into Facts

```json
{
  "Customer": {
    "email": "user@example.com",
    "__func_0_isvalidemail": true
  },
  "Order": {
    "createdAt": "2024-01-01",
    "__func_1_dayssince": 354
  }
}
```

### Step 5: Execute

```rust
run_rule_engine(transformed_grl, enhanced_facts)
// Rule fires because:
//   Customer.__func_0_isvalidemail == true  ✓
//   Order.__func_1_dayssince > 30  ✓ (354 > 30)
```

## Pros and Cons

### Pros
✅ No need to fork rust-rule-engine
✅ Can ship immediately (v1.7.0-alpha)
✅ Full control over function execution
✅ Easy to debug (can inspect enhanced facts)

### Cons
❌ "Pollutes" facts object with computed fields
❌ Can't use computed values in other computations (yet)
❌ Complex expressions not supported initially
❌ "Hacky" - not native to GRL

## Recommendation

**Ship v1.7.0-alpha with Approach 2 (Preprocessing):**
1. Implement basic preprocessing for simple cases
2. Support functions in `when` conditions only
3. Document limitations clearly
4. Gather user feedback

**Then for v1.7.0-stable:**
- Improve preprocessing to handle complex expressions
- OR contribute to rust-rule-engine (Approach 1)
- OR wait for upstream to add plugin support

## Next Steps

1. Implement `parse_function_calls()` - regex-based parser
2. Implement `transform_grl()` - string replacement
3. Implement `evaluate_function()` - call our function registry
4. Implement `inject_computed_field()` - JSON manipulation
5. Wrap in `rule_execute_with_functions()` PostgreSQL function
6. Write tests
7. Document limitations
