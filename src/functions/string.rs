/// String manipulation built-in functions
use regex::Regex;
use serde_json::Value;

/// Validate email address
/// Usage: IsValidEmail("user@example.com")
pub fn is_valid_email(args: &[Value]) -> Result<Value, String> {
    if args.is_empty() {
        return Err("IsValidEmail requires 1 argument: email string".to_string());
    }

    let email = args[0]
        .as_str()
        .ok_or("IsValidEmail: argument must be a string")?;

    // Simple email regex (RFC 5322 simplified)
    let email_regex = Regex::new(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")
        .map_err(|e| format!("Regex error: {}", e))?;

    Ok(Value::Bool(email_regex.is_match(email)))
}

/// Check if string contains substring
/// Usage: Contains("hello world", "world")
pub fn contains(args: &[Value]) -> Result<Value, String> {
    if args.len() < 2 {
        return Err("Contains requires 2 arguments: string, substring".to_string());
    }

    let haystack = args[0]
        .as_str()
        .ok_or("Contains: first argument must be a string")?;

    let needle = args[1]
        .as_str()
        .ok_or("Contains: second argument must be a string")?;

    Ok(Value::Bool(haystack.contains(needle)))
}

/// Match string against regex pattern
/// Usage: RegexMatch("hello123", "\\d+")
pub fn regex_match(args: &[Value]) -> Result<Value, String> {
    if args.len() < 2 {
        return Err("RegexMatch requires 2 arguments: string, pattern".to_string());
    }

    let text = args[0]
        .as_str()
        .ok_or("RegexMatch: first argument must be a string")?;

    let pattern = args[1]
        .as_str()
        .ok_or("RegexMatch: second argument must be a string")?;

    let re = Regex::new(pattern).map_err(|e| format!("Invalid regex: {}", e))?;

    Ok(Value::Bool(re.is_match(text)))
}

/// Convert string to uppercase
/// Usage: ToUpper("hello")
pub fn to_upper(args: &[Value]) -> Result<Value, String> {
    if args.is_empty() {
        return Err("ToUpper requires 1 argument: string".to_string());
    }

    let text = args[0]
        .as_str()
        .ok_or("ToUpper: argument must be a string")?;

    Ok(Value::String(text.to_uppercase()))
}

/// Convert string to lowercase
/// Usage: ToLower("HELLO")
pub fn to_lower(args: &[Value]) -> Result<Value, String> {
    if args.is_empty() {
        return Err("ToLower requires 1 argument: string".to_string());
    }

    let text = args[0]
        .as_str()
        .ok_or("ToLower: argument must be a string")?;

    Ok(Value::String(text.to_lowercase()))
}

/// Trim whitespace from both ends
/// Usage: Trim("  hello  ")
pub fn trim(args: &[Value]) -> Result<Value, String> {
    if args.is_empty() {
        return Err("Trim requires 1 argument: string".to_string());
    }

    let text = args[0].as_str().ok_or("Trim: argument must be a string")?;

    Ok(Value::String(text.trim().to_string()))
}

/// Get string length
/// Usage: Length("hello")
pub fn length(args: &[Value]) -> Result<Value, String> {
    if args.is_empty() {
        return Err("Length requires 1 argument: string".to_string());
    }

    let text = args[0]
        .as_str()
        .ok_or("Length: argument must be a string")?;

    Ok(Value::Number(text.len().into()))
}

/// Get substring
/// Usage: Substring("hello", 1, 3) -> "ell"
pub fn substring(args: &[Value]) -> Result<Value, String> {
    if args.len() < 3 {
        return Err("Substring requires 3 arguments: string, start, length".to_string());
    }

    let text = args[0]
        .as_str()
        .ok_or("Substring: first argument must be a string")?;

    let start = args[1]
        .as_u64()
        .ok_or("Substring: start must be a number")? as usize;

    let length = args[2]
        .as_u64()
        .ok_or("Substring: length must be a number")? as usize;

    if start >= text.len() {
        return Err(format!("Start index {} out of bounds", start));
    }

    let end = std::cmp::min(start + length, text.len());
    let result = &text[start..end];

    Ok(Value::String(result.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_is_valid_email() {
        assert_eq!(
            is_valid_email(&[json!("user@example.com")]).unwrap(),
            json!(true)
        );
        assert_eq!(
            is_valid_email(&[json!("invalid-email")]).unwrap(),
            json!(false)
        );
    }

    #[test]
    fn test_contains() {
        assert_eq!(
            contains(&[json!("hello world"), json!("world")]).unwrap(),
            json!(true)
        );
        assert_eq!(
            contains(&[json!("hello world"), json!("foo")]).unwrap(),
            json!(false)
        );
    }

    #[test]
    fn test_regex_match() {
        assert_eq!(
            regex_match(&[json!("hello123"), json!(r"\d+")]).unwrap(),
            json!(true)
        );
        assert_eq!(
            regex_match(&[json!("hello"), json!(r"\d+")]).unwrap(),
            json!(false)
        );
    }

    #[test]
    fn test_to_upper() {
        assert_eq!(to_upper(&[json!("hello")]).unwrap(), json!("HELLO"));
    }

    #[test]
    fn test_to_lower() {
        assert_eq!(to_lower(&[json!("HELLO")]).unwrap(), json!("hello"));
    }

    #[test]
    fn test_trim() {
        assert_eq!(trim(&[json!("  hello  ")]).unwrap(), json!("hello"));
    }

    #[test]
    fn test_length() {
        assert_eq!(length(&[json!("hello")]).unwrap(), json!(5));
    }

    #[test]
    fn test_substring() {
        assert_eq!(
            substring(&[json!("hello"), json!(1), json!(3)]).unwrap(),
            json!("ell")
        );
    }
}
