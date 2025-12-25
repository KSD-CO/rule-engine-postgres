/// GRL Preprocessing for Built-in Functions
/// Transforms GRL code with function calls into standard GRL by:
/// 1. Parsing function calls from GRL
/// 2. Evaluating functions and getting results
/// 3. Replacing function calls with literal values directly
use regex::Regex;
use serde_json::Value;

/// Represents a function call found in GRL code
#[derive(Debug, Clone)]
pub struct FunctionCall {
    /// Original text: "IsValidEmail(Customer.email)"
    pub original_text: String,
    /// Function name: "IsValidEmail"
    pub name: String,
    /// Raw arguments: "Customer.email"
    pub raw_args: String,
    /// Evaluated result value (computed during preprocessing)
    pub result_value: Option<Value>,
    /// Whether this function is in a 'when' clause (true) or 'then' clause (false)
    pub in_when_clause: bool,
    /// Computed field name for when clause functions (e.g., "__func_0_isvalidemail")
    pub computed_field: Option<String>,
}

/// Parse function calls from GRL code and detect their context (when vs then)
pub fn parse_function_calls(grl_code: &str) -> Result<Vec<FunctionCall>, String> {
    let mut calls = Vec::new();
    let mut func_counter = 0;

    // Regex to match function calls: FunctionName(args)
    // Matches: IsValidEmail(Customer.email), Round(Price * 1.08, 2), etc.
    let func_regex = Regex::new(r"([A-Z][a-zA-Z0-9_]*)\(([^)]+)\)")
        .map_err(|e| format!("Regex error: {}", e))?;

    for cap in func_regex.captures_iter(grl_code) {
        let original_text = cap[0].to_string();
        let name = cap[1].to_string();
        let raw_args = cap[2].to_string();

        // Detect if function is in 'when' or 'then' clause
        let in_when_clause = is_in_when_clause(grl_code, &original_text);

        // Generate computed field name for when clause functions
        let computed_field = if in_when_clause {
            // Extract context from first argument (e.g., "Order.createdAt" → "Order")
            let context = extract_context_from_args(&raw_args);
            let field_name = if let Some(ctx) = context {
                format!("{}.{}_{}_{}", ctx, "__func", func_counter, name.to_lowercase())
            } else {
                format!("__func_{}_{}", func_counter, name.to_lowercase())
            };
            func_counter += 1;
            Some(field_name)
        } else {
            None
        };

        calls.push(FunctionCall {
            original_text,
            name,
            raw_args,
            result_value: None, // Will be filled during evaluation
            in_when_clause,
            computed_field,
        });
    }

    Ok(calls)
}

/// Extract context object from function arguments
/// Examples:
///   "Order.createdAt" → Some("Order")
///   "Customer.email, Customer.name" → Some("Customer")
///   "42, 100" → None
fn extract_context_from_args(raw_args: &str) -> Option<String> {
    // Get first argument
    let first_arg = raw_args.split(',').next()?.trim();

    // Check if it's a dotted field reference (e.g., "Order.createdAt")
    if first_arg.contains('.') && !first_arg.starts_with('"') {
        // Extract the first part before the dot
        let parts: Vec<&str> = first_arg.split('.').collect();
        if parts.len() >= 2 {
            return Some(parts[0].to_string());
        }
    }

    None
}

/// Detect if a function call is in a 'when' clause vs 'then' clause
fn is_in_when_clause(grl_code: &str, function_text: &str) -> bool {
    // Find the position of the function call
    if let Some(func_pos) = grl_code.find(function_text) {
        // Look backwards from function position to find the nearest 'when' or 'then'
        let before_func = &grl_code[..func_pos];

        // Find last occurrence of 'when' and 'then' before this function
        let last_when = before_func.rfind("when ");
        let last_then = before_func.rfind("then ");

        match (last_when, last_then) {
            (Some(when_pos), Some(then_pos)) => when_pos > then_pos,
            (Some(_), None) => true,  // Only found 'when'
            (None, Some(_)) => false, // Only found 'then'
            (None, None) => false,    // Default to 'then' context
        }
    } else {
        false
    }
}

/// Convert serde_json::Value to GRL literal string
/// Examples:
///   true → "true"
///   false → "false"
///   123 → "123"
///   45.67 → "45.67"
///   "hello" → "\"hello\""
///   null → "nil"
fn value_to_grl_literal(value: &Value) -> String {
    match value {
        Value::Null => "nil".to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => n.to_string(),
        Value::String(s) => format!("\"{}\"", s.replace('"', "\\\"")),
        Value::Array(_) => "nil".to_string(), // Arrays not supported in GRL literals
        Value::Object(_) => "nil".to_string(), // Objects not supported in GRL literals
    }
}

/// Transform GRL code by replacing function calls
/// - Functions in 'then' clauses → replaced with literal values
/// - Functions in 'when' clauses → replaced with field references
pub fn transform_grl(grl_code: &str, function_calls: &[FunctionCall]) -> String {
    let mut transformed = grl_code.to_string();

    for call in function_calls {
        if call.in_when_clause {
            // For 'when' clauses: replace with field reference
            if let Some(ref field) = call.computed_field {
                transformed = transformed.replace(&call.original_text, field);
            }
        } else {
            // For 'then' clauses: replace with literal value
            if let Some(ref value) = call.result_value {
                let literal = value_to_grl_literal(value);
                transformed = transformed.replace(&call.original_text, &literal);
            }
        }
    }

    transformed
}

/// Evaluate a function call and return the result
pub fn evaluate_function_call(call: &FunctionCall, facts: &Value) -> Result<Value, String> {
    // Parse arguments and resolve field references
    let args = parse_and_resolve_args(&call.raw_args, facts)?;

    // Execute the function
    super::execute_function(&call.name, &args)
}

/// Parse function arguments and resolve field references from facts
fn parse_and_resolve_args(raw_args: &str, facts: &Value) -> Result<Vec<Value>, String> {
    let mut args = Vec::new();

    // Split arguments by comma (simple approach - doesn't handle nested commas)
    for arg_str in raw_args.split(',') {
        let arg_trimmed = arg_str.trim();

        // Try to resolve as field reference first (e.g., "Customer.email")
        if let Some(value) = resolve_field_reference(arg_trimmed, facts) {
            args.push(value);
        } else if arg_trimmed.starts_with('"') && arg_trimmed.ends_with('"') {
            // String literal
            let s = arg_trimmed.trim_matches('"');
            args.push(Value::String(s.to_string()));
        } else if let Ok(num) = arg_trimmed.parse::<i64>() {
            // Integer literal
            args.push(Value::Number(num.into()));
        } else if let Ok(num) = arg_trimmed.parse::<f64>() {
            // Float literal
            args.push(
                serde_json::Number::from_f64(num)
                    .map(Value::Number)
                    .unwrap_or(Value::Null),
            );
        } else if arg_trimmed == "true" {
            args.push(Value::Bool(true));
        } else if arg_trimmed == "false" {
            args.push(Value::Bool(false));
        } else if arg_trimmed == "nil" || arg_trimmed == "null" {
            args.push(Value::Null);
        } else {
            // Try to evaluate as expression (complex case)
            // For v1.7.0, we'll just pass it as a string
            args.push(Value::String(arg_trimmed.to_string()));
        }
    }

    Ok(args)
}

/// Resolve field reference from facts (supports both nested and flat formats)
/// Nested: facts["Customer"]["email"]
/// Flat: facts["Customer.email"]
fn resolve_field_reference(field_ref: &str, facts: &Value) -> Option<Value> {
    // Try flattened dotted key first (e.g., "Customer.email")
    if let Some(value) = facts.get(field_ref) {
        return Some(value.clone());
    }

    // Try nested access as fallback
    let parts: Vec<&str> = field_ref.split('.').collect();
    if parts.len() < 2 {
        // Single part - try direct access
        return facts.get(field_ref).cloned();
    }

    let mut current = facts;
    for part in parts {
        current = current.get(part)?;
    }

    Some(current.clone())
}


/// Main preprocessing function - transform GRL by evaluating functions
/// - Functions in 'when' clauses: inject into facts as fields
/// - Functions in 'then' clauses: replace with literal values
pub fn preprocess_grl_with_functions(grl_code: &str, facts: &mut Value) -> Result<String, String> {
    // Step 1: Parse function calls and detect context (when vs then)
    let mut function_calls = parse_function_calls(grl_code)?;

    if function_calls.is_empty() {
        // No functions to process
        return Ok(grl_code.to_string());
    }

    // Step 2: Evaluate functions and store results
    for call in &mut function_calls {
        let result = evaluate_function_call(call, facts)?;
        call.result_value = Some(result.clone());

        // Step 3: For 'when' clause functions, inject result into facts
        if call.in_when_clause {
            if let Some(ref field_name) = call.computed_field {
                // Inject using the dotted key format (e.g., "Order.__func_0_dayssince")
                // This matches the flattened facts format
                if let Some(obj) = facts.as_object_mut() {
                    obj.insert(field_name.clone(), result);
                }
            }
        }
    }

    // Step 4: Transform GRL code
    // - 'when' clauses: replace with field references
    // - 'then' clauses: replace with literal values
    let transformed_grl = transform_grl(grl_code, &function_calls);

    Ok(transformed_grl)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_parse_function_calls() {
        let grl = r#"
            rule "Test" {
                when Customer.active == true
                then Customer.valid = IsValidEmail(Customer.email);
            }
        "#;

        let calls = parse_function_calls(grl).unwrap();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].name, "IsValidEmail");
        assert_eq!(calls[0].raw_args, "Customer.email");
        assert_eq!(calls[0].in_when_clause, false); // Function is in 'then' clause
        assert!(calls[0].computed_field.is_none()); // No computed field for 'then' functions
    }

    #[test]
    fn test_parse_function_calls_in_when_clause() {
        let grl = r#"
            rule "Test" {
                when DaysSince(Order.createdAt) > 90
                then Order.isExpired = true;
            }
        "#;

        let calls = parse_function_calls(grl).unwrap();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].name, "DaysSince");
        assert_eq!(calls[0].in_when_clause, true); // Function is in 'when' clause
        assert!(calls[0].computed_field.is_some()); // Has computed field for 'when' functions

        // Check that computed field includes context (Order.__func_0_dayssince)
        let computed_field = calls[0].computed_field.as_ref().unwrap();
        assert!(computed_field.starts_with("Order."));
    }

    #[test]
    fn test_value_to_grl_literal() {
        assert_eq!(value_to_grl_literal(&json!(true)), "true");
        assert_eq!(value_to_grl_literal(&json!(false)), "false");
        assert_eq!(value_to_grl_literal(&json!(123)), "123");
        assert_eq!(value_to_grl_literal(&json!(45.67)), "45.67");
        assert_eq!(value_to_grl_literal(&json!("hello")), "\"hello\"");
        assert_eq!(value_to_grl_literal(&json!(null)), "nil");
    }

    #[test]
    fn test_transform_grl_then_clause() {
        let grl = "Customer.valid = IsValidEmail(Customer.email);";
        let calls = vec![FunctionCall {
            original_text: "IsValidEmail(Customer.email)".to_string(),
            name: "IsValidEmail".to_string(),
            raw_args: "Customer.email".to_string(),
            result_value: Some(json!(true)),
            in_when_clause: false,
            computed_field: None,
        }];

        let transformed = transform_grl(grl, &calls);
        assert!(transformed.contains("Customer.valid = true"));
        assert!(!transformed.contains("IsValidEmail"));
    }

    #[test]
    fn test_transform_grl_when_clause() {
        let grl = "when DaysSince(Order.createdAt) > 90";
        let calls = vec![FunctionCall {
            original_text: "DaysSince(Order.createdAt)".to_string(),
            name: "DaysSince".to_string(),
            raw_args: "Order.createdAt".to_string(),
            result_value: Some(json!(724)),
            in_when_clause: true,
            computed_field: Some("Order.__func_0_dayssince".to_string()),
        }];

        let transformed = transform_grl(grl, &calls);
        assert!(transformed.contains("when Order.__func_0_dayssince > 90"));
        assert!(!transformed.contains("DaysSince"));
    }

    #[test]
    fn test_resolve_field_reference_nested() {
        let facts = json!({
            "Customer": {
                "email": "test@example.com"
            }
        });

        let value = resolve_field_reference("Customer.email", &facts);
        assert_eq!(value, Some(Value::String("test@example.com".to_string())));
    }

    #[test]
    fn test_resolve_field_reference_flat() {
        let facts = json!({
            "Customer.email": "test@example.com"
        });

        let value = resolve_field_reference("Customer.email", &facts);
        assert_eq!(value, Some(Value::String("test@example.com".to_string())));
    }

    #[test]
    fn test_preprocess_grl_with_functions_then_clause() {
        let grl = r#"
            rule "EmailCheck" {
                when Customer.email != nil
                then Customer.valid = IsValidEmail(Customer.email);
            }
        "#;

        let mut facts = json!({
            "Customer.email": "test@example.com"
        });

        let transformed = preprocess_grl_with_functions(grl, &mut facts).unwrap();

        // Check that function call was replaced with literal value (true)
        assert!(transformed.contains("Customer.valid = true"));
        assert!(!transformed.contains("IsValidEmail"));

        // Check that facts were NOT modified (no injection for 'then' functions)
        assert!(facts.get("__func_0_isvalidemail").is_none());
    }

    #[test]
    fn test_preprocess_grl_with_functions_when_clause() {
        let grl = r#"
            rule "CheckAge" {
                when DaysSince(Order.createdAt) > 90
                then Order.isExpired = true;
            }
        "#;

        let mut facts = json!({
            "Order.createdAt": "2024-01-01"
        });

        let transformed = preprocess_grl_with_functions(grl, &mut facts).unwrap();

        // Check that function call was replaced with field reference (includes context)
        assert!(transformed.contains("when Order.__func_0_dayssince > 90"));
        assert!(!transformed.contains("DaysSince"));

        // Check that facts were modified (injection for 'when' functions)
        // Should be injected as dotted key "Order.__func_0_dayssince"
        assert!(facts.get("Order.__func_0_dayssince").is_some());
        // The value should be the number of days
        assert!(facts["Order.__func_0_dayssince"].is_number());
    }
}
