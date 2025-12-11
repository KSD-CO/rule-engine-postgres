use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataSource {
    pub datasource_id: i32,
    pub datasource_name: String,
    pub base_url: String,
    pub auth_type: AuthType,
    pub default_headers: HashMap<String, String>,
    pub timeout_ms: i32,
    pub retry_enabled: bool,
    pub max_retries: i32,
    pub cache_enabled: bool,
    pub cache_ttl_seconds: i32,
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum AuthType {
    None,
    Basic,
    Bearer,
    ApiKey,
    OAuth2,
}

impl std::str::FromStr for AuthType {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "none" => Ok(AuthType::None),
            "basic" => Ok(AuthType::Basic),
            "bearer" => Ok(AuthType::Bearer),
            "api_key" => Ok(AuthType::ApiKey),
            "oauth2" => Ok(AuthType::OAuth2),
            _ => Err(format!("Invalid auth type: {}", s)),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataSourceAuth {
    pub credentials: HashMap<String, String>,
}

impl DataSourceAuth {
    pub fn new() -> Self {
        Self {
            credentials: HashMap::new(),
        }
    }

    pub fn set(&mut self, key: String, value: String) {
        self.credentials.insert(key, value);
    }

    pub fn get(&self, key: &str) -> Option<&String> {
        self.credentials.get(key)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataSourceRequest {
    pub datasource_id: i32,
    pub endpoint: String,
    pub method: String,
    pub params: JsonValue,
    pub rule_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataSourceResponse {
    pub request_id: i32,
    pub status: String,
    pub cache_hit: bool,
    pub response_status: Option<i32>,
    pub response_body: Option<JsonValue>,
    pub error_message: Option<String>,
    pub execution_time_ms: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheEntry {
    pub cache_key: String,
    pub cache_value: JsonValue,
    pub response_status: i32,
    pub expires_at: DateTime<Utc>,
}
