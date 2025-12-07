use pgrx::datum::TimestampWithTimeZone;
use pgrx::prelude::*;

/// Record a rule execution for statistics tracking
///
/// # Arguments
/// * `rule_name` - Name of the rule that was executed
/// * `rule_version` - Version of the rule (optional)
/// * `execution_time_ms` - Execution time in milliseconds
/// * `success` - Whether the execution was successful
/// * `error_message` - Error message if execution failed (optional)
/// * `facts_modified` - Number of facts modified (optional)
/// * `rules_fired` - Number of rules that fired (optional)
///
/// # Returns
/// The ID of the newly created statistics record
///
/// # Example
/// ```sql
/// SELECT rule_record_execution('loan_approval', '1.0.0', 45.5, true, NULL, 3, 5);
/// ```
#[pg_extern]
fn rule_record_execution(
    rule_name: &str,
    rule_version: Option<&str>,
    execution_time_ms: f64,
    success: bool,
    error_message: Option<&str>,
    facts_modified: default!(i32, 0),
    rules_fired: default!(i32, 0),
) -> Result<i64, Box<dyn std::error::Error>> {
    let query = format!(
        "SELECT rule_record_execution('{}', {}, {}, {}, {}, {}, {})",
        rule_name.replace("'", "''"),
        rule_version
            .map(|v| format!("'{}'", v.replace("'", "''")))
            .unwrap_or_else(|| "NULL".to_string()),
        execution_time_ms,
        success,
        error_message
            .map(|e| format!("'{}'", e.replace("'", "''")))
            .unwrap_or_else(|| "NULL".to_string()),
        facts_modified,
        rules_fired
    );

    let result = Spi::get_one::<i64>(&query)?;
    result.ok_or_else(|| "Failed to record execution".into())
}

/// Get comprehensive statistics for a rule within a time range
///
/// # Arguments
/// * `rule_name` - Name of the rule
/// * `start_time` - Start of time range (optional, defaults to 7 days ago)
/// * `end_time` - End of time range (optional, defaults to now)
///
/// # Returns
/// JSON object containing execution statistics
///
/// # Example
/// ```sql
/// SELECT rule_stats('loan_approval', NOW() - INTERVAL '30 days', NOW());
/// ```
#[pg_extern]
fn rule_stats(
    rule_name: &str,
    start_time: Option<TimestampWithTimeZone>,
    end_time: Option<TimestampWithTimeZone>,
) -> Result<pgrx::JsonB, Box<dyn std::error::Error>> {
    let start_str = match start_time {
        Some(ts) => format!("'{}' ::timestamptz", ts),
        None => "NOW() - INTERVAL '7 days'".to_string(),
    };

    let end_str = match end_time {
        Some(ts) => format!("'{}' ::timestamptz", ts),
        None => "NOW()".to_string(),
    };

    let query = format!(
        "SELECT rule_stats('{}', {}, {})",
        rule_name.replace("'", "''"),
        start_str,
        end_str
    );

    let result = Spi::get_one::<pgrx::JsonB>(&query)?;
    match result {
        Some(stats) => Ok(stats),
        None => {
            let empty_json = serde_json::json!({
                "rule_name": rule_name,
                "total_executions": 0,
                "message": "No execution data found"
            });
            Ok(pgrx::JsonB(empty_json))
        }
    }
}

/// Clear execution statistics for a specific rule
///
/// # Arguments
/// * `rule_name` - Name of the rule
/// * `before_date` - Optional cutoff date (clears stats before this date, or all if NULL)
///
/// # Returns
/// Number of statistics records deleted
///
/// # Example
/// ```sql
/// -- Clear all stats for a rule
/// SELECT rule_clear_stats('old_rule', NULL);
///
/// -- Clear stats older than 90 days
/// SELECT rule_clear_stats('loan_approval', NOW() - INTERVAL '90 days');
/// ```
#[pg_extern]
fn rule_clear_stats(
    rule_name: &str,
    before_date: Option<TimestampWithTimeZone>,
) -> Result<i64, Box<dyn std::error::Error>> {
    let date_str = match before_date {
        Some(ts) => format!("'{}' ::timestamptz", ts),
        None => "NULL".to_string(),
    };

    let query = format!(
        "SELECT rule_clear_stats('{}', {})",
        rule_name.replace("'", "''"),
        date_str
    );

    let result = Spi::get_one::<i64>(&query)?;
    Ok(result.unwrap_or(0))
}
