/// Math built-in functions
use serde_json::Value;

/// Round a number to specified decimal places
/// Usage: Round(3.14159, 2) -> 3.14
pub fn round(args: &[Value]) -> Result<Value, String> {
    if args.is_empty() {
        return Err("Round requires at least 1 argument: number".to_string());
    }

    let num = args[0]
        .as_f64()
        .ok_or("Round: first argument must be a number")?;

    let decimals = if args.len() > 1 {
        args[1]
            .as_u64()
            .ok_or("Round: second argument must be a number")? as u32
    } else {
        0
    };

    let multiplier = 10_f64.powi(decimals as i32);
    let rounded = (num * multiplier).round() / multiplier;

    Ok(serde_json::Number::from_f64(rounded)
        .map(Value::Number)
        .unwrap_or(Value::Null))
}

/// Absolute value
/// Usage: Abs(-5) -> 5
pub fn abs(args: &[Value]) -> Result<Value, String> {
    if args.is_empty() {
        return Err("Abs requires 1 argument: number".to_string());
    }

    let num = args[0].as_f64().ok_or("Abs: argument must be a number")?;

    Ok(serde_json::Number::from_f64(num.abs())
        .map(Value::Number)
        .unwrap_or(Value::Null))
}

/// Minimum of two or more numbers
/// Usage: Min(5, 10, 3) -> 3
pub fn min(args: &[Value]) -> Result<Value, String> {
    if args.len() < 2 {
        return Err("Min requires at least 2 arguments".to_string());
    }

    let numbers: Result<Vec<f64>, String> = args
        .iter()
        .map(|v| {
            v.as_f64()
                .ok_or_else(|| "Min: all arguments must be numbers".to_string())
        })
        .collect();

    let numbers = numbers?;
    let min_val = numbers.into_iter().fold(f64::INFINITY, |a, b| a.min(b));

    Ok(serde_json::Number::from_f64(min_val)
        .map(Value::Number)
        .unwrap_or(Value::Null))
}

/// Maximum of two or more numbers
/// Usage: Max(5, 10, 3) -> 10
pub fn max(args: &[Value]) -> Result<Value, String> {
    if args.len() < 2 {
        return Err("Max requires at least 2 arguments".to_string());
    }

    let numbers: Result<Vec<f64>, String> = args
        .iter()
        .map(|v| {
            v.as_f64()
                .ok_or_else(|| "Max: all arguments must be numbers".to_string())
        })
        .collect();

    let numbers = numbers?;
    let max_val = numbers.into_iter().fold(f64::NEG_INFINITY, |a, b| a.max(b));

    Ok(serde_json::Number::from_f64(max_val)
        .map(Value::Number)
        .unwrap_or(Value::Null))
}

/// Floor (round down)
/// Usage: Floor(3.7) -> 3
pub fn floor(args: &[Value]) -> Result<Value, String> {
    if args.is_empty() {
        return Err("Floor requires 1 argument: number".to_string());
    }

    let num = args[0].as_f64().ok_or("Floor: argument must be a number")?;

    Ok(serde_json::Number::from_f64(num.floor())
        .map(Value::Number)
        .unwrap_or(Value::Null))
}

/// Ceiling (round up)
/// Usage: Ceil(3.2) -> 4
pub fn ceil(args: &[Value]) -> Result<Value, String> {
    if args.is_empty() {
        return Err("Ceil requires 1 argument: number".to_string());
    }

    let num = args[0].as_f64().ok_or("Ceil: argument must be a number")?;

    Ok(serde_json::Number::from_f64(num.ceil())
        .map(Value::Number)
        .unwrap_or(Value::Null))
}

/// Square root
/// Usage: Sqrt(16) -> 4
pub fn sqrt(args: &[Value]) -> Result<Value, String> {
    if args.is_empty() {
        return Err("Sqrt requires 1 argument: number".to_string());
    }

    let num = args[0].as_f64().ok_or("Sqrt: argument must be a number")?;

    if num < 0.0 {
        return Err("Sqrt: cannot take square root of negative number".to_string());
    }

    Ok(serde_json::Number::from_f64(num.sqrt())
        .map(Value::Number)
        .unwrap_or(Value::Null))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_round() {
        assert_eq!(round(&[json!(3.14159), json!(2)]).unwrap(), json!(3.14));
        assert_eq!(round(&[json!(3.7)]).unwrap(), json!(4.0));
    }

    #[test]
    fn test_abs() {
        assert_eq!(abs(&[json!(-5.5)]).unwrap(), json!(5.5));
        assert_eq!(abs(&[json!(5.5)]).unwrap(), json!(5.5));
    }

    #[test]
    fn test_min() {
        assert_eq!(min(&[json!(5), json!(10), json!(3)]).unwrap(), json!(3.0));
    }

    #[test]
    fn test_max() {
        assert_eq!(max(&[json!(5), json!(10), json!(3)]).unwrap(), json!(10.0));
    }

    #[test]
    fn test_floor() {
        assert_eq!(floor(&[json!(3.7)]).unwrap(), json!(3.0));
    }

    #[test]
    fn test_ceil() {
        assert_eq!(ceil(&[json!(3.2)]).unwrap(), json!(4.0));
    }

    #[test]
    fn test_sqrt() {
        assert_eq!(sqrt(&[json!(16)]).unwrap(), json!(4.0));
    }
}
