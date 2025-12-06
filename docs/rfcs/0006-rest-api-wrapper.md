# RFC-0006: REST API Wrapper

- **Status:** Draft
- **Author:** Rule Engine Team
- **Created:** 2025-12-06
- **Updated:** 2025-12-06
- **Phase:** 4.3 (Integration & Interoperability)
- **Priority:** P1 - High

---

## Summary

Expose PostgreSQL rule engine functionality via RESTful HTTP API, enabling language-agnostic integration from any platform (web apps, mobile apps, microservices) without direct database connections.

---

## Motivation

Current limitations:
- Direct PostgreSQL connection required for all operations
- Connection pooling complexity for web apps
- Security concerns exposing database credentials to frontend
- No standard REST interface for external systems

### Use Cases

1. **Web Applications:** Execute rules from React/Vue/Angular frontend
2. **Mobile Apps:** iOS/Android apps call rules via HTTP
3. **Microservices:** Service-to-service rule execution
4. **Third-party Integration:** External systems use rules without PostgreSQL drivers
5. **API Gateway:** Centralized rule execution endpoint

---

## Detailed Design

### Architecture Options

#### Option 1: PostgREST (Recommended for MVP)
- Automatic REST API from PostgreSQL schema
- Zero custom code required
- Built-in authentication (JWT)
- Row-level security support

#### Option 2: Custom Rust API Server
- Full control over API design
- Better performance optimization
- Custom authentication logic
- More deployment complexity

#### Option 3: pg_net + Database Functions
- API endpoints defined in SQL
- No separate service required
- Limited HTTP server features

**Decision:** Start with PostgREST (Option 1), migrate to custom Rust later if needed.

---

## PostgREST Implementation

### Database Schema

```sql
-- API schema (separate from internal schema)
CREATE SCHEMA IF NOT EXISTS api;

-- API views for rules
CREATE VIEW api.rules AS
SELECT 
    rule_name,
    rule_content,
    rule_version,
    is_default,
    created_at,
    created_by
FROM rule_definitions rd
JOIN rule_versions rv ON rd.id = rv.rule_definition_id
WHERE is_active = true;

-- API function for rule execution
CREATE OR REPLACE FUNCTION api.execute_rule(
    rule_name TEXT,
    facts JSONB
) RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    -- Validate input
    IF rule_name IS NULL OR facts IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'rule_name and facts are required'
        );
    END IF;
    
    -- Execute rule
    BEGIN
        result := rule_execute_by_name(rule_name, facts);
        
        RETURN jsonb_build_object(
            'success', true,
            'result', result,
            'timestamp', NOW()
        );
        
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', SQLERRM,
            'error_code', SQLSTATE
        );
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- API function for backward chaining
CREATE OR REPLACE FUNCTION api.query_rule(
    rule_name TEXT,
    query JSONB
) RETURNS JSONB AS $$
DECLARE
    result JSONB;
BEGIN
    BEGIN
        result := rule_backward_chain_by_name(rule_name, query);
        
        RETURN jsonb_build_object(
            'success', true,
            'result', result,
            'timestamp', NOW()
        );
        
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', SQLERRM
        );
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- API function for rule validation
CREATE OR REPLACE FUNCTION api.validate_rule(
    rule_content TEXT
) RETURNS JSONB AS $$
DECLARE
    validation_result JSONB;
BEGIN
    BEGIN
        -- Try to parse rule
        PERFORM rule_parse(rule_content);
        
        RETURN jsonb_build_object(
            'valid', true,
            'message', 'Rule syntax is valid'
        );
        
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'valid', false,
            'error', SQLERRM
        );
    END;
END;
$$ LANGUAGE plpgsql;

-- API function for rule creation
CREATE OR REPLACE FUNCTION api.create_rule(
    rule_name TEXT,
    rule_content TEXT,
    rule_version TEXT DEFAULT '1.0.0',
    tags TEXT[] DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
    new_rule_id INTEGER;
BEGIN
    -- Validate rule syntax first
    IF NOT (api.validate_rule(rule_content)->>'valid')::BOOLEAN THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Invalid rule syntax'
        );
    END IF;
    
    -- Save rule
    new_rule_id := rule_save(rule_name, rule_content, rule_version);
    
    -- Add tags if provided
    IF tags IS NOT NULL THEN
        FOREACH tag IN ARRAY tags LOOP
            PERFORM rule_tag_add(rule_name, tag);
        END LOOP;
    END IF;
    
    RETURN jsonb_build_object(
        'success', true,
        'rule_id', new_rule_id,
        'rule_name', rule_name,
        'version', rule_version
    );
    
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Health check endpoint
CREATE OR REPLACE FUNCTION api.health() RETURNS JSONB AS $$
BEGIN
    RETURN jsonb_build_object(
        'status', 'healthy',
        'timestamp', NOW(),
        'version', '1.0.0',
        'database', current_database()
    );
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
GRANT USAGE ON SCHEMA api TO web_anon, web_user;
GRANT SELECT ON api.rules TO web_anon, web_user;
GRANT EXECUTE ON FUNCTION api.execute_rule TO web_anon, web_user;
GRANT EXECUTE ON FUNCTION api.query_rule TO web_anon, web_user;
GRANT EXECUTE ON FUNCTION api.validate_rule TO web_anon, web_user;
GRANT EXECUTE ON FUNCTION api.create_rule TO web_user;
GRANT EXECUTE ON FUNCTION api.health TO web_anon, web_user;
```

### PostgREST Configuration

```conf
# postgrest.conf
db-uri = "postgres://authenticator:password@localhost:5432/rules_db"
db-schemas = "api"
db-anon-role = "web_anon"
db-pool = 10
db-pool-timeout = 10

server-host = "0.0.0.0"
server-port = 3000

jwt-secret = "your-secret-key-min-32-chars-long"
jwt-aud = "your-audience"

# OpenAPI
openapi-mode = "follow-privileges"
openapi-server-proxy-uri = "http://localhost:3000"
```

### Authentication Setup

```sql
-- Create roles
CREATE ROLE web_anon NOLOGIN;
CREATE ROLE web_user NOLOGIN;
CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD 'password';

GRANT web_anon TO authenticator;
GRANT web_user TO authenticator;

-- JWT claims function
CREATE OR REPLACE FUNCTION auth.check_token() RETURNS void AS $$
BEGIN
    IF current_setting('request.jwt.claims', true)::jsonb->>'role' = 'web_user' THEN
        SET LOCAL ROLE web_user;
    ELSE
        SET LOCAL ROLE web_anon;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Row-level security example
ALTER TABLE rule_definitions ENABLE ROW LEVEL SECURITY;

CREATE POLICY select_rules ON rule_definitions
    FOR SELECT
    USING (
        is_active = true AND (
            created_by = current_user OR
            current_user IN ('web_anon', 'web_user')
        )
    );
```

---

## REST API Endpoints

### Core Endpoints

#### 1. Health Check
```http
GET /rpc/health
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2025-12-06T10:30:00Z",
  "version": "1.0.0",
  "database": "rules_db"
}
```

#### 2. Execute Rule
```http
POST /rpc/execute_rule
Content-Type: application/json

{
  "rule_name": "loan_approval",
  "facts": {
    "Applicant": {
      "CreditScore": 750,
      "Income": 80000,
      "DebtToIncome": 0.25
    }
  }
}
```

**Response:**
```json
{
  "success": true,
  "result": {
    "Applicant": {
      "CreditScore": 750,
      "Income": 80000,
      "DebtToIncome": 0.25,
      "Approved": true,
      "InterestRate": 3.5
    }
  },
  "timestamp": "2025-12-06T10:30:00Z"
}
```

#### 3. Query Rule (Backward Chaining)
```http
POST /rpc/query_rule
Content-Type: application/json

{
  "rule_name": "patient_diagnosis",
  "query": {
    "Patient.Diagnosis": "?"
  }
}
```

**Response:**
```json
{
  "success": true,
  "result": {
    "Patient": {
      "Diagnosis": "Type2Diabetes",
      "Confidence": 0.85
    }
  },
  "timestamp": "2025-12-06T10:30:00Z"
}
```

#### 4. Validate Rule
```http
POST /rpc/validate_rule
Content-Type: application/json

{
  "rule_content": "rule \"test\" { when X > 10 then Y = 1; }"
}
```

**Response:**
```json
{
  "valid": true,
  "message": "Rule syntax is valid"
}
```

#### 5. Create Rule
```http
POST /rpc/create_rule
Content-Type: application/json
Authorization: Bearer <jwt-token>

{
  "rule_name": "discount_rule",
  "rule_content": "rule \"Discount\" { when Order.Total > 100 then Order.Discount = 10; }",
  "rule_version": "1.0.0",
  "tags": ["pricing", "discount"]
}
```

**Response:**
```json
{
  "success": true,
  "rule_id": 123,
  "rule_name": "discount_rule",
  "version": "1.0.0"
}
```

#### 6. List Rules
```http
GET /rules?select=rule_name,rule_version,created_at
```

**Response:**
```json
[
  {
    "rule_name": "loan_approval",
    "rule_version": "1.0.0",
    "created_at": "2025-11-01T10:00:00Z"
  },
  {
    "rule_name": "discount_rule",
    "rule_version": "1.0.0",
    "created_at": "2025-12-06T10:30:00Z"
  }
]
```

---

## Client SDKs

### JavaScript/TypeScript

```typescript
// rule-engine-client.ts
import axios, { AxiosInstance } from 'axios';

export interface RuleExecutionRequest {
  rule_name: string;
  facts: Record<string, any>;
}

export interface RuleExecutionResponse {
  success: boolean;
  result?: Record<string, any>;
  error?: string;
  timestamp: string;
}

export class RuleEngineClient {
  private client: AxiosInstance;

  constructor(baseURL: string, apiKey?: string) {
    this.client = axios.create({
      baseURL,
      headers: {
        'Content-Type': 'application/json',
        ...(apiKey && { 'Authorization': `Bearer ${apiKey}` })
      }
    });
  }

  async executeRule(request: RuleExecutionRequest): Promise<RuleExecutionResponse> {
    const { data } = await this.client.post('/rpc/execute_rule', request);
    return data;
  }

  async queryRule(ruleName: string, query: Record<string, any>): Promise<RuleExecutionResponse> {
    const { data } = await this.client.post('/rpc/query_rule', {
      rule_name: ruleName,
      query
    });
    return data;
  }

  async validateRule(ruleContent: string): Promise<{ valid: boolean; message?: string; error?: string }> {
    const { data } = await this.client.post('/rpc/validate_rule', {
      rule_content: ruleContent
    });
    return data;
  }

  async createRule(name: string, content: string, version: string = '1.0.0', tags?: string[]): Promise<any> {
    const { data } = await this.client.post('/rpc/create_rule', {
      rule_name: name,
      rule_content: content,
      rule_version: version,
      tags
    });
    return data;
  }

  async listRules(): Promise<any[]> {
    const { data } = await this.client.get('/rules', {
      params: { select: 'rule_name,rule_version,created_at' }
    });
    return data;
  }

  async health(): Promise<any> {
    const { data } = await this.client.get('/rpc/health');
    return data;
  }
}

// Usage
const client = new RuleEngineClient('http://localhost:3000', 'your-jwt-token');

const result = await client.executeRule({
  rule_name: 'loan_approval',
  facts: {
    Applicant: {
      CreditScore: 750,
      Income: 80000
    }
  }
});

console.log(result.success ? result.result : result.error);
```

### Python

```python
# rule_engine_client.py
import requests
from typing import Dict, Any, Optional, List

class RuleEngineClient:
    def __init__(self, base_url: str, api_key: Optional[str] = None):
        self.base_url = base_url.rstrip('/')
        self.session = requests.Session()
        self.session.headers.update({
            'Content-Type': 'application/json'
        })
        if api_key:
            self.session.headers.update({
                'Authorization': f'Bearer {api_key}'
            })
    
    def execute_rule(self, rule_name: str, facts: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a rule with given facts."""
        response = self.session.post(
            f'{self.base_url}/rpc/execute_rule',
            json={
                'rule_name': rule_name,
                'facts': facts
            }
        )
        response.raise_for_status()
        return response.json()
    
    def query_rule(self, rule_name: str, query: Dict[str, Any]) -> Dict[str, Any]:
        """Query rule using backward chaining."""
        response = self.session.post(
            f'{self.base_url}/rpc/query_rule',
            json={
                'rule_name': rule_name,
                'query': query
            }
        )
        response.raise_for_status()
        return response.json()
    
    def validate_rule(self, rule_content: str) -> Dict[str, Any]:
        """Validate rule syntax."""
        response = self.session.post(
            f'{self.base_url}/rpc/validate_rule',
            json={'rule_content': rule_content}
        )
        response.raise_for_status()
        return response.json()
    
    def create_rule(
        self,
        rule_name: str,
        rule_content: str,
        version: str = '1.0.0',
        tags: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """Create a new rule."""
        response = self.session.post(
            f'{self.base_url}/rpc/create_rule',
            json={
                'rule_name': rule_name,
                'rule_content': rule_content,
                'rule_version': version,
                'tags': tags
            }
        )
        response.raise_for_status()
        return response.json()
    
    def list_rules(self) -> List[Dict[str, Any]]:
        """List all available rules."""
        response = self.session.get(
            f'{self.base_url}/rules',
            params={'select': 'rule_name,rule_version,created_at'}
        )
        response.raise_for_status()
        return response.json()
    
    def health(self) -> Dict[str, Any]:
        """Check API health."""
        response = self.session.get(f'{self.base_url}/rpc/health')
        response.raise_for_status()
        return response.json()

# Usage
client = RuleEngineClient('http://localhost:3000', api_key='your-jwt-token')

result = client.execute_rule(
    'loan_approval',
    {
        'Applicant': {
            'CreditScore': 750,
            'Income': 80000
        }
    }
)

if result['success']:
    print(result['result'])
else:
    print(f"Error: {result['error']}")
```

### Go

```go
// rule_engine_client.go
package ruleengine

import (
    "bytes"
    "encoding/json"
    "fmt"
    "net/http"
)

type Client struct {
    BaseURL    string
    APIKey     string
    HTTPClient *http.Client
}

type RuleExecutionRequest struct {
    RuleName string                 `json:"rule_name"`
    Facts    map[string]interface{} `json:"facts"`
}

type RuleExecutionResponse struct {
    Success   bool                   `json:"success"`
    Result    map[string]interface{} `json:"result,omitempty"`
    Error     string                 `json:"error,omitempty"`
    Timestamp string                 `json:"timestamp"`
}

func NewClient(baseURL, apiKey string) *Client {
    return &Client{
        BaseURL:    baseURL,
        APIKey:     apiKey,
        HTTPClient: &http.Client{},
    }
}

func (c *Client) ExecuteRule(ruleName string, facts map[string]interface{}) (*RuleExecutionResponse, error) {
    req := RuleExecutionRequest{
        RuleName: ruleName,
        Facts:    facts,
    }
    
    body, err := json.Marshal(req)
    if err != nil {
        return nil, err
    }
    
    httpReq, err := http.NewRequest("POST", c.BaseURL+"/rpc/execute_rule", bytes.NewBuffer(body))
    if err != nil {
        return nil, err
    }
    
    httpReq.Header.Set("Content-Type", "application/json")
    if c.APIKey != "" {
        httpReq.Header.Set("Authorization", "Bearer "+c.APIKey)
    }
    
    resp, err := c.HTTPClient.Do(httpReq)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()
    
    var result RuleExecutionResponse
    if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
        return nil, err
    }
    
    return &result, nil
}

// Usage
client := ruleengine.NewClient("http://localhost:3000", "your-jwt-token")

result, err := client.ExecuteRule("loan_approval", map[string]interface{}{
    "Applicant": map[string]interface{}{
        "CreditScore": 750,
        "Income":      80000,
    },
})

if err != nil {
    panic(err)
}

if result.Success {
    fmt.Println(result.Result)
} else {
    fmt.Println("Error:", result.Error)
}
```

---

## Deployment

### Docker Compose

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: rules_db
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./migrations:/docker-entrypoint-initdb.d
    ports:
      - "5432:5432"

  postgrest:
    image: postgrest/postgrest:latest
    ports:
      - "3000:3000"
    environment:
      PGRST_DB_URI: postgres://authenticator:password@postgres:5432/rules_db
      PGRST_DB_SCHEMAS: api
      PGRST_DB_ANON_ROLE: web_anon
      PGRST_JWT_SECRET: ${JWT_SECRET}
      PGRST_OPENAPI_MODE: follow-privileges
    depends_on:
      - postgres

  swagger:
    image: swaggerapi/swagger-ui
    ports:
      - "8080:8080"
    environment:
      API_URL: http://localhost:3000/
    depends_on:
      - postgrest

volumes:
  pgdata:
```

### Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgrest
spec:
  replicas: 3
  selector:
    matchLabels:
      app: postgrest
  template:
    metadata:
      labels:
        app: postgrest
    spec:
      containers:
      - name: postgrest
        image: postgrest/postgrest:latest
        ports:
        - containerPort: 3000
        env:
        - name: PGRST_DB_URI
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: uri
        - name: PGRST_JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: jwt-secret
              key: secret
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: postgrest
spec:
  selector:
    app: postgrest
  ports:
  - port: 80
    targetPort: 3000
  type: LoadBalancer
```

---

## Security

- **JWT Authentication:** Token-based auth with roles
- **HTTPS Only:** Enforce TLS in production
- **Rate Limiting:** Use nginx/Kong for rate limits
- **CORS:** Configure allowed origins
- **Input Validation:** All inputs validated in API functions
- **SQL Injection:** PostgREST prevents SQL injection
- **Row-Level Security:** Fine-grained access control

---

## Performance

- **Connection Pooling:** PostgREST manages connection pool
- **Caching:** Add Redis/Varnish for frequently used rules
- **Horizontal Scaling:** Multiple PostgREST instances behind load balancer
- **Database Optimization:** Indexes on frequently queried columns
- **Compression:** Enable gzip for responses

**Targets:**
- Response time: < 100ms for rule execution
- Throughput: 1000+ requests/second
- Availability: 99.9% uptime

---

## Success Metrics

- **Adoption:** 80% of applications use REST API instead of direct DB
- **Performance:** < 100ms p95 latency
- **Documentation:** Complete OpenAPI spec with examples
- **Client Libraries:** SDKs for 5+ languages

---

## Changelog

- **2025-12-06:** Initial draft
