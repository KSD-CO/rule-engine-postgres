use pgrx::datum::TimestampWithTimeZone;
use pgrx::prelude::*;

/// Record a rule execution for statistics tracking
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
    let result: Option<i64> = Spi::connect(|client| {
        client
            .select(
                "SELECT rule_record_execution($1, $2, $3, $4, $5, $6, $7)",
                None,
                &[
                    rule_name.into(),
                    rule_version
                        .map(|v| v.into())
                        .unwrap_or_else(|| Option::<String>::None.into()),
                    execution_time_ms.into(),
                    success.into(),
                    error_message
                        .map(|e| e.into())
                        .unwrap_or_else(|| Option::<String>::None.into()),
                    facts_modified.into(),
                    rules_fired.into(),
                ],
            )?
            .first()
            .get_one::<i64>()
    })?;

    Ok(result.unwrap_or(0))
}

/// Get comprehensive statistics for a rule within a time range
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

    let result: Option<pgrx::JsonB> = Spi::connect(|client| {
        client
            .select(
                "SELECT rule_stats($1, $2, $3)",
                None,
                &[rule_name.into(), start_str.into(), end_str.into()],
            )?
            .first()
            .get_one::<pgrx::JsonB>()
    })?;

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
#[pg_extern]
fn rule_clear_stats(
    rule_name: &str,
    before_date: Option<TimestampWithTimeZone>,
) -> Result<i64, Box<dyn std::error::Error>> {
    let date_str = match before_date {
        Some(ts) => format!("'{}' ::timestamptz", ts),
        None => "NULL".to_string(),
    };

    let result: Option<i64> = Spi::connect(|client| {
        client
            .select(
                "SELECT rule_clear_stats($1, $2)",
                None,
                &[rule_name.into(), date_str.into()],
            )?
            .first()
            .get_one::<i64>()
    })?;

    Ok(result.unwrap_or(0))
}
