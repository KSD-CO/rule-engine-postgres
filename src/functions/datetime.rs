/// Date/time built-in functions
use chrono::{DateTime, Duration, NaiveDate, Utc};
use serde_json::Value;

/// Calculate days since a given date
/// Usage: DaysSince("2024-01-01")
pub fn days_since(args: &[Value]) -> Result<Value, String> {
    if args.is_empty() {
        return Err("DaysSince requires 1 argument: date string".to_string());
    }

    let date_str = args[0]
        .as_str()
        .ok_or("DaysSince: argument must be a string")?;

    let date = NaiveDate::parse_from_str(date_str, "%Y-%m-%d")
        .map_err(|e| format!("Invalid date format: {}", e))?;

    let now = Utc::now().date_naive();
    let days = now.signed_duration_since(date).num_days();

    Ok(Value::Number(days.into()))
}

/// Add days to a date
/// Usage: AddDays("2024-01-01", 30)
pub fn add_days(args: &[Value]) -> Result<Value, String> {
    if args.len() < 2 {
        return Err("AddDays requires 2 arguments: date string, days".to_string());
    }

    let date_str = args[0]
        .as_str()
        .ok_or("AddDays: first argument must be a string")?;

    let days = args[1]
        .as_i64()
        .ok_or("AddDays: second argument must be a number")?;

    let date = NaiveDate::parse_from_str(date_str, "%Y-%m-%d")
        .map_err(|e| format!("Invalid date format: {}", e))?;

    let new_date = date + Duration::days(days);

    Ok(Value::String(new_date.format("%Y-%m-%d").to_string()))
}

/// Format a date with custom format
/// Usage: FormatDate("2024-01-01", "%B %d, %Y") -> "January 01, 2024"
pub fn format_date(args: &[Value]) -> Result<Value, String> {
    if args.len() < 2 {
        return Err("FormatDate requires 2 arguments: date string, format".to_string());
    }

    let date_str = args[0]
        .as_str()
        .ok_or("FormatDate: first argument must be a string")?;

    let format = args[1]
        .as_str()
        .ok_or("FormatDate: second argument must be a string")?;

    let date = NaiveDate::parse_from_str(date_str, "%Y-%m-%d")
        .map_err(|e| format!("Invalid date format: {}", e))?;

    Ok(Value::String(date.format(format).to_string()))
}

/// Get current timestamp
/// Usage: Now()
pub fn now(_args: &[Value]) -> Result<Value, String> {
    let now: DateTime<Utc> = Utc::now();
    Ok(Value::String(now.to_rfc3339()))
}

/// Get current date (without time)
/// Usage: Today()
pub fn today(_args: &[Value]) -> Result<Value, String> {
    let today = Utc::now().date_naive();
    Ok(Value::String(today.format("%Y-%m-%d").to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_days_since() {
        let result = days_since(&[json!("2024-01-01")]);
        assert!(result.is_ok());
        // Should be positive number (days since Jan 1, 2024)
        assert!(result.unwrap().as_i64().unwrap() > 0);
    }

    #[test]
    fn test_add_days() {
        let result = add_days(&[json!("2024-01-01"), json!(10)]);
        assert_eq!(result.unwrap(), json!("2024-01-11"));
    }

    #[test]
    fn test_format_date() {
        let result = format_date(&[json!("2024-01-15"), json!("%Y/%m/%d")]);
        assert_eq!(result.unwrap(), json!("2024/01/15"));
    }

    #[test]
    fn test_today() {
        let result = today(&[]);
        assert!(result.is_ok());
        // Should be in YYYY-MM-DD format
        assert!(result.unwrap().as_str().unwrap().contains("-"));
    }
}
