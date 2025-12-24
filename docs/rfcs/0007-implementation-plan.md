# NATS Integration - Implementation Plan & Checklist

**RFC:** 0007 - NATS Message Queue Integration
**Version:** 1.0
**Created:** 2024-12-24
**Status:** Planning

---

## 📊 Overview

This document provides a detailed, step-by-step implementation plan for NATS integration into the rule engine webhook system.

### Timeline Summary

| Phase | Duration | Scope |
|-------|----------|-------|
| **Phase 1 - Foundation** | 3-4 days | Rust setup, basic publish |
| **Phase 2 - Core Features** | 3-4 days | JetStream, SQL API, monitoring |
| **Phase 3 - Integration** | 2-3 days | Webhook integration, examples |
| **Phase 4 - Testing** | 2-3 days | Tests, benchmarks, docs |
| **Phase 5 - Production** | 1-2 days | Migration, deployment guide |
| **Total** | **11-16 days** | Full implementation |

---

## 🎯 Phase 1: Foundation (Days 1-4)

**Goal:** Set up Rust infrastructure for NATS client integration

### 1.1 Project Setup

**Duration:** 2-3 hours

- [ ] **Task 1.1.1:** Add NATS dependencies to `Cargo.toml`
  ```toml
  [dependencies]
  async-nats = "0.33"
  tokio = { version = "1.35", features = ["rt-multi-thread", "macros"] }
  serde = { version = "1.0", features = ["derive"] }
  serde_json = "1.0"
  thiserror = "1.0"
  ```
  - **Effort:** 15 min
  - **Verification:** Run `cargo check`

- [ ] **Task 1.1.2:** Create module structure
  ```
  src/nats/
    ├── mod.rs          # Module exports
    ├── config.rs       # Configuration types
    ├── client.rs       # NATS client wrapper
    ├── pool.rs         # Connection pooling
    ├── publisher.rs    # Publishing logic
    ├── error.rs        # Error types
    └── models.rs       # Data models
  ```
  - **Effort:** 30 min
  - **Verification:** Files created, module compiles

- [ ] **Task 1.1.3:** Update `src/lib.rs` to include NATS module
  ```rust
  mod nats;
  pub use nats::*;
  ```
  - **Effort:** 5 min
  - **Verification:** Module is accessible

- [ ] **Task 1.1.4:** Add NATS module to `src/api/mod.rs`
  ```rust
  pub mod nats;
  ```
  - **Effort:** 5 min

**Checkpoint:** ✅ Project structure is ready, dependencies compile

---

### 1.2 Configuration Types

**Duration:** 1-2 hours

- [ ] **Task 1.2.1:** Implement `NatsConfig` struct in `src/nats/config.rs`
  ```rust
  #[derive(Debug, Clone, Serialize, Deserialize)]
  pub struct NatsConfig {
      pub nats_url: String,
      pub cluster_urls: Option<Vec<String>>,
      pub auth_type: AuthType,
      pub connection_timeout_ms: u64,
      pub max_connections: usize,
      pub jetstream_enabled: bool,
      pub stream_name: String,
      pub subject_prefix: String,
  }
  ```
  - **Effort:** 20 min
  - **Tests:** Unit test for serialization/deserialization

- [ ] **Task 1.2.2:** Implement `AuthType` enum
  ```rust
  #[derive(Debug, Clone, Serialize, Deserialize)]
  pub enum AuthType {
      None,
      Token(String),
      Credentials(String),
      NKey(String),
  }
  ```
  - **Effort:** 15 min
  - **Tests:** Test each auth type variant

- [ ] **Task 1.2.3:** Implement `Default` for `NatsConfig`
  ```rust
  impl Default for NatsConfig {
      fn default() -> Self {
          Self {
              nats_url: "nats://localhost:4222".to_string(),
              // ... defaults
          }
      }
  }
  ```
  - **Effort:** 10 min
  - **Tests:** Test default values

- [ ] **Task 1.2.4:** Add config validation
  ```rust
  impl NatsConfig {
      pub fn validate(&self) -> Result<(), ConfigError> {
          // Validate URL format
          // Validate timeout > 0
          // Validate max_connections > 0
      }
  }
  ```
  - **Effort:** 20 min
  - **Tests:** Test valid and invalid configs

**Checkpoint:** ✅ Configuration types are complete and tested

---

### 1.3 Error Handling

**Duration:** 1 hour

- [ ] **Task 1.3.1:** Implement `NatsError` enum in `src/nats/error.rs`
  ```rust
  #[derive(Debug, thiserror::Error)]
  pub enum NatsError {
      #[error("NATS connection error: {0}")]
      ConnectionError(String),

      #[error("JetStream not enabled")]
      JetStreamNotEnabled,

      #[error("Publish error: {0}")]
      PublishError(String),

      #[error("Authentication error: {0}")]
      AuthError(String),

      #[error("Configuration error: {0}")]
      ConfigError(String),

      #[error("Pool error: {0}")]
      PoolError(String),
  }
  ```
  - **Effort:** 20 min

- [ ] **Task 1.3.2:** Implement `From<async_nats::Error>` conversion
  ```rust
  impl From<async_nats::Error> for NatsError {
      fn from(err: async_nats::Error) -> Self {
          NatsError::ConnectionError(err.to_string())
      }
  }
  ```
  - **Effort:** 10 min

- [ ] **Task 1.3.3:** Add helpful error context methods
  ```rust
  impl NatsError {
      pub fn is_retriable(&self) -> bool {
          matches!(self, Self::ConnectionError(_) | Self::PublishError(_))
      }
  }
  ```
  - **Effort:** 15 min
  - **Tests:** Test error classification

**Checkpoint:** ✅ Error types are well-defined

---

### 1.4 NATS Client Wrapper

**Duration:** 3-4 hours

- [ ] **Task 1.4.1:** Implement basic client creation in `src/nats/client.rs`
  ```rust
  pub async fn create_client(config: &NatsConfig) -> Result<Client, NatsError> {
      let mut options = ConnectOptions::new()
          .connection_timeout(Duration::from_millis(config.connection_timeout_ms));

      // Apply auth
      // Apply TLS
      // Connect

      Ok(client)
  }
  ```
  - **Effort:** 1 hour
  - **Tests:** Test connection with different configs

- [ ] **Task 1.4.2:** Implement authentication handling
  ```rust
  fn apply_auth(options: ConnectOptions, auth: &AuthType) -> Result<ConnectOptions, NatsError>
  ```
  - **Effort:** 30 min
  - **Tests:** Test each auth type

- [ ] **Task 1.4.3:** Implement connection retry logic
  ```rust
  async fn create_client_with_retry(
      config: &NatsConfig,
      max_retries: usize
  ) -> Result<Client, NatsError>
  ```
  - **Effort:** 45 min
  - **Tests:** Test retry behavior

- [ ] **Task 1.4.4:** Add health check function
  ```rust
  pub async fn check_connection(client: &Client) -> bool {
      client.connection_state() == State::Connected
  }
  ```
  - **Effort:** 15 min
  - **Tests:** Test health check

**Checkpoint:** ✅ NATS client creation is working

---

### 1.5 Connection Pooling

**Duration:** 3-4 hours

- [ ] **Task 1.5.1:** Implement `NatsPool` struct in `src/nats/pool.rs`
  ```rust
  pub struct NatsPool {
      clients: Vec<Client>,
      current_index: AtomicUsize,
      config: NatsConfig,
  }
  ```
  - **Effort:** 30 min

- [ ] **Task 1.5.2:** Implement pool initialization
  ```rust
  impl NatsPool {
      pub async fn new(config: NatsConfig) -> Result<Self, NatsError> {
          let mut clients = Vec::with_capacity(config.max_connections);

          for _ in 0..config.max_connections {
              let client = create_client(&config).await?;
              clients.push(client);
          }

          Ok(Self { clients, ... })
      }
  }
  ```
  - **Effort:** 1 hour
  - **Tests:** Test pool creation with different sizes

- [ ] **Task 1.5.3:** Implement round-robin client selection
  ```rust
  pub fn get_client(&self) -> &Client {
      let index = self.current_index
          .fetch_add(1, Ordering::Relaxed) % self.clients.len();
      &self.clients[index]
  }
  ```
  - **Effort:** 30 min
  - **Tests:** Test fair distribution

- [ ] **Task 1.5.4:** Add pool health monitoring
  ```rust
  pub fn pool_stats(&self) -> PoolStats {
      // Count healthy connections
      // Track usage stats
  }
  ```
  - **Effort:** 45 min
  - **Tests:** Test stats collection

- [ ] **Task 1.5.5:** Implement graceful shutdown
  ```rust
  pub async fn close(&mut self) -> Result<(), NatsError> {
      for client in &self.clients {
          client.flush().await?;
      }
      Ok(())
  }
  ```
  - **Effort:** 30 min
  - **Tests:** Test clean shutdown

**Checkpoint:** ✅ Connection pool is functional and tested

---

### 1.6 Global State Management

**Duration:** 2-3 hours

- [ ] **Task 1.6.1:** Create global publisher registry
  ```rust
  use std::sync::Mutex;
  use std::collections::HashMap;

  lazy_static! {
      static ref NATS_PUBLISHERS: Mutex<HashMap<String, NatsPublisher>> =
          Mutex::new(HashMap::new());
  }
  ```
  - **Effort:** 30 min
  - **Dependencies:** Add `lazy_static = "1.4"` to Cargo.toml

- [ ] **Task 1.6.2:** Add publisher registration/retrieval
  ```rust
  pub fn register_publisher(name: String, publisher: NatsPublisher) -> Result<(), NatsError>
  pub fn get_publisher(name: &str) -> Result<NatsPublisher, NatsError>
  pub fn remove_publisher(name: &str) -> Result<(), NatsError>
  ```
  - **Effort:** 1 hour
  - **Tests:** Test concurrent access

- [ ] **Task 1.6.3:** Implement thread-safety tests
  - **Effort:** 45 min
  - **Tests:** Multi-threaded registration/retrieval

**Checkpoint:** ✅ Global state is thread-safe

---

## 🚀 Phase 2: Core Features (Days 5-8)

**Goal:** Implement JetStream, publishing, and SQL API

### 2.1 Basic Publishing

**Duration:** 2-3 hours

- [ ] **Task 2.1.1:** Implement `NatsPublisher` in `src/nats/publisher.rs`
  ```rust
  pub struct NatsPublisher {
      pool: NatsPool,
      jetstream: Option<JetStreamContext>,
  }
  ```
  - **Effort:** 30 min

- [ ] **Task 2.1.2:** Implement core NATS publish (fire-and-forget)
  ```rust
  pub async fn publish(&self, subject: &str, payload: &[u8]) -> Result<(), NatsError>
  ```
  - **Effort:** 45 min
  - **Tests:** Test successful publish

- [ ] **Task 2.1.3:** Implement publish with headers
  ```rust
  pub async fn publish_with_headers(
      &self,
      subject: &str,
      headers: HeaderMap,
      payload: &[u8]
  ) -> Result<(), NatsError>
  ```
  - **Effort:** 30 min
  - **Tests:** Test header propagation

- [ ] **Task 2.1.4:** Add publish timeout handling
  ```rust
  pub async fn publish_with_timeout(
      &self,
      subject: &str,
      payload: &[u8],
      timeout: Duration
  ) -> Result<(), NatsError>
  ```
  - **Effort:** 30 min
  - **Tests:** Test timeout behavior

**Checkpoint:** ✅ Basic publishing works

---

### 2.2 JetStream Integration

**Duration:** 4-5 hours

- [ ] **Task 2.2.1:** Initialize JetStream context in publisher
  ```rust
  impl NatsPublisher {
      pub async fn new(config: NatsConfig) -> Result<Self, NatsError> {
          let pool = NatsPool::new(config.clone()).await?;

          let jetstream = if config.jetstream_enabled {
              let client = pool.get_client();
              Some(jetstream::new(client.clone()))
          } else {
              None
          };

          Ok(Self { pool, jetstream })
      }
  }
  ```
  - **Effort:** 1 hour
  - **Tests:** Test with JetStream enabled/disabled

- [ ] **Task 2.2.2:** Implement JetStream publish
  ```rust
  pub async fn publish_jetstream(
      &self,
      subject: &str,
      payload: &[u8]
  ) -> Result<JetStreamAck, NatsError>
  ```
  - **Effort:** 1 hour
  - **Tests:** Verify acknowledgment

- [ ] **Task 2.2.3:** Implement publish with message ID (deduplication)
  ```rust
  pub async fn publish_jetstream_with_id(
      &self,
      subject: &str,
      message_id: &str,
      payload: &[u8]
  ) -> Result<JetStreamAck, NatsError>
  ```
  - **Effort:** 1 hour
  - **Tests:** Test deduplication (same ID = same sequence)

- [ ] **Task 2.2.4:** Add publish acknowledgment model
  ```rust
  #[derive(Debug, Clone)]
  pub struct JetStreamAck {
      pub stream: String,
      pub sequence: u64,
      pub duplicate: bool,
  }
  ```
  - **Effort:** 30 min

- [ ] **Task 2.2.5:** Implement stream creation helper
  ```rust
  pub async fn ensure_stream(
      &self,
      stream_config: StreamConfig
  ) -> Result<(), NatsError>
  ```
  - **Effort:** 1 hour
  - **Tests:** Test stream creation/update

**Checkpoint:** ✅ JetStream publishing is working

---

### 2.3 Database Schema

**Duration:** 2-3 hours

- [ ] **Task 2.3.1:** Create migration file `migrations/007_nats_integration.sql`
  - **Effort:** 15 min

- [ ] **Task 2.3.2:** Add `rule_nats_config` table
  ```sql
  CREATE TABLE rule_nats_config (
      config_id SERIAL PRIMARY KEY,
      config_name TEXT NOT NULL UNIQUE DEFAULT 'default',
      nats_url TEXT NOT NULL DEFAULT 'nats://localhost:4222',
      -- ... (full schema from RFC)
  );
  ```
  - **Effort:** 30 min
  - **Tests:** Test table creation

- [ ] **Task 2.3.3:** Add `rule_nats_streams` table
  - **Effort:** 30 min
  - **Tests:** Test foreign key constraints

- [ ] **Task 2.3.4:** Extend `rule_webhooks` table
  ```sql
  ALTER TABLE rule_webhooks
  ADD COLUMN nats_enabled BOOLEAN DEFAULT false,
  ADD COLUMN nats_subject TEXT,
  ADD COLUMN nats_config_id INTEGER REFERENCES rule_nats_config(config_id),
  ADD COLUMN publish_mode TEXT DEFAULT 'queue';
  ```
  - **Effort:** 20 min
  - **Tests:** Test ALTER on existing data

- [ ] **Task 2.3.5:** Add `rule_nats_publish_history` table
  - **Effort:** 30 min
  - **Tests:** Test indexes

- [ ] **Task 2.3.6:** Add `rule_nats_consumer_stats` table
  - **Effort:** 20 min

- [ ] **Task 2.3.7:** Insert default configuration
  ```sql
  INSERT INTO rule_nats_config (config_name, nats_url)
  VALUES ('default', 'nats://localhost:4222')
  ON CONFLICT (config_name) DO NOTHING;
  ```
  - **Effort:** 10 min

**Checkpoint:** ✅ Database schema is complete

---

### 2.4 SQL API Functions (PL/pgSQL)

**Duration:** 3-4 hours

- [ ] **Task 2.4.1:** Implement `rule_nats_configure()`
  ```sql
  CREATE OR REPLACE FUNCTION rule_nats_configure(
      p_config_name TEXT DEFAULT 'default',
      p_nats_url TEXT DEFAULT 'nats://localhost:4222',
      ...
  ) RETURNS BOOLEAN
  ```
  - **Effort:** 45 min
  - **Tests:** Test INSERT and UPDATE scenarios

- [ ] **Task 2.4.2:** Implement `rule_nats_stream_create()`
  - **Effort:** 45 min
  - **Tests:** Test stream creation with various configs

- [ ] **Task 2.4.3:** Implement `rule_webhook_enable_nats()`
  - **Effort:** 1 hour
  - **Tests:** Test enabling NATS for webhooks

- [ ] **Task 2.4.4:** Implement `rule_nats_stats()`
  - **Effort:** 1 hour
  - **Tests:** Test stats aggregation

- [ ] **Task 2.4.5:** Add input validation for all functions
  - **Effort:** 30 min
  - **Tests:** Test invalid inputs

**Checkpoint:** ✅ SQL API functions work correctly

---

### 2.5 Rust API Functions (pgrx)

**Duration:** 4-5 hours

- [ ] **Task 2.5.1:** Create `src/api/nats.rs` file
  - **Effort:** 5 min

- [ ] **Task 2.5.2:** Implement `rule_nats_init()`
  ```rust
  #[pg_extern]
  fn rule_nats_init(config_name: &str) -> Result<JsonB, Box<dyn std::error::Error>>
  ```
  - **Effort:** 1.5 hours
  - **Steps:**
    1. Load config from `rule_nats_config` table via SPI
    2. Create `NatsPublisher`
    3. Store in global registry
    4. Return success JSON
  - **Tests:** Test initialization

- [ ] **Task 2.5.3:** Implement `rule_webhook_publish_nats()`
  ```rust
  #[pg_extern]
  fn rule_webhook_publish_nats(
      webhook_id: i32,
      payload: JsonB,
      message_id: Option<String>
  ) -> Result<JsonB, Box<dyn std::error::Error>>
  ```
  - **Effort:** 2 hours
  - **Steps:**
    1. Load webhook config via SPI
    2. Get publisher from registry
    3. Publish to NATS
    4. Record history
    5. Return acknowledgment
  - **Tests:** Test successful publish and errors

- [ ] **Task 2.5.4:** Implement `rule_webhook_call_unified()`
  ```rust
  #[pg_extern]
  fn rule_webhook_call_unified(
      webhook_id: i32,
      payload: JsonB
  ) -> Result<JsonB, Box<dyn std::error::Error>>
  ```
  - **Effort:** 1.5 hours
  - **Steps:**
    1. Check webhook `publish_mode`
    2. Route to queue, NATS, or both
    3. Return combined results
  - **Tests:** Test all three modes

**Checkpoint:** ✅ Rust API functions are working

---

### 2.6 Monitoring Views

**Duration:** 1-2 hours

- [ ] **Task 2.6.1:** Create `nats_publish_summary` view
  ```sql
  CREATE OR REPLACE VIEW nats_publish_summary AS
  SELECT ...
  ```
  - **Effort:** 30 min
  - **Tests:** Test view returns correct data

- [ ] **Task 2.6.2:** Create `nats_recent_failures` view
  - **Effort:** 20 min

- [ ] **Task 2.6.3:** Create `nats_performance_stats` view
  - **Effort:** 30 min

- [ ] **Task 2.6.4:** Add view documentation comments
  - **Effort:** 20 min

**Checkpoint:** ✅ Monitoring views are available

---

## 🔗 Phase 3: Integration (Days 9-11)

**Goal:** Integrate NATS with existing webhook system

### 3.1 Webhook Integration

**Duration:** 2-3 hours

- [ ] **Task 3.1.1:** Update existing webhook functions to check NATS mode
  - **Effort:** 1 hour
  - **Files to modify:**
    - Check if any webhook functions need updates

- [ ] **Task 3.1.2:** Add NATS option to `rule_webhook_register()`
  ```sql
  CREATE OR REPLACE FUNCTION rule_webhook_register(
      ...,
      p_enable_nats BOOLEAN DEFAULT false,
      p_nats_subject TEXT DEFAULT NULL
  )
  ```
  - **Effort:** 45 min
  - **Tests:** Test registration with NATS

- [ ] **Task 3.1.3:** Update webhook update function
  - **Effort:** 30 min

- [ ] **Task 3.1.4:** Ensure backward compatibility
  - **Effort:** 30 min
  - **Tests:** Verify existing webhooks still work

**Checkpoint:** ✅ Integration is seamless

---

### 3.2 Worker Examples

**Duration:** 4-5 hours

- [ ] **Task 3.2.1:** Create `examples/nats-workers/` directory
  - **Effort:** 5 min

- [ ] **Task 3.2.2:** Implement Node.js worker
  - **File:** `examples/nats-workers/nodejs/worker.js`
  - **Effort:** 2 hours
  - **Features:**
    - Connect to NATS
    - Subscribe to webhook subject
    - Process messages
    - Make HTTP calls
    - Acknowledge/NAK messages
  - **Tests:** Manual testing with test messages

- [ ] **Task 3.2.3:** Add Node.js package.json and README
  - **Effort:** 30 min

- [ ] **Task 3.2.4:** Implement Go worker
  - **File:** `examples/nats-workers/go/worker.go`
  - **Effort:** 2 hours
  - **Features:** Same as Node.js
  - **Tests:** Manual testing

- [ ] **Task 3.2.5:** Add Go module files and README
  - **Effort:** 30 min

- [ ] **Task 3.2.6:** Create Python worker (optional)
  - **Effort:** 2 hours (optional)

**Checkpoint:** ✅ Workers are functional

---

### 3.3 Example Scenarios

**Duration:** 2-3 hours

- [ ] **Task 3.3.1:** Create `examples/nats-integration/` directory
  - **Effort:** 5 min

- [ ] **Task 3.3.2:** Add basic setup example
  - **File:** `examples/nats-integration/01-basic-setup.sql`
  - **Effort:** 45 min

- [ ] **Task 3.3.3:** Add fan-out pattern example
  - **File:** `examples/nats-integration/02-fan-out.sql`
  - **Effort:** 45 min

- [ ] **Task 3.3.4:** Add load balancing example
  - **File:** `examples/nats-integration/03-load-balancing.sql`
  - **Effort:** 45 min

- [ ] **Task 3.3.5:** Add hybrid mode example
  - **File:** `examples/nats-integration/04-hybrid-mode.sql`
  - **Effort:** 30 min

**Checkpoint:** ✅ Examples are comprehensive

---

## ✅ Phase 4: Testing (Days 12-14)

**Goal:** Comprehensive testing at all levels

### 4.1 Unit Tests (Rust)

**Duration:** 3-4 hours

- [ ] **Task 4.1.1:** Test NATS configuration
  - **File:** `src/nats/config.rs`
  - **Effort:** 30 min
  - **Tests:**
    - Default values
    - Serialization/deserialization
    - Validation

- [ ] **Task 4.1.2:** Test NATS client creation
  - **File:** `src/nats/client.rs`
  - **Effort:** 1 hour
  - **Tests:**
    - Connection with different auth types
    - Connection failures
    - Retry logic

- [ ] **Task 4.1.3:** Test connection pool
  - **File:** `src/nats/pool.rs`
  - **Effort:** 1 hour
  - **Tests:**
    - Pool initialization
    - Round-robin distribution
    - Health monitoring
    - Shutdown

- [ ] **Task 4.1.4:** Test publisher
  - **File:** `src/nats/publisher.rs`
  - **Effort:** 1.5 hours
  - **Tests:**
    - Basic publish
    - JetStream publish
    - Deduplication
    - Error handling

**Checkpoint:** ✅ All Rust code is unit tested

---

### 4.2 Integration Tests (SQL)

**Duration:** 4-5 hours

- [ ] **Task 4.2.1:** Create test file `tests/test_nats_integration.sql`
  - **Effort:** 10 min

- [ ] **Task 4.2.2:** Test NATS configuration functions
  ```sql
  -- Test rule_nats_configure()
  -- Test rule_nats_stream_create()
  ```
  - **Effort:** 1 hour

- [ ] **Task 4.2.3:** Test webhook NATS enablement
  ```sql
  -- Test rule_webhook_enable_nats()
  ```
  - **Effort:** 45 min

- [ ] **Task 4.2.4:** Test publishing (requires running NATS server)
  ```sql
  -- Test rule_nats_init()
  -- Test rule_webhook_publish_nats()
  -- Test rule_webhook_call_unified()
  ```
  - **Effort:** 2 hours
  - **Setup:** Docker NATS server for testing

- [ ] **Task 4.2.5:** Test monitoring views
  ```sql
  -- Test nats_publish_summary
  -- Test nats_recent_failures
  -- Test nats_performance_stats
  -- Test rule_nats_stats()
  ```
  - **Effort:** 1 hour

- [ ] **Task 4.2.6:** Test error scenarios
  - **Effort:** 45 min

**Checkpoint:** ✅ SQL integration tests pass

---

### 4.3 End-to-End Tests

**Duration:** 3-4 hours

- [ ] **Task 4.3.1:** Setup test environment
  - **Effort:** 1 hour
  - **Components:**
    - PostgreSQL with extension
    - NATS server (Docker)
    - Test worker (Node.js or Go)

- [ ] **Task 4.3.2:** Test complete flow
  - **Effort:** 2 hours
  - **Scenario:**
    1. Configure NATS
    2. Register webhook with NATS
    3. Publish event from PostgreSQL
    4. Worker receives and processes
    5. Verify HTTP call made
    6. Check history and stats

- [ ] **Task 4.3.3:** Test failure scenarios
  - **Effort:** 1 hour
  - **Scenarios:**
    - NATS server down
    - Worker failure
    - Network timeout

**Checkpoint:** ✅ E2E tests validate full flow

---

### 4.4 Performance Tests

**Duration:** 3-4 hours

- [ ] **Task 4.4.1:** Create benchmark script
  - **File:** `load-tests/07_nats_publish.sql`
  - **Effort:** 1 hour

- [ ] **Task 4.4.2:** Benchmark publish throughput
  ```sql
  -- Publish 10,000 messages
  -- Measure time, calculate msg/sec
  ```
  - **Effort:** 1 hour
  - **Target:** >10,000 msg/sec

- [ ] **Task 4.4.3:** Benchmark latency (P50, P95, P99)
  - **Effort:** 1 hour
  - **Target:**
    - P50 < 5ms
    - P95 < 15ms
    - P99 < 20ms

- [ ] **Task 4.4.4:** Stress test with concurrent connections
  - **Effort:** 1 hour
  - **Test:** 100 concurrent PostgreSQL connections publishing

**Checkpoint:** ✅ Performance meets targets

---

## 📚 Phase 5: Documentation & Deployment (Days 15-16)

**Goal:** Complete documentation and production readiness

### 5.1 User Documentation

**Duration:** 4-5 hours

- [ ] **Task 5.1.1:** Create main guide `docs/NATS_INTEGRATION.md`
  - **Effort:** 2 hours
  - **Sections:**
    - Overview
    - Installation & Setup
    - Configuration
    - Usage Examples
    - Worker Setup
    - Monitoring
    - Troubleshooting
    - FAQ

- [ ] **Task 5.1.2:** Update `docs/WEBHOOKS.md` with NATS section
  - **Effort:** 30 min

- [ ] **Task 5.1.3:** Update main README.md
  - **Effort:** 30 min
  - **Add:** NATS integration feature

- [ ] **Task 5.1.4:** Create worker setup guides
  - **Files:**
    - `examples/nats-workers/nodejs/README.md`
    - `examples/nats-workers/go/README.md`
  - **Effort:** 1 hour

- [ ] **Task 5.1.5:** Create deployment guide
  - **File:** `docs/NATS_DEPLOYMENT.md`
  - **Effort:** 1 hour
  - **Topics:**
    - NATS server setup
    - Clustering
    - TLS configuration
    - Authentication
    - Monitoring

**Checkpoint:** ✅ Documentation is complete

---

### 5.2 Migration Guide

**Duration:** 2 hours

- [ ] **Task 5.2.1:** Create migration guide
  - **File:** `docs/NATS_MIGRATION.md`
  - **Effort:** 1.5 hours
  - **Sections:**
    - Prerequisites
    - Upgrade steps
    - Migrating from PostgreSQL queue to NATS
    - Rollback procedure
    - Checklist

- [ ] **Task 5.2.2:** Add migration SQL scripts
  - **File:** `migrations/007_nats_integration.sql`
  - **Effort:** 30 min
  - **Include:**
    - Safe upgrades
    - Data preservation
    - Rollback statements

**Checkpoint:** ✅ Migration is documented

---

### 5.3 API Documentation

**Duration:** 2 hours

- [ ] **Task 5.3.1:** Generate API reference
  - **Effort:** 1 hour
  - **Tools:** Extract from SQL functions and Rust docs

- [ ] **Task 5.3.2:** Add function examples
  - **Effort:** 1 hour
  - **Format:**
    ```sql
    -- Function: rule_nats_configure
    -- Description: ...
    -- Example:
    SELECT rule_nats_configure(...);
    ```

**Checkpoint:** ✅ API is documented

---

### 5.4 Production Checklist

**Duration:** 2-3 hours

- [ ] **Task 5.4.1:** Create production checklist
  - **File:** `docs/NATS_PRODUCTION_CHECKLIST.md`
  - **Effort:** 1 hour
  - **Items:**
    - [ ] NATS server is running and healthy
    - [ ] TLS is configured
    - [ ] Authentication is enabled
    - [ ] JetStream is configured
    - [ ] Workers are deployed
    - [ ] Monitoring is set up
    - [ ] Alerts are configured
    - [ ] Backup strategy for JetStream data

- [ ] **Task 5.4.2:** Create Docker Compose example
  - **File:** `examples/docker-compose.nats.yml`
  - **Effort:** 1 hour
  - **Services:**
    - PostgreSQL
    - NATS Server
    - Example worker

- [ ] **Task 5.4.3:** Create Kubernetes manifests (optional)
  - **Files:** `examples/k8s/`
  - **Effort:** 2 hours (optional)

**Checkpoint:** ✅ Production deployment is ready

---

### 5.5 Testing Documentation

**Duration:** 1 hour

- [ ] **Task 5.5.1:** Document test coverage
  - **File:** `docs/NATS_TESTING.md`
  - **Effort:** 30 min

- [ ] **Task 5.5.2:** Document how to run tests
  - **Effort:** 30 min
  - **Include:**
    - Unit tests: `cargo test`
    - Integration tests: `psql -f tests/test_nats_integration.sql`
    - E2E tests setup

**Checkpoint:** ✅ Testing is documented

---

## 📊 Implementation Tracking

### Progress Overview

```
Phase 1: Foundation          [ ] 0/19 tasks (0%)
Phase 2: Core Features       [ ] 0/31 tasks (0%)
Phase 3: Integration         [ ] 0/13 tasks (0%)
Phase 4: Testing             [ ] 0/17 tasks (0%)
Phase 5: Documentation       [ ] 0/13 tasks (0%)

Total: 0/93 tasks (0%)
```

### Daily Breakdown

| Day | Focus | Tasks | Status |
|-----|-------|-------|--------|
| 1 | Project setup, config types | 1.1-1.3 | ⬜ Not Started |
| 2 | NATS client, pool | 1.4-1.5 | ⬜ Not Started |
| 3 | Global state, publishing | 1.6, 2.1 | ⬜ Not Started |
| 4 | JetStream integration | 2.2 | ⬜ Not Started |
| 5 | Database schema | 2.3 | ⬜ Not Started |
| 6 | SQL API functions | 2.4 | ⬜ Not Started |
| 7 | Rust API functions | 2.5 | ⬜ Not Started |
| 8 | Monitoring, integration | 2.6, 3.1 | ⬜ Not Started |
| 9 | Workers, examples | 3.2, 3.3 | ⬜ Not Started |
| 10-11 | Testing (unit, integration) | 4.1, 4.2 | ⬜ Not Started |
| 12 | E2E, performance tests | 4.3, 4.4 | ⬜ Not Started |
| 13-14 | Documentation | 5.1, 5.2, 5.3 | ⬜ Not Started |
| 15 | Production prep | 5.4, 5.5 | ⬜ Not Started |
| 16 | Buffer/polish | - | ⬜ Not Started |

---

## 🚨 Critical Path

These tasks must be completed in order:

1. **Phase 1.1-1.5** → NATS client infrastructure
2. **Phase 2.1-2.2** → Publishing functionality
3. **Phase 2.3-2.5** → Database & API
4. **Phase 3.1** → Integration with webhooks
5. **Phase 4** → Testing validates everything
6. **Phase 5** → Documentation for release

**Parallel Work Opportunities:**
- Phase 3.2 (Workers) can be done alongside Phase 4 (Tests)
- Phase 5.1-5.3 (Docs) can start once APIs are stable

---

## 🎯 Success Criteria

Implementation is complete when:

- [ ] All 93 tasks are checked off
- [ ] All tests pass (unit, integration, E2E)
- [ ] Performance targets met (>10K msg/sec, <20ms P99)
- [ ] Documentation is complete
- [ ] Example workers function correctly
- [ ] Migration from existing webhooks works
- [ ] Production deployment guide is ready

---

## 📝 Notes & Risks

### Known Risks

1. **Async Rust in pgrx:** May have challenges with tokio runtime
   - **Mitigation:** Use blocking runtime, keep async isolated

2. **NATS server availability during tests**
   - **Mitigation:** Docker Compose for test environment

3. **Backward compatibility**
   - **Mitigation:** Thorough testing of existing webhooks

### Dependencies

- NATS Server 2.10+ required
- `async-nats` crate compatibility with pgrx
- PostgreSQL 12+ for tests

### Open Questions

- [ ] Should we support NATS KV for caching?
- [ ] Do we need rate limiting per webhook?
- [ ] Should workers be in separate repo?

---

## 🔄 Updates

| Date | Update | By |
|------|--------|-----|
| 2024-12-24 | Initial plan created | - |

---

**Next Step:** Start Phase 1, Task 1.1.1 - Add NATS dependencies to Cargo.toml

