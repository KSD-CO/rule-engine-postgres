/// JSON manipulation built-in functions
use serde_json::Value;

/// Parse JSON string to object
/// Usage: JsonParse('{"name": "Alice"}')
pub fn parse(args: &[Value]) -> Result<Value, String> {
    if args.is_empty() {
        return Err("JsonParse requires 1 argument: JSON string".to_string());
    }

    let json_str = args[0]
        .as_str()
        .ok_or("JsonParse: argument must be a string")?;

    serde_json::from_str(json_str).map_err(|e| format!("Invalid JSON: {}", e))
}

/// Convert object to JSON string
/// Usage: JsonStringify({"name": "Alice"})
pub fn stringify(args: &[Value]) -> Result<Value, String> {
    if args.is_empty() {
        return Err("JsonStringify requires 1 argument: object".to_string());
    }

    serde_json::to_string(&args[0])
        .map(Value::String)
        .map_err(|e| format!("Failed to stringify: {}", e))
}

/// Get value from JSON object by path
/// Usage: JsonGet({"user": {"name": "Alice"}}, "user.name") -> "Alice"
pub fn get(args: &[Value]) -> Result<Value, String> {
    if args.len() < 2 {
        return Err("JsonGet requires 2 arguments: object, path".to_string());
    }

    let obj = &args[0];
    let path = args[1].as_str().ok_or("JsonGet: path must be a string")?;

    // Split path by dots
    let keys: Vec<&str> = path.split('.').collect();

    let mut current = obj;
    for key in keys {
        current = current
            .get(key)
            .ok_or_else(|| format!("Key '{}' not found", key))?;
    }

    Ok(current.clone())
}

/// Set value in JSON object by path
/// Usage: JsonSet({"user": {}}, "user.name", "Alice")
pub fn set(args: &[Value]) -> Result<Value, String> {
    if args.len() < 3 {
        return Err("JsonSet requires 3 arguments: object, path, value".to_string());
    }

    let mut obj = args[0].clone();
    let path = args[1].as_str().ok_or("JsonSet: path must be a string")?;
    let value = &args[2];

    // Split path by dots
    let keys: Vec<&str> = path.split('.').collect();

    if keys.is_empty() {
        return Err("Invalid path".to_string());
    }

    // Navigate to parent and set the final key
    let mut current = &mut obj;
    for (i, key) in keys.iter().enumerate() {
        if i == keys.len() - 1 {
            // Last key - set the value
            if let Some(map) = current.as_object_mut() {
                map.insert(key.to_string(), value.clone());
            } else {
                return Err(format!("Cannot set property '{}' on non-object", key));
            }
        } else {
            // Intermediate key - navigate deeper
            if !current.is_object() {
                return Err(format!("Path '{}' is not an object", key));
            }

            current = current
                .get_mut(key)
                .ok_or_else(|| format!("Key '{}' not found", key))?;
        }
    }

    Ok(obj)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_parse() {
        let result = parse(&[json!(r#"{"name": "Alice"}"#)]).unwrap();
        assert_eq!(result, json!({"name": "Alice"}));
    }

    #[test]
    fn test_stringify() {
        let result = stringify(&[json!({"name": "Alice"})]).unwrap();
        assert_eq!(result, json!(r#"{"name":"Alice"}"#));
    }

    #[test]
    fn test_get() {
        let obj = json!({"user": {"name": "Alice", "age": 30}});
        let result = get(&[obj, json!("user.name")]).unwrap();
        assert_eq!(result, json!("Alice"));
    }

    #[test]
    fn test_set() {
        let obj = json!({"user": {}});
        let result = set(&[obj, json!("user.name"), json!("Alice")]).unwrap();
        assert_eq!(result, json!({"user": {"name": "Alice"}}));
    }
}
