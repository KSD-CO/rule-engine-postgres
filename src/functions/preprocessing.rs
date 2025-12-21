/// GRL Preprocessing for Built-in Functions
/// Transforms GRL code with function calls into standard GRL by:
/// 1. Parsing function calls from GRL
/// 2. Evaluating functions and injecting results into facts
/// 3. Replacing function calls with computed field references
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
    /// Context object where to inject computed value: "Customer"
    pub context_object: String,
    /// Unique field name for computed value: "__func_0_isvalidemail"
    pub computed_field: String,
}

/// Parse function calls from GRL code
pub fn parse_function_calls(grl_code: &str) -> Result<Vec<FunctionCall>, String> {
    let mut calls = Vec::new();

    // Regex to match function calls: FunctionName(args)
    // Matches: IsValidEmail(Customer.email), Round(Price * 1.08, 2), etc.
    let func_regex = Regex::new(r"([A-Z][a-zA-Z0-9_]*)\(([^)]+)\)")
        .map_err(|e| format!("Regex error: {}", e))?;

    for (index, cap) in func_regex.captures_iter(grl_code).enumerate() {
        let original_text = cap[0].to_string();
        let name = cap[1].to_string();
        let raw_args = cap[2].to_string();

        // Extract context object from first argument
        // e.g., "Customer.email" → "Customer"
        let context_object = extract_context_object(&raw_args)?;

        // Generate unique computed field name
        let computed_field = format!("__func_{}_{}", index, name.to_lowercase());

        calls.push(FunctionCall {
            original_text,
            name,
            raw_args,
            context_object,
            computed_field,
        });
    }

    Ok(calls)
}

/// Extract context object from function arguments
/// "Customer.email" → "Customer"
/// "Order.subtotal * 1.08, 2" → "Order"
fn extract_context_object(args: &str) -> Result<String, String> {
    // Find first field access pattern (Object.field)
    let field_regex = Regex::new(r"([A-Z][a-zA-Z0-9_]*)\.").unwrap();

    if let Some(cap) = field_regex.captures(args) {
        Ok(cap[1].to_string())
    } else {
        // If no context found, default to "Result"
        Ok("Result".to_string())
    }
}

/// Transform GRL code by replacing function calls with computed field references
pub fn transform_grl(grl_code: &str, function_calls: &[FunctionCall]) -> String {
    let mut transformed = grl_code.to_string();

    for call in function_calls {
        // Replace function call with computed field reference
        // IsValidEmail(Customer.email) → Customer.__func_0_isvalidemail
        let replacement = format!("{}.{}", call.context_object, call.computed_field);
        transformed = transformed.replace(&call.original_text, &replacement);
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

/// Resolve field reference from facts
/// "Customer.email" → Value from facts["Customer"]["email"]
fn resolve_field_reference(field_ref: &str, facts: &Value) -> Option<Value> {
    let parts: Vec<&str> = field_ref.split('.').collect();

    if parts.len() < 2 {
        return None;
    }

    let mut current = facts;
    for part in parts {
        current = current.get(part)?;
    }

    Some(current.clone())
}

/// Inject computed field into facts
pub fn inject_computed_field(
    facts: &mut Value,
    context_object: &str,
    field_name: &str,
    value: Value,
) -> Result<(), String> {
    // Get or create context object
    if !facts.is_object() {
        return Err("Facts must be a JSON object".to_string());
    }

    let facts_obj = facts.as_object_mut().ok_or("Facts must be a JSON object")?;

    // Get or create context object
    let context = facts_obj
        .entry(context_object)
        .or_insert_with(|| Value::Object(serde_json::Map::new()))
        .as_object_mut()
        .ok_or_else(|| format!("Context {} must be an object", context_object))?;

    // Inject computed field
    context.insert(field_name.to_string(), value);

    Ok(())
}

/// Main preprocessing function - transform GRL and enhance facts
pub fn preprocess_grl_with_functions(grl_code: &str, facts: &mut Value) -> Result<String, String> {
    // Step 1: Parse function calls
    let function_calls = parse_function_calls(grl_code)?;

    if function_calls.is_empty() {
        // No functions to process
        return Ok(grl_code.to_string());
    }

    // Step 2: Evaluate functions and inject into facts
    for call in &function_calls {
        let result = evaluate_function_call(call, facts)?;
        inject_computed_field(facts, &call.context_object, &call.computed_field, result)?;
    }

    // Step 3: Transform GRL code
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
        assert_eq!(calls[0].context_object, "Customer");
    }

    #[test]
    fn test_extract_context_object() {
        assert_eq!(
            extract_context_object("Customer.email").unwrap(),
            "Customer"
        );
        assert_eq!(
            extract_context_object("Order.total * 1.08, 2").unwrap(),
            "Order"
        );
    }

    #[test]
    fn test_transform_grl() {
        let grl = "Customer.valid = IsValidEmail(Customer.email);";
        let calls = vec![FunctionCall {
            original_text: "IsValidEmail(Customer.email)".to_string(),
            name: "IsValidEmail".to_string(),
            raw_args: "Customer.email".to_string(),
            context_object: "Customer".to_string(),
            computed_field: "__func_0_isvalidemail".to_string(),
        }];

        let transformed = transform_grl(grl, &calls);
        assert!(transformed.contains("Customer.__func_0_isvalidemail"));
    }

    #[test]
    fn test_resolve_field_reference() {
        let facts = json!({
            "Customer": {
                "email": "test@example.com"
            }
        });

        let value = resolve_field_reference("Customer.email", &facts);
        assert_eq!(value, Some(Value::String("test@example.com".to_string())));
    }

    #[test]
    fn test_inject_computed_field() {
        let mut facts = json!({
            "Customer": {
                "email": "test@example.com"
            }
        });

        inject_computed_field(&mut facts, "Customer", "__func_0_test", json!(true)).unwrap();

        assert_eq!(facts["Customer"]["__func_0_test"], json!(true));
    }

    #[test]
    fn test_preprocess_grl_with_functions() {
        let grl = r#"
            rule "EmailCheck" {
                when Customer.email != nil
                then Customer.valid = IsValidEmail(Customer.email);
            }
        "#;

        let mut facts = json!({
            "Customer": {
                "email": "test@example.com"
            }
        });

        let transformed = preprocess_grl_with_functions(grl, &mut facts).unwrap();

        // Check that function call was replaced
        assert!(transformed.contains("Customer.__func_0_isvalidemail"));

        // Check that computed field was injected
        assert!(facts["Customer"]["__func_0_isvalidemail"].is_boolean());
        assert_eq!(facts["Customer"]["__func_0_isvalidemail"], json!(true));
    }
}
