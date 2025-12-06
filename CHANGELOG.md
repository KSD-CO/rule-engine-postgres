# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
