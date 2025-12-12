use crate::datasources::client::{DataSourceClient, HttpMethod};
use crate::datasources::models::{DataSource, DataSourceAuth};
use pgrx::prelude::*;
use pgrx::JsonB;
use serde_json::Value as JsonValue;
use std::collections::HashMap;
use std::str::FromStr;

/// Fetch data from an external API data source
#[pg_extern]
fn rule_datasource_fetch(
    datasource_id: i32,
    endpoint: String,
    params: JsonB,
) -> Result<JsonB, String> {
    // Get datasource configuration from database using parameterized query
    let datasource_result = Spi::connect(|client| -> Result<DataSource, spi::Error> {
        let result = client.select(
            "SELECT datasource_id, datasource_name, base_url, auth_type,
                    default_headers, timeout_ms, retry_enabled, max_retries,
                    cache_enabled, cache_ttl_seconds, enabled
             FROM rule_datasources
             WHERE datasource_id = $1",
            None,
            &[datasource_id.into()],
        )?;

        if result.is_empty() {
            return Err(spi::Error::InvalidPosition);
        }

        let row = result.first();
        let datasource_name = row.get::<String>(2)?.unwrap_or_default();
        let base_url = row.get::<String>(3)?.unwrap_or_default();
        let auth_type_str = row.get::<String>(4)?.unwrap_or("none".to_string());
        let default_headers_json = row.get::<JsonB>(5)?.unwrap_or(JsonB(serde_json::json!({})));
        let timeout_ms = row.get::<i32>(6)?.unwrap_or(5000);
        let retry_enabled = row.get::<bool>(7)?.unwrap_or(true);
        let max_retries = row.get::<i32>(8)?.unwrap_or(3);
        let cache_enabled = row.get::<bool>(9)?.unwrap_or(true);
        let cache_ttl_seconds = row.get::<i32>(10)?.unwrap_or(300);
        let enabled = row.get::<bool>(11)?.unwrap_or(true);

        if !enabled {
            return Err(spi::Error::InvalidPosition);
        }

        // Parse default headers
        let mut default_headers = HashMap::new();
        if let Some(obj) = default_headers_json.0.as_object() {
            for (key, value) in obj {
                if let Some(val_str) = value.as_str() {
                    default_headers.insert(key.clone(), val_str.to_string());
                }
            }
        }

        let auth_type = crate::datasources::models::AuthType::from_str(&auth_type_str)
            .map_err(|_| spi::Error::InvalidPosition)?;

        Ok(DataSource {
            datasource_id,
            datasource_name,
            base_url,
            auth_type,
            default_headers,
            timeout_ms,
            retry_enabled,
            max_retries,
            cache_enabled,
            cache_ttl_seconds,
            enabled,
        })
    });

    let datasource = datasource_result.map_err(|e| format!("Failed to load datasource: {}", e))?;

    // Generate cache key
    let cache_key = generate_cache_key(&endpoint, &params.0);

    // Check cache if enabled
    if datasource.cache_enabled {
        let cache_result = check_cache(datasource_id, &cache_key);
        if let Ok(Some(cached_value)) = cache_result {
            let _ = record_request(datasource_id, &endpoint, "GET", &params.0, true, None);

            return Ok(JsonB(serde_json::json!({
                "success": true,
                "cache_hit": true,
                "data": cached_value,
                "datasource_name": datasource.datasource_name
            })));
        }
    }

    let auth = load_auth_credentials(datasource_id)?;
    let client =
        DataSourceClient::new().map_err(|e| format!("Failed to create HTTP client: {}", e))?;

    let method = HttpMethod::Get;
    let response = client.fetch(&datasource, &auth, &endpoint, method, &params.0)?;

    if datasource.cache_enabled && response.status == "success" {
        if let Some(ref body) = response.response_body {
            let _ = store_cache(
                datasource_id,
                &cache_key,
                body,
                response.response_status.unwrap_or(200),
                datasource.cache_ttl_seconds,
            );
        }
    }

    let request_id = record_request(
        datasource_id,
        &endpoint,
        "GET",
        &params.0,
        false,
        response.error_message.as_deref(),
    )?;

    let result = serde_json::json!({
        "success": response.status == "success",
        "request_id": request_id,
        "cache_hit": false,
        "status": response.response_status,
        "data": response.response_body,
        "error": response.error_message,
        "execution_time_ms": response.execution_time_ms,
        "datasource_name": datasource.datasource_name
    });

    Ok(JsonB(result))
}

#[pg_extern]
fn rule_datasource_fetch_with_method(
    datasource_id: i32,
    endpoint: String,
    _method: String,
    params: JsonB,
) -> Result<JsonB, String> {
    rule_datasource_fetch(datasource_id, endpoint, params)
}

fn generate_cache_key(endpoint: &str, params: &JsonValue) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    let mut hasher = DefaultHasher::new();
    endpoint.hash(&mut hasher);
    params.to_string().hash(&mut hasher);
    format!("{:x}", hasher.finish())
}

fn check_cache(datasource_id: i32, cache_key: &str) -> Result<Option<JsonValue>, String> {
    Spi::connect(|client| -> Result<Option<JsonValue>, spi::Error> {
        let result = client.select(
            "SELECT cache_value FROM rule_datasource_cache
             WHERE datasource_id = $1 AND cache_key = $2 AND expires_at > CURRENT_TIMESTAMP",
            None,
            &[datasource_id.into(), cache_key.to_string().into()],
        )?;

        if result.is_empty() {
            return Ok(None);
        }

        let row = result.first();
        let cache_value = row.get::<JsonB>(1)?;

        let _ = client.select(
            "UPDATE rule_datasource_cache
             SET hit_count = hit_count + 1, last_hit_at = CURRENT_TIMESTAMP
             WHERE datasource_id = $1 AND cache_key = $2",
            None,
            &[datasource_id.into(), cache_key.to_string().into()],
        )?;

        Ok(cache_value.map(|v| v.0))
    })
    .map_err(|e: spi::Error| format!("Cache check failed: {}", e))
}

fn store_cache(
    datasource_id: i32,
    cache_key: &str,
    cache_value: &JsonValue,
    response_status: i32,
    ttl_seconds: i32,
) -> Result<(), String> {
    let cache_value_json = JsonB(cache_value.clone());

    Spi::connect(|client| -> Result<(), spi::Error> {
        client.select(
            "INSERT INTO rule_datasource_cache
             (datasource_id, cache_key, cache_value, response_status, expires_at)
             VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP + ($5 || ' seconds')::INTERVAL)
             ON CONFLICT (datasource_id, cache_key) DO UPDATE
             SET cache_value = EXCLUDED.cache_value,
                 response_status = EXCLUDED.response_status,
                 created_at = CURRENT_TIMESTAMP,
                 expires_at = CURRENT_TIMESTAMP + ($5 || ' seconds')::INTERVAL,
                 hit_count = 0,
                 last_hit_at = NULL",
            None,
            &[
                datasource_id.into(),
                cache_key.to_string().into(),
                cache_value_json.into(),
                response_status.into(),
                ttl_seconds.into(),
            ],
        )?;
        Ok(())
    })
    .map_err(|e: spi::Error| format!("Failed to store cache: {}", e))
}

fn load_auth_credentials(datasource_id: i32) -> Result<DataSourceAuth, String> {
    Spi::connect(|client| -> Result<DataSourceAuth, spi::Error> {
        let result = client.select(
            "SELECT auth_key, auth_value FROM rule_datasource_auth WHERE datasource_id = $1",
            None,
            &[datasource_id.into()],
        )?;

        let mut auth = DataSourceAuth::new();
        for row in result {
            if let (Some(key), Some(value)) = (row.get::<String>(1)?, row.get::<String>(2)?) {
                auth.set(key, value);
            }
        }
        Ok(auth)
    })
    .map_err(|e: spi::Error| format!("Failed to load auth credentials: {}", e))
}

fn record_request(
    datasource_id: i32,
    endpoint: &str,
    method: &str,
    params: &JsonValue,
    cache_hit: bool,
    error_message: Option<&str>,
) -> Result<i32, String> {
    let status = if error_message.is_some() {
        "failed"
    } else if cache_hit {
        "cached"
    } else {
        "success"
    };

    let params_json = JsonB(params.clone());

    Spi::connect(|client| -> Result<i32, spi::Error> {
        // Simplified version - just required fields for now
        let result = client.select(
            "INSERT INTO rule_datasource_requests
             (datasource_id, endpoint, method, params, status, cache_hit, completed_at)
             VALUES ($1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP)
             RETURNING request_id",
            None,
            &[
                datasource_id.into(),
                endpoint.to_string().into(),
                method.to_string().into(),
                params_json.into(),
                status.to_string().into(),
                cache_hit.into(),
            ],
        )?;

        let request_id: i32 = result
            .first()
            .get_one::<i32>()?
            .ok_or(spi::Error::InvalidPosition)?;
        Ok(request_id)
    })
    .map_err(|e: spi::Error| format!("Failed to record request: {}", e))
}
