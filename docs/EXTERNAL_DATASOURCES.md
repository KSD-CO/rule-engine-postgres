# External Data Sources (Phase 4.3, v1.6.0)

**Status:** ✅ Complete
**Version:** 1.6.0
**Released:** December 12, 2025

## Overview

External Data Sources enable the rule engine to fetch data from REST APIs during rule execution, allowing rules to make decisions based on real-time external data. This feature includes connection pooling, caching strategies, authentication management, and comprehensive monitoring.

---

## Features

### ✅ Data Source Management
- Register external REST APIs with full configuration
- Support for multiple authentication methods (Basic, Bearer, API Key, OAuth2)
- Custom headers and request configuration
- Enable/disable data sources without deletion
- Data source categorization with tags

### ✅ Authentication Support
- **None**: No authentication
- **Basic**: Username/password authentication
- **Bearer**: Token-based authentication
- **API Key**: Custom header-based API keys
- **OAuth2**: OAuth 2.0 access tokens

### ✅ Caching Layer
- Automatic response caching with TTL
- Configurable cache duration per data source
- Cache hit/miss tracking
- Manual cache invalidation
- Automatic cleanup of expired entries

### ✅ Connection Pooling
- HTTP connection reuse for better performance
- Configurable pool size
- Automatic connection management

### ✅ Retry Logic
- Automatic retry on failures
- Configurable max retries
- Exponential backoff (future enhancement)
- Failure tracking and monitoring

### ✅ Monitoring & Analytics
- Real-time status tracking
- Success/failure rates
- Performance metrics (avg, min, max, percentiles)
- Cache hit rates
- Recent failures view
- Request history with full audit trail

---

## Architecture

### Data Flow

```
Rule Execution
    ↓
Check Cache (if enabled)
    ↓ (cache miss)
HTTP Client (with connection pooling)
    ↓
External API
    ↓
Parse Response (JSON)
    ↓
Store in Cache (if successful)
    ↓
Record Request Stats
    ↓
Return to Rule
```

### Connection Pooling

The HTTP client maintains a pool of reusable connections:
- **Max idle connections per host**: 10
- **Connection timeout**: Configurable per data source
- **Automatic cleanup**: Idle connections are cleaned up automatically

---

## Database Schema

### Tables

#### `rule_datasources`
Data source endpoint configurations
```sql
CREATE TABLE rule_datasources (
    datasource_id SERIAL PRIMARY KEY,
    datasource_name TEXT NOT NULL UNIQUE,
    description TEXT,
    base_url TEXT NOT NULL,
    auth_type TEXT DEFAULT 'none',
    default_headers JSONB DEFAULT '{}',
    timeout_ms INTEGER DEFAULT 5000,
    retry_enabled BOOLEAN DEFAULT true,
    max_retries INTEGER DEFAULT 3,
    cache_enabled BOOLEAN DEFAULT true,
    cache_ttl_seconds INTEGER DEFAULT 300,
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    tags TEXT[] DEFAULT '{}'
);
```

#### `rule_datasource_auth`
Authentication credentials for data sources
```sql
CREATE TABLE rule_datasource_auth (
    auth_id SERIAL PRIMARY KEY,
    datasource_id INTEGER REFERENCES rule_datasources(datasource_id),
    auth_key TEXT NOT NULL,
    auth_value TEXT NOT NULL,
    UNIQUE(datasource_id, auth_key)
);
```

#### `rule_datasource_cache`
Cache for API responses
```sql
CREATE TABLE rule_datasource_cache (
    cache_id SERIAL PRIMARY KEY,
    datasource_id INTEGER REFERENCES rule_datasources(datasource_id),
    cache_key TEXT NOT NULL,
    cache_value JSONB NOT NULL,
    response_status INTEGER,
    expires_at TIMESTAMPTZ NOT NULL,
    hit_count INTEGER DEFAULT 0,
    last_hit_at TIMESTAMPTZ,
    UNIQUE(datasource_id, cache_key)
);
```

#### `rule_datasource_requests`
History and monitoring of API requests
```sql
CREATE TABLE rule_datasource_requests (
    request_id SERIAL PRIMARY KEY,
    datasource_id INTEGER REFERENCES rule_datasources(datasource_id),
    endpoint TEXT NOT NULL,
    method TEXT DEFAULT 'GET',
    params JSONB DEFAULT '{}',
    status TEXT DEFAULT 'pending',
    cache_hit BOOLEAN DEFAULT false,
    rule_name TEXT,
    response_status INTEGER,
    response_body JSONB,
    error_message TEXT,
    execution_time_ms NUMERIC,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
```

#### `rule_datasource_rate_limits`
Track rate limiting per data source
```sql
CREATE TABLE rule_datasource_rate_limits (
    rate_limit_id SERIAL PRIMARY KEY,
    datasource_id INTEGER REFERENCES rule_datasources(datasource_id) UNIQUE,
    max_requests_per_minute INTEGER DEFAULT 60,
    max_requests_per_hour INTEGER DEFAULT 1000,
    current_minute_count INTEGER DEFAULT 0,
    current_hour_count INTEGER DEFAULT 0,
    minute_window_start TIMESTAMPTZ,
    hour_window_start TIMESTAMPTZ
);
```

---

## API Reference

### Data Source Registration

#### `rule_datasource_register()`
Registers a new external data source.

```sql
rule_datasource_register(
    p_name TEXT,
    p_base_url TEXT,
    p_auth_type TEXT DEFAULT 'none',
    p_default_headers JSONB DEFAULT '{}'::JSONB,
    p_description TEXT DEFAULT NULL,
    p_timeout_ms INTEGER DEFAULT 5000,
    p_cache_ttl_seconds INTEGER DEFAULT 300
) RETURNS INTEGER
```

**Parameters:**
- `p_name`: Unique name for the data source
- `p_base_url`: Base URL of the API (e.g., `https://api.github.com`)
- `p_auth_type`: Authentication type (`none`, `basic`, `bearer`, `api_key`, `oauth2`)
- `p_default_headers`: Default headers for all requests (JSON object)
- `p_description`: Optional description
- `p_timeout_ms`: Request timeout in milliseconds (max 60000)
- `p_cache_ttl_seconds`: Cache time-to-live in seconds

**Returns:** `datasource_id` (INTEGER)

**Example:**
```sql
-- Register GitHub API
SELECT rule_datasource_register(
    'github_api',
    'https://api.github.com',
    'bearer',
    '{
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28"
    }'::JSONB,
    'GitHub REST API v3',
    10000,
    600
);

-- Register public API (no auth)
SELECT rule_datasource_register(
    'jsonplaceholder',
    'https://jsonplaceholder.typicode.com',
    'none',
    '{"Content-Type": "application/json"}'::JSONB,
    'JSONPlaceholder test API'
);
```

---

#### `rule_datasource_update()`
Updates data source configuration.

```sql
rule_datasource_update(
    p_datasource_id INTEGER,
    p_base_url TEXT DEFAULT NULL,
    p_default_headers JSONB DEFAULT NULL,
    p_timeout_ms INTEGER DEFAULT NULL,
    p_cache_ttl_seconds INTEGER DEFAULT NULL,
    p_enabled BOOLEAN DEFAULT NULL
) RETURNS BOOLEAN
```

**Example:**
```sql
-- Update timeout
SELECT rule_datasource_update(1, NULL, NULL, 15000, NULL, NULL);

-- Disable data source
SELECT rule_datasource_update(1, NULL, NULL, NULL, NULL, false);
```

---

#### `rule_datasource_delete()`
Deletes a data source (cascades to auth, cache, requests).

```sql
rule_datasource_delete(p_datasource_id INTEGER) RETURNS BOOLEAN
```

**Example:**
```sql
SELECT rule_datasource_delete(1);
```

---

#### `rule_datasource_list()`
Lists all data sources with statistics.

```sql
rule_datasource_list(p_enabled_only BOOLEAN DEFAULT false)
RETURNS TABLE (
    datasource_id INTEGER,
    datasource_name TEXT,
    base_url TEXT,
    auth_type TEXT,
    enabled BOOLEAN,
    cache_enabled BOOLEAN,
    total_requests BIGINT,
    cache_hit_rate NUMERIC,
    avg_response_time_ms NUMERIC,
    created_at TIMESTAMPTZ
)
```

**Example:**
```sql
-- List all data sources
SELECT * FROM rule_datasource_list();

-- List only enabled data sources
SELECT * FROM rule_datasource_list(true);
```

---

#### `rule_datasource_get()`
Gets data source configuration by ID or name.

```sql
rule_datasource_get(p_identifier TEXT) RETURNS JSON
```

**Example:**
```sql
-- By name
SELECT rule_datasource_get('github_api');

-- By ID
SELECT rule_datasource_get('1');
```

---

### Authentication Management

#### `rule_datasource_auth_set()`
Sets authentication credentials for a data source.

```sql
rule_datasource_auth_set(
    p_datasource_id INTEGER,
    p_auth_key TEXT,
    p_auth_value TEXT
) RETURNS BOOLEAN
```

**Example:**
```sql
-- Basic auth
SELECT rule_datasource_auth_set(1, 'username', 'myuser');
SELECT rule_datasource_auth_set(1, 'password', 'mypass');

-- Bearer token
SELECT rule_datasource_auth_set(2, 'token', 'ghp_1234567890abcdef');

-- API key
SELECT rule_datasource_auth_set(3, 'header_name', 'X-API-Key');
SELECT rule_datasource_auth_set(3, 'api_key', 'my-secret-api-key');

-- OAuth2
SELECT rule_datasource_auth_set(4, 'access_token', 'ya29.a0...');
```

**⚠️ Security Warning:** In production, encrypt auth values before storing!

---

#### `rule_datasource_auth_get()`
Gets authentication credential (use carefully!).

```sql
rule_datasource_auth_get(
    p_datasource_id INTEGER,
    p_auth_key TEXT
) RETURNS TEXT
```

**Example:**
```sql
SELECT rule_datasource_auth_get(1, 'token');
```

**⚠️ Warning:** This function is `SECURITY DEFINER`. Restrict access!

---

#### `rule_datasource_auth_delete()`
Removes authentication credential.

```sql
rule_datasource_auth_delete(
    p_datasource_id INTEGER,
    p_auth_key TEXT
) RETURNS BOOLEAN
```

**Example:**
```sql
SELECT rule_datasource_auth_delete(1, 'old_token');
```

---

### Data Fetching

#### `rule_datasource_fetch()`
Fetches data from an external API.

```sql
rule_datasource_fetch(
    p_datasource_id INTEGER,
    p_endpoint TEXT,
    p_params JSONB DEFAULT '{}'::JSONB
) RETURNS JSON
```

**Parameters:**
- `p_datasource_id`: ID of the registered data source
- `p_endpoint`: Relative endpoint path (e.g., `/users/123`)
- `p_params`: Query parameters or request body (JSON object)

**Returns:** JSON object with response data

**Example:**
```sql
-- Fetch user data
SELECT rule_datasource_fetch(
    1,
    '/users/123',
    '{}'::JSONB
);

-- Fetch with query parameters
SELECT rule_datasource_fetch(
    1,
    '/users',
    '{"per_page": 10, "page": 1}'::JSONB
);

-- Response format:
-- {
--   "success": true,
--   "request_id": 42,
--   "cache_hit": false,
--   "status": 200,
--   "data": { ... },
--   "execution_time_ms": 123.45,
--   "datasource_name": "github_api"
-- }
```

---

### Cache Management

#### `rule_datasource_cache_get()`
Retrieves cached response if still valid.

```sql
rule_datasource_cache_get(
    p_datasource_id INTEGER,
    p_cache_key TEXT
) RETURNS JSONB
```

#### `rule_datasource_cache_set()`
Stores response in cache.

```sql
rule_datasource_cache_set(
    p_datasource_id INTEGER,
    p_cache_key TEXT,
    p_cache_value JSONB,
    p_response_status INTEGER,
    p_ttl_seconds INTEGER
) RETURNS BOOLEAN
```

#### `rule_datasource_cache_clear()`
Clears cache for a specific data source or all.

```sql
rule_datasource_cache_clear(
    p_datasource_id INTEGER DEFAULT NULL
) RETURNS BIGINT
```

**Example:**
```sql
-- Clear cache for specific data source
SELECT rule_datasource_cache_clear(1);

-- Clear all caches
SELECT rule_datasource_cache_clear();
```

#### `rule_datasource_cache_cleanup()`
Removes expired cache entries.

```sql
rule_datasource_cache_cleanup() RETURNS BIGINT
```

**Example:**
```sql
-- Cleanup expired entries
SELECT rule_datasource_cache_cleanup();

-- Schedule with pg_cron
SELECT cron.schedule(
    'cleanup-datasource-cache',
    '*/15 * * * *',  -- Every 15 minutes
    $$SELECT rule_datasource_cache_cleanup()$$
);
```

---

### Monitoring Views

#### `datasource_status_summary`
Summary of data source request statistics.

```sql
SELECT * FROM datasource_status_summary;
```

**Columns:**
- `datasource_id`, `datasource_name`, `base_url`, `enabled`, `cache_enabled`
- `total_requests`, `successful_requests`, `failed_requests`, `cached_requests`
- `avg_execution_time_ms`, `last_request_at`
- `success_rate_pct`, `cache_hit_rate_pct`

---

#### `datasource_recent_failures`
Recent failed requests for debugging.

```sql
SELECT * FROM datasource_recent_failures LIMIT 10;
```

**Columns:**
- `request_id`, `datasource_name`, `base_url`, `endpoint`, `method`
- `status`, `retry_count`, `error_message`, `response_status`
- `params`, `created_at`, `completed_at`

---

#### `datasource_performance_stats`
Performance statistics per data source.

```sql
SELECT * FROM datasource_performance_stats;
```

**Columns:**
- `datasource_id`, `datasource_name`, `total_requests`
- `avg_time_ms`, `min_time_ms`, `max_time_ms`
- `p50_time_ms`, `p95_time_ms`, `p99_time_ms`

---

#### `datasource_cache_stats`
Cache statistics per data source.

```sql
SELECT * FROM datasource_cache_stats;
```

**Columns:**
- `datasource_id`, `datasource_name`, `cache_enabled`
- `total_cache_entries`, `valid_cache_entries`, `expired_cache_entries`
- `avg_hit_count`, `total_hits`, `last_cache_hit_at`

---

### Maintenance

#### `rule_datasource_cleanup_old_requests()`
Removes old request records.

```sql
rule_datasource_cleanup_old_requests(
    p_older_than INTERVAL DEFAULT '30 days',
    p_keep_failed BOOLEAN DEFAULT true
) RETURNS BIGINT
```

**Example:**
```sql
-- Cleanup requests older than 7 days (keep failed ones)
SELECT rule_datasource_cleanup_old_requests('7 days', true);

-- Cleanup all requests older than 30 days
SELECT rule_datasource_cleanup_old_requests('30 days', false);
```

---

## Usage Examples

### Example 1: Fetch User Data from GitHub API

```sql
-- 1. Register GitHub API
SELECT rule_datasource_register(
    'github_api',
    'https://api.github.com',
    'bearer',
    '{
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28"
    }'::JSONB,
    'GitHub REST API',
    10000,
    600
) AS github_id \gset

-- 2. Set Bearer token
SELECT rule_datasource_auth_set(:github_id, 'token', 'ghp_YOUR_TOKEN_HERE');

-- 3. Fetch user data
SELECT rule_datasource_fetch(
    :github_id,
    '/users/torvalds',
    '{}'::JSONB
) AS user_data;

-- 4. Monitor performance
SELECT * FROM datasource_status_summary WHERE datasource_name = 'github_api';
```

---

### Example 2: Public API with Query Parameters

```sql
-- 1. Register JSONPlaceholder API
SELECT rule_datasource_register(
    'jsonplaceholder',
    'https://jsonplaceholder.typicode.com',
    'none',
    '{"Content-Type": "application/json"}'::JSONB
) AS jp_id \gset

-- 2. Fetch posts with query params
SELECT rule_datasource_fetch(
    :jp_id,
    '/posts',
    '{"userId": 1}'::JSONB
);

-- 3. Fetch specific post (cache enabled, TTL=300s)
SELECT rule_datasource_fetch(
    :jp_id,
    '/posts/1',
    '{}'::JSONB
);

-- Second call will hit cache
SELECT rule_datasource_fetch(
    :jp_id,
    '/posts/1',
    '{}'::JSONB
);
```

---

### Example 3: Integration with Rules

Create a rule that fetches external data:

```sql
-- 1. Register currency exchange API
SELECT rule_datasource_register(
    'exchange_rates',
    'https://api.exchangerate-api.com/v4/latest',
    'none',
    '{}'::JSONB,
    'Currency exchange rates'
);

-- 2. Create rule that uses external data
SELECT rule_save(
    'currency_converter',
    'rule CurrencyConverter "Convert amount using live exchange rate" {
        when
            Transaction.currency == "EUR" &&
            Transaction.amount > 0
        then
            // In practice, you would fetch exchange rate via
            // custom function that calls rule_datasource_fetch
            Transaction.usd_amount = Transaction.amount * 1.10;
    }',
    '1.0.0',
    'Currency conversion with live rates'
);

-- 3. In your application layer, you could:
--    a) Fetch exchange rates before rule execution
--    b) Pass them as facts
--    c) Or create a custom PL/pgSQL function that combines
--       rule_datasource_fetch with rule execution
```

---

### Example 4: API Key Authentication

```sql
-- 1. Register API with API key auth
SELECT rule_datasource_register(
    'weather_api',
    'https://api.openweathermap.org/data/2.5',
    'api_key',
    '{"Content-Type": "application/json"}'::JSONB,
    'OpenWeather API'
) AS weather_id \gset

-- 2. Set API key credentials
SELECT rule_datasource_auth_set(:weather_id, 'header_name', 'appid');
SELECT rule_datasource_auth_set(:weather_id, 'api_key', 'YOUR_API_KEY_HERE');

-- 3. Fetch weather data
SELECT rule_datasource_fetch(
    :weather_id,
    '/weather',
    '{"q": "London", "units": "metric"}'::JSONB
);
```

---

## Best Practices

### 1. Security

✅ **DO:**
- Encrypt authentication credentials before storing
- Use HTTPS URLs only
- Rotate API keys regularly
- Restrict access to `rule_datasource_auth_get()`
- Use environment variables for sensitive data
- Implement proper database roles and permissions

❌ **DON'T:**
- Store credentials in plain text
- Use HTTP for sensitive data
- Share credentials across environments
- Expose API keys in logs

### 2. Performance

✅ **DO:**
- Enable caching for frequently accessed data
- Set appropriate cache TTL based on data freshness requirements
- Use connection pooling (automatic)
- Monitor cache hit rates
- Set reasonable timeouts
- Clean up old request records regularly

❌ **DON'T:**
- Set cache TTL too high for rapidly changing data
- Set cache TTL too low (defeats purpose of caching)
- Keep unlimited request history
- Set timeouts too high

### 3. Reliability

✅ **DO:**
- Enable retry logic
- Monitor failure rates
- Set up alerting for high failure rates
- Handle API rate limits
- Test with mock APIs first

❌ **DON'T:**
- Retry indefinitely
- Ignore error messages
- Skip monitoring
- Exceed API rate limits

### 4. Monitoring

✅ **DO:**
- Check `datasource_status_summary` regularly
- Monitor `datasource_recent_failures`
- Track performance with `datasource_performance_stats`
- Review cache efficiency with `datasource_cache_stats`
- Set up alerts for anomalies

❌ **DON'T:**
- Ignore failed requests
- Skip performance reviews
- Forget to monitor cache hit rates

---

## Troubleshooting

### Problem: Data source not fetching data

**Solution:**
1. Check if data source is enabled: `SELECT enabled FROM rule_datasources WHERE datasource_id = ?;`
2. Verify base URL is correct
3. Check authentication credentials are set
4. Review recent failures: `SELECT * FROM datasource_recent_failures WHERE datasource_id = ?;`

### Problem: Low cache hit rate

**Solution:**
1. Check cache is enabled for the data source
2. Verify cache TTL is appropriate
3. Review cache stats: `SELECT * FROM datasource_cache_stats;`
4. Check if data is actually being cached
5. Clear and rebuild cache if needed

### Problem: High response times

**Solution:**
1. Check network connectivity to API
2. Review performance stats: `SELECT * FROM datasource_performance_stats;`
3. Consider increasing timeout if API is slow
4. Enable or increase cache TTL
5. Check API rate limits

### Problem: Authentication failures

**Solution:**
1. Verify auth type matches API requirements
2. Check credentials are correct: `SELECT * FROM rule_datasource_auth WHERE datasource_id = ?;`
3. Ensure token/key hasn't expired
4. Review API documentation for auth changes
5. Check default headers include required auth headers

---

## Migration

### From v1.5.0 to v1.6.0

```sql
-- Run migration
\i migrations/006_external_datasources.sql

-- Verify installation
\dt rule_datasource*
\df rule_datasource*
\dv datasource*
```

### Verify Tables

```sql
SELECT tablename FROM pg_tables
WHERE tablename LIKE 'rule_datasource%'
ORDER BY tablename;
```

Expected tables:
- `rule_datasources`
- `rule_datasource_auth`
- `rule_datasource_cache`
- `rule_datasource_rate_limits`
- `rule_datasource_requests`

---

## Performance Considerations

### Connection Pooling

- HTTP client maintains a pool of up to 10 idle connections per host
- Connections are automatically reused for better performance
- No manual connection management required

### Caching Strategy

- Cache key is generated from endpoint + params
- Default TTL: 300 seconds (5 minutes)
- Cache automatically expires after TTL
- Hit count tracking for cache effectiveness analysis

### Request Lifecycle

1. **Check cache** (~0.1ms if hit)
2. **HTTP request** (variable, depends on API)
3. **Parse JSON** (~1-5ms)
4. **Store cache** (~1ms)
5. **Record stats** (~1ms)

**Total overhead:** ~2-7ms + API response time

---

## Limitations

1. **Synchronous execution**: Requests block until complete
2. **No streaming**: Responses must fit in memory
3. **JSON only**: Only JSON responses are supported
4. **GET requests default**: Only GET implemented in initial version
5. **No request batching**: Each request is independent

Future enhancements will address these limitations.

---

## References

- [ROADMAP](ROADMAP.md) - Feature roadmap
- [WEBHOOKS](WEBHOOKS.md) - Webhook support documentation
- [API Reference](api-reference.md) - Complete API documentation
- [PostgreSQL HTTP Extension](https://github.com/pramsey/pgsql-http) - Alternative for simple HTTP calls

---

**Version:** 1.6.0
**Status:** ✅ Production Ready
**Last Updated:** December 12, 2025
