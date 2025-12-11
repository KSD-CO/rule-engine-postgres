use super::models::{AuthType, DataSource, DataSourceAuth, DataSourceResponse};
use reqwest::blocking::{Client, RequestBuilder};
use reqwest::header::{HeaderMap, HeaderName, HeaderValue};
use serde_json::Value as JsonValue;
use std::collections::HashMap;
use std::str::FromStr;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Copy)]
pub enum HttpMethod {
    Get,
    Post,
    Put,
    Patch,
    Delete,
}

impl FromStr for HttpMethod {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_uppercase().as_str() {
            "GET" => Ok(HttpMethod::Get),
            "POST" => Ok(HttpMethod::Post),
            "PUT" => Ok(HttpMethod::Put),
            "PATCH" => Ok(HttpMethod::Patch),
            "DELETE" => Ok(HttpMethod::Delete),
            _ => Err(format!("Invalid HTTP method: {}", s)),
        }
    }
}

pub struct DataSourceClient {
    client: Client,
}

impl DataSourceClient {
    pub fn new() -> Result<Self, String> {
        let client = Client::builder()
            .pool_max_idle_per_host(10) // Connection pooling
            .build()
            .map_err(|e| format!("Failed to create HTTP client: {}", e))?;

        Ok(Self { client })
    }

    /// Fetch data from external API
    pub fn fetch(
        &self,
        datasource: &DataSource,
        auth: &DataSourceAuth,
        endpoint: &str,
        method: HttpMethod,
        params: &JsonValue,
    ) -> Result<DataSourceResponse, String> {
        let start_time = Instant::now();

        // Build full URL
        let url = format!("{}{}", datasource.base_url.trim_end_matches('/'), endpoint);

        // Build request
        let mut request = self.build_request(method, &url)?;

        // Add default headers
        request = self.add_headers(request, &datasource.default_headers)?;

        // Add authentication
        request = self.add_auth(request, &datasource.auth_type, auth)?;

        // Add timeout
        request = request.timeout(Duration::from_millis(datasource.timeout_ms as u64));

        // Add body/params based on method
        request = match method {
            HttpMethod::Get => {
                // For GET, add params as query string
                if let Some(obj) = params.as_object() {
                    for (key, value) in obj {
                        let value_str = match value {
                            JsonValue::String(s) => s.clone(),
                            JsonValue::Number(n) => n.to_string(),
                            JsonValue::Bool(b) => b.to_string(),
                            _ => value.to_string(),
                        };
                        request = request.query(&[(key, value_str)]);
                    }
                }
                request
            }
            HttpMethod::Post | HttpMethod::Put | HttpMethod::Patch => {
                // For POST/PUT/PATCH, send params as JSON body
                request.json(params)
            }
            HttpMethod::Delete => request,
        };

        // Execute request with retry logic
        let response_result = self.execute_with_retry(
            request,
            datasource.retry_enabled,
            datasource.max_retries as u32,
        );

        let execution_time_ms = start_time.elapsed().as_millis() as f64;

        match response_result {
            Ok(response) => {
                let status_code = response.status().as_u16() as i32;
                let is_success = response.status().is_success();

                // Try to parse response as JSON
                let body_result = response.json::<JsonValue>();

                match body_result {
                    Ok(body) => Ok(DataSourceResponse {
                        request_id: 0, // Will be set by database
                        status: if is_success {
                            "success".to_string()
                        } else {
                            "failed".to_string()
                        },
                        cache_hit: false,
                        response_status: Some(status_code),
                        response_body: Some(body),
                        error_message: None,
                        execution_time_ms: Some(execution_time_ms),
                    }),
                    Err(_) => {
                        // If JSON parsing fails, return error
                        Ok(DataSourceResponse {
                            request_id: 0,
                            status: "failed".to_string(),
                            cache_hit: false,
                            response_status: Some(status_code),
                            response_body: None,
                            error_message: Some("Failed to parse response as JSON".to_string()),
                            execution_time_ms: Some(execution_time_ms),
                        })
                    }
                }
            }
            Err(e) => Ok(DataSourceResponse {
                request_id: 0,
                status: "failed".to_string(),
                cache_hit: false,
                response_status: None,
                response_body: None,
                error_message: Some(e),
                execution_time_ms: Some(execution_time_ms),
            }),
        }
    }

    fn build_request(&self, method: HttpMethod, url: &str) -> Result<RequestBuilder, String> {
        let request = match method {
            HttpMethod::Get => self.client.get(url),
            HttpMethod::Post => self.client.post(url),
            HttpMethod::Put => self.client.put(url),
            HttpMethod::Patch => self.client.patch(url),
            HttpMethod::Delete => self.client.delete(url),
        };

        Ok(request)
    }

    fn add_headers(
        &self,
        mut request: RequestBuilder,
        headers: &HashMap<String, String>,
    ) -> Result<RequestBuilder, String> {
        for (key, value) in headers {
            let header_name = HeaderName::from_str(key)
                .map_err(|e| format!("Invalid header name '{}': {}", key, e))?;
            let header_value = HeaderValue::from_str(value)
                .map_err(|e| format!("Invalid header value for '{}': {}", key, e))?;

            request = request.header(header_name, header_value);
        }

        Ok(request)
    }

    fn add_auth(
        &self,
        mut request: RequestBuilder,
        auth_type: &AuthType,
        auth: &DataSourceAuth,
    ) -> Result<RequestBuilder, String> {
        match auth_type {
            AuthType::None => Ok(request),
            AuthType::Basic => {
                let username = auth
                    .get("username")
                    .ok_or("Basic auth requires 'username'")?;
                let password = auth
                    .get("password")
                    .ok_or("Basic auth requires 'password'")?;

                Ok(request.basic_auth(username, Some(password)))
            }
            AuthType::Bearer => {
                let token = auth.get("token").ok_or("Bearer auth requires 'token'")?;

                Ok(request.bearer_auth(token))
            }
            AuthType::ApiKey => {
                let header_name = auth
                    .get("header_name")
                    .ok_or("API key auth requires 'header_name'")?;
                let api_key = auth.get("api_key").ok_or("API key auth requires 'api_key'")?;

                let header_name = HeaderName::from_str(header_name)
                    .map_err(|e| format!("Invalid header name: {}", e))?;
                let header_value = HeaderValue::from_str(api_key)
                    .map_err(|e| format!("Invalid API key: {}", e))?;

                Ok(request.header(header_name, header_value))
            }
            AuthType::OAuth2 => {
                // OAuth2 is similar to Bearer for now
                let token = auth
                    .get("access_token")
                    .ok_or("OAuth2 requires 'access_token'")?;

                Ok(request.bearer_auth(token))
            }
        }
    }

    fn execute_with_retry(
        &self,
        request: RequestBuilder,
        retry_enabled: bool,
        max_retries: u32,
    ) -> Result<reqwest::blocking::Response, String> {
        let mut attempts = 0;

        loop {
            // Clone request for retry (note: this requires rebuilding the request each time)
            let response = request
                .try_clone()
                .ok_or("Failed to clone request")?
                .send();

            match response {
                Ok(resp) => {
                    if resp.status().is_success() || !retry_enabled || attempts >= max_retries {
                        return Ok(resp);
                    }

                    // If we get here, it's a non-success status and we should retry
                    attempts += 1;
                    if attempts < max_retries {
                        // Simple retry delay (could be exponential backoff)
                        std::thread::sleep(Duration::from_millis(1000 * attempts as u64));
                        continue;
                    } else {
                        return Ok(resp);
                    }
                }
                Err(e) => {
                    if !retry_enabled || attempts >= max_retries {
                        return Err(format!("HTTP request failed: {}", e));
                    }

                    attempts += 1;
                    if attempts < max_retries {
                        std::thread::sleep(Duration::from_millis(1000 * attempts as u64));
                        continue;
                    } else {
                        return Err(format!("HTTP request failed after {} retries: {}", attempts, e));
                    }
                }
            }
        }
    }
}

impl Default for DataSourceClient {
    fn default() -> Self {
        Self::new().expect("Failed to create default DataSourceClient")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_http_method_from_str() {
        assert!(matches!(HttpMethod::from_str("GET"), Ok(HttpMethod::Get)));
        assert!(matches!(HttpMethod::from_str("post"), Ok(HttpMethod::Post)));
        assert!(matches!(HttpMethod::from_str("PUT"), Ok(HttpMethod::Put)));
        assert!(HttpMethod::from_str("INVALID").is_err());
    }

    #[test]
    fn test_client_creation() {
        let client = DataSourceClient::new();
        assert!(client.is_ok());
    }
}
