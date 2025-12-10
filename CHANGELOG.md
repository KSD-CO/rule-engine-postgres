# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] - 2025-12-10

### Added

#### Phase 4.2: Webhook Support 🎉

**HTTP Callouts from Rules:**
- Integrate rules with external systems via webhooks
- Support for all HTTP methods (GET, POST, PUT, PATCH, DELETE)
- Custom headers and authentication configuration
- Configurable timeouts and retry policies
- Enable/disable webhooks dynamically

**Database Schema:**
- `rule_webhooks` table: Webhook endpoint configurations
- `rule_webhook_secrets` table: Secure storage for API keys and tokens
- `rule_webhook_calls` table: Active webhook call queue
- `rule_webhook_call_history` table: Complete execution history with audit trail
- Views: `webhook_status_summary`, `webhook_recent_failures`, `webhook_performance_stats`
- Indexes for optimized lookups and performance monitoring

**Webhook Management Functions:**
- `rule_webhook_register(name, url, method, headers, ...)` - Register HTTP endpoints
- `rule_webhook_update(webhook_id, ...)` - Update webhook configuration
- `rule_webhook_delete(webhook_id)` - Remove webhooks
- `rule_webhook_list()` - List all registered webhooks
- `rule_webhook_get(identifier)` - Get specific webhook details

**Secret Management Functions:**
- `rule_webhook_secret_set(webhook_id, key, value)` - Store secrets securely (SECURITY DEFINER)
- `rule_webhook_secret_get(webhook_id, key)` - Retrieve secrets (SECURITY DEFINER)
- `rule_webhook_secret_delete(webhook_id, key)` - Remove secrets
- Per-webhook secret storage with automatic cleanup on webhook deletion

**Execution Functions:**
- `rule_webhook_call(webhook_id, payload)` - Execute webhook call
- `rule_webhook_enqueue(webhook_id, payload, scheduled_for)` - Queue webhook for later processing
- `rule_webhook_call_with_http(webhook_id, payload)` - Direct HTTP call (requires HTTP extension)
- Support for both synchronous and asynchronous execution

**Retry & Monitoring Functions:**
- `rule_webhook_call_status(call_id)` - Check execution status
- `rule_webhook_retry(call_id)` - Manually retry failed calls
- `rule_webhook_process_retries(batch_size)` - Process retry queue (for external workers)
- `rule_webhook_cleanup_old_calls(days)` - Cleanup completed/failed calls
- Exponential backoff strategy with configurable multiplier
- Configurable max retries per webhook

**Monitoring Views:**
- `webhook_status_summary`: Success/failure counts and rates per webhook
- `webhook_recent_failures`: Recent failed calls for debugging
- `webhook_performance_stats`: Avg/min/max/p50/p95/p99 execution times

**Features:**
- Queue-based processing for reliability
- Automatic retry with exponential backoff
- Full audit trail of all webhook calls
- Performance metrics tracking
- Secret rotation support
- Optional HTTP extension integration
- External worker support for scalability

**Extension Files:**
- `rule_engine_postgre_extensions--1.4.0--1.5.0.sql` - Upgrade script (699 lines)
- `rule_engine_postgre_extensions--1.5.0.sql` - Base version (2,784 lines)
- Updated `.control` file to version 1.5.0

**Documentation:**
- Complete Webhook API documentation ([WEBHOOKS.md](docs/WEBHOOKS.md))
- Detailed upgrade guide ([UPGRADE_INSTRUCTIONS.md](docs/UPGRADE_INSTRUCTIONS.md))
- Usage examples: Slack notifications, CRM integration, batch processing
- External worker setup guide (Node.js example)
- Best practices and troubleshooting

### Changed
- Updated Cargo.toml version to 1.5.0
- Updated README.md with Phase 4.2 features and webhook examples
- Updated ROADMAP.md to mark Phase 4.2 as complete
- Enhanced documentation index with webhook and upgrade docs

### Performance
- Webhook validation: <1ms per call
- Queue processing: ~50-100 calls/second
- Retry logic: Exponential backoff (1s, 2s, 4s, 8s, 16s)
- Performance tracking: p50/p95/p99 percentiles calculated

### Migration
```sql
-- Upgrade from v1.4.0
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.5.0';

-- Or run migration directly
\i migrations/005_webhooks.sql
```

### Optional Dependencies
```sql
-- For actual HTTP calls (optional)
CREATE EXTENSION IF NOT EXISTS http;
```

**Note**: Without HTTP extension, webhooks are queued for processing by external workers. See [WEBHOOKS.md](docs/WEBHOOKS.md) for external worker setup.

### Backward Compatibility
✅ Fully backward compatible with v1.4.0
- All Phase 1, Phase 2 features continue to work
- No breaking changes
- Existing rules, tests, and applications unaffected
- Webhooks are optional - existing functionality unchanged

### Security
- 🔐 Secrets stored with SECURITY DEFINER functions
- 🔒 Separate secrets table with restricted access
- ✅ Input validation for URLs and payloads
- 📝 Full audit trail of all webhook calls
- 🛡️ Configurable timeouts to prevent hanging

---

## [1.4.0] - 2025-12-09

### Added

#### Phase 2: Developer Experience 🎉

**Testing Framework:**
- `rule_test_cases` table: Test definitions with assertions
- `rule_test_results` table: Test execution history
- `rule_test_coverage` table: Coverage tracking per rule
- Views: `test_suite_summary`, `recent_test_failures`
- 7 assertion types: equals, not_equals, exists, not_exists, contains, greater_than, less_than
- Functions:
  - `rule_test_create(name, rule, input, expected_output, ...)` - Create test cases
  - `rule_test_run(test_id)` - Run individual test
  - `rule_test_run_all(rule_name)` - Batch test execution
  - `rule_test_coverage(rule_name)` - Get coverage statistics

**Validation & Linting:**
- Functions:
  - `rule_validate(grl)` - Syntax validation with detailed errors
  - `rule_lint(grl, strict_mode)` - Best practices checking
- Checks: syntax compilation, empty rules, GRL structure, complex conditions (>5 AND operators), deep nesting (>10 levels), unused variables, line length (strict mode), TODO/FIXME comments, salience recommendations

**Debugging Tools:**
- `rule_debug_traces` table: Execution trace storage
- Functions:
  - `rule_debug_execute(facts, rules, session_id)` - Execute with tracing
  - `rule_trace_get(session_id)` - Retrieve execution traces
- Features: session-based tracking, before/after state comparison, error tracking

**Rule Templates:**
- `rule_templates` table: Template definitions
- `rule_template_instances` table: Instance tracking
- View: `template_usage_stats`
- Functions:
  - `rule_template_create(name, grl_template, params, ...)` - Create templates
  - `rule_template_instantiate(template_id, param_values)` - Generate rules from templates
  - `rule_template_list(category)` - List available templates
  - `rule_template_get(identifier)` - Get specific template
- 3 built-in templates: threshold_check, tier_assignment, discount_rule
- Parameter substitution with `{{param}}` syntax

**Extension Files:**
- `rule_engine_postgre_extensions--1.3.0--1.4.0.sql` - Upgrade script (797 lines)
- `rule_engine_postgre_extensions--1.4.0.sql` - Base version (2,085 lines)
- Updated `.control` file to version 1.4.0

**Documentation:**
- Complete Phase 2 API documentation ([PHASE2_DEVELOPER_EXPERIENCE.md](docs/PHASE2_DEVELOPER_EXPERIENCE.md))
- Upgrade guide ([UPGRADE_GUIDE.md](UPGRADE_GUIDE.md))
- Extension versioning guide ([EXTENSION_VERSIONING.md](EXTENSION_VERSIONING.md))
- Installation guide ([PHASE2_INSTALLATION.md](PHASE2_INSTALLATION.md))
- Implementation summary ([PHASE2_SUMMARY.md](PHASE2_SUMMARY.md))

### Changed
- Updated Cargo.toml version to 1.4.0
- Updated README.md with Phase 2 features
- Updated ROADMAP.md to mark Phase 2 as complete
- Updated install.sh to mention Phase 2 tests

### Performance
- Rule validation: ~0.034ms per validation (100 validations in 3.38ms)
- Template instantiation: ~0.153ms per instantiation (50 instantiations in 7.67ms)
- Test execution: 1-5ms depending on rule complexity
- Debug trace overhead: <1ms

### Migration
```sql
-- Upgrade from v1.3.0
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.4.0';

-- Or run migration directly
\i migrations/004_developer_experience.sql
\i migrations/004_fix.sql
```

### Backward Compatibility
✅ Fully backward compatible with v1.3.0
- All Phase 1 features continue to work
- No breaking changes
- Existing rules, tests, and applications unaffected

---

## [1.3.0] - 2025-12-07

### Added

#### Rule Sets (Collections) 🎉

**Database Schema:**
- `rule_sets` table: Named collections of rules with metadata
- `rule_set_members` table: Rule-to-set mapping with execution order
- `rule_performance_summary` view: Aggregated metrics per rule
- Cascade deletion for rule set cleanup
- Indexes for optimized lookups

**New SQL Functions:**
- `ruleset_create(name, description)` - Create new rule collections
- `ruleset_add_rule(ruleset_id, rule_name, rule_version, order)` - Add rules with ordering
- `ruleset_remove_rule(ruleset_id, rule_name, rule_version)` - Remove rules from sets
- `ruleset_execute(ruleset_id, facts_json)` - Execute all rules sequentially
- `ruleset_list()` - List all rule sets with member count
- `ruleset_get_rules(ruleset_id)` - View rules in a set ordered by execution order
- `ruleset_delete(ruleset_id)` - Delete rule sets

**Features:**
- Group multiple rules into reusable workflows
- Configurable execution order (lower numbers execute first)
- Sequential execution with output chaining
- Version-specific or default rule selection
- Active/inactive rule set management

**Rust API Wrapper:**
- `src/api/rulesets.rs` with 5 exported functions
- Full error handling and input validation
- Comprehensive documentation and examples

#### Execution Statistics Tracking 📊

**Database Schema:**
- `rule_execution_stats` table: Detailed execution records
- Tracks: duration, success/failure, facts modified, rules fired
- Time-series data with indexes for efficient querying
- Configurable retention and cleanup

**New SQL Functions:**
- `rule_record_execution(rule_name, version, time_ms, success, error, facts_modified, rules_fired)` - Log executions
- `rule_stats(rule_name, start_time, end_time)` - Comprehensive statistics with percentiles
- `rule_performance_report(limit, order_by)` - Top rules by execution/performance
- `rule_clear_stats(rule_name, before_date)` - Cleanup old statistics

**Statistics Include:**
- Total executions, success/failure counts, success rate
- Execution time: avg/min/max/median/p95/p99
- Facts modified and rules fired aggregates
- Recent error messages for debugging
- First and last execution timestamps

**Rust API Wrapper:**
- `src/api/stats.rs` with 3 exported functions
- JSON output for easy integration
- Optional time range filtering
- Efficient batch cleanup

### Changed
- Updated version to 1.3.0 across all files
- Enhanced control file description to include rule sets and statistics
- Updated `src/api/mod.rs` to export new modules

### Documentation
- Comprehensive test suite in `tests/test_rule_sets_and_stats.sql`
- 15 test scenarios covering all features
- Error handling and edge case tests
- Usage examples in README
- Migration guide in CHANGELOG

### Migration

**Upgrade from existing installation:**
```sql
-- For existing v1.0.0, v1.1.0, or v1.2.0 users
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.3.0';
-- PostgreSQL will automatically apply all intermediate migrations
```

**Fresh installation:**
```sql
CREATE EXTENSION rule_engine_postgre_extensions;
-- Installs v1.3.0 with all features (Rule Repository + Event Triggers + Rule Sets + Stats)
```

**Manual migration (if needed):**
```bash
psql -d your_database -f migrations/003_rule_sets_and_stats.sql
```

**Verify installation:**
```sql
SELECT rule_engine_version();  -- Should return "1.3.0"
SELECT COUNT(*) FROM rule_sets;  -- Should work (new table)
SELECT COUNT(*) FROM rule_execution_stats;  -- Should work (new table)
```

---

## [1.2.0] - 2025-12-07

### Added

#### Event Triggers Integration 🎉 (RFC-0002)

**Database Schema:**
- `rule_triggers` table: Trigger configurations with foreign key to rule_definitions
- `rule_trigger_history` table: Execution audit trail with timing metrics
- `rule_trigger_stats` view: Real-time statistics for monitoring
- Generic trigger function `execute_rule_trigger()` for all event types
- Indexes for performance optimization

**New SQL Functions:**
- `rule_trigger_create(name, table_name, rule_name, event_type)` - Create automatic triggers
- `rule_trigger_enable(trigger_id, enabled)` - Enable/disable without deleting
- `rule_trigger_history(trigger_id, start_time, end_time)` - View execution history
- `rule_trigger_delete(trigger_id)` - Remove triggers with cleanup

**Features:**
- Automatic rule execution on INSERT/UPDATE/DELETE events
- Full audit trail with OLD/NEW data snapshots
- Error handling without transaction rollback
- Performance monitoring (<10ms overhead per trigger)
- Support for multiple triggers per table/event
- Trigger enable/disable for maintenance

**Documentation:**
- RFC-0002 with complete technical design
- Usage examples in README
- Comprehensive test suite in `tests/test_event_triggers.sql`
- Performance benchmarks and best practices

### Changed
- Updated version to 1.2.0 across all files
- Enhanced control file description to include event triggers
- Improved Docker build process (manual installation method)

### Fixed
- Fixed Rust compilation errors in triggers module (simplified SPI usage)
- Updated `rule_trigger_history()` to return JSON instead of table type
- Dockerfile now uses `cargo build` + manual copy (avoids pgrx_embed dependency)

### Migration

**Upgrade from v1.0.0 or v1.1.0:**
```sql
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.2.0';
```

**Fresh installation:**
```sql
CREATE EXTENSION rule_engine_postgre_extensions;
-- Installs v1.3.0 (latest) with all features
```

---

## [1.1.0] - 2025-12-06

### Added

#### Rule Repository & Versioning System 🎉

**Database Schema:**
- `rule_definitions` table: Master rule records with metadata
- `rule_versions` table: Version history with semantic versioning
- `rule_tags` table: Tag-based organization system
- `rule_audit_log` table: Automatic audit trail
- Triggers for single-default enforcement and automatic logging
- Utility functions for semantic version comparison

**New SQL Functions:**
- `rule_save(name, grl_content, version, description, change_notes)` - Save rules with versioning
- `rule_get(name, version)` - Retrieve GRL content by name/version
- `rule_activate(name, version)` - Set default version
- `rule_delete(name, version)` - Delete versions or entire rules
- `rule_tag_add(name, tag)` - Add organizational tags
- `rule_tag_remove(name, tag)` - Remove tags
- `rule_execute_by_name(name, facts_json, version)` - Execute stored rules (forward chaining)
- `rule_query_by_name(name, facts_json, goal, version)` - Query goals with stored rules (backward chaining)
- `rule_can_prove_by_name(name, facts_json, goal, version)` - Fast boolean goal check with stored rules

**Features:**
- Semantic versioning (MAJOR.MINOR.PATCH) with auto-increment
- Multiple versions per rule with single default enforcement
- Tag-based categorization for filtering and organization
- Automatic audit logging of all changes
- Protection against deleting default versions
- User tracking (created_by, updated_by)
- Migration script: `migrations/001_rule_repository.sql`

**Implementation:**
- Rust module: `src/repository/` with 375+ lines
  - `queries.rs` - CRUD operations and SPI integration
  - `models.rs` - Data structures
  - `validation.rs` - Input validation (name format, GRL syntax)
  - `version.rs` - Semantic version parsing and comparison
- Integration with pgrx SPI for database operations
- Comprehensive error handling with `RuleEngineError`

**Documentation:**
- RFC-0001: Rule Repository & Versioning (complete technical design)
- Updated README with examples and API reference
- Migration guide and usage patterns

### Changed
- Extension version bumped from 1.0.0 to 1.1.0
- Control file updated with new version and description
- README enhanced with Rule Repository section
- Architecture documentation updated

### Technical Notes
- Fixed `Spi::get_one()` usage patterns for macOS compatibility
- Used EXISTS queries to avoid InvalidPosition errors
- Implemented proper SQL escaping for user inputs
- All functions tested and validated in PostgreSQL 17

### Migration

**Upgrade from v1.0.0:**
```sql
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.1.0';
```

**Fresh installation:**
```sql
CREATE EXTENSION rule_engine_postgre_extensions;
-- Installs latest version (currently 1.3.0) with all features
```

---

## [1.0.0] - 2025-11-20

### Added
- **Forward Chaining**: Event-driven rule execution
  - `run_rule_engine(facts_json, rules_grl)` function
- **Backward Chaining**: Goal-driven reasoning with proof traces
  - `query_backward_chaining(facts_json, rules_grl, goal)` function
  - `query_backward_chaining_multi(facts_json, rules_grl, goals[])` function
  - `can_prove_goal(facts_json, rules_grl, goal)` function
- **Utility Functions**:
  - `rule_engine_health_check()` - Health monitoring
  - `rule_engine_version()` - Version reporting
- **Core Features**:
  - GRL (Grule Rule Language) syntax support
  - JSON/JSONB facts processing
  - Error handling with 12 error codes
  - Input validation and size limits
  - Rust-based implementation with pgrx
- **Infrastructure**:
  - Docker and Docker Compose support
  - CI/CD with GitHub Actions
  - Migration system
  - Comprehensive documentation
  - Installation scripts (quick-install.sh, install.sh)

### Documentation
- Complete README with examples
- API reference documentation
- Integration patterns guide
- Backward chaining guide
- Use case examples (6 real-world scenarios)
- Docker deployment guide
- Build from source guide

---

## Release Notes

### v1.1.0 Highlights

The Rule Repository system brings enterprise-grade rule management to PostgreSQL:

✅ **Version Control**: Store multiple versions, roll back anytime
✅ **Safe Deployment**: Activate/deactivate versions without deleting
✅ **Organization**: Tag-based filtering for production/staging/dev
✅ **Audit Trail**: Full history of who changed what and when
✅ **Execute by Name**: No need to pass GRL content repeatedly

**Perfect for:**
- Teams managing dozens of business rules
- Multi-environment deployments (dev/staging/prod)
- Compliance requirements (audit trails)
- A/B testing different rule versions
- Gradual rollouts and rollbacks

**Migration Path:**
```sql
-- Enable Rule Repository
\i migrations/001_rule_repository.sql

-- Start using it
SELECT rule_save('my_rules', 'rule "Example" { ... }', '1.0.0', 'Initial', 'First version');
SELECT rule_execute_by_name('my_rules', '{"data": "value"}', NULL);
```

---

[1.1.0]: https://github.com/KSD-CO/rule-engine-postgres/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/KSD-CO/rule-engine-postgres/releases/tag/v1.0.0
