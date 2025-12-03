# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Changed
- Updated rust-rule-engine dependency from 0.14.1 to 1.6.0
- Updated serde to 1.0.228
- Updated chrono to 0.4.42

### Fixed
- Added support for `Value::Expression` variant in rust-rule-engine 1.6.0

## [1.0.0] - 2025-01-18

### 🚀 Production Ready Release

Major release with comprehensive deployment tools, enhanced error handling, and monitoring capabilities.

### Added

**Core Features:**
- Health check function: `rule_engine_health_check()`
- Version function: `rule_engine_version()`
- Structured error codes (ERR001-ERR012)
- ISO 8601 timestamps in all error responses

**Infrastructure:**
- Multi-stage Dockerfile for optimized builds
- Production-ready docker-compose.yml with health checks
- Support for PostgreSQL 13-17
- Optional PgAdmin and Prometheus exporters
- `.env.example` template with configuration options
- `postgresql.conf` with production-tuned settings
- Docker initialization scripts

**CI/CD:**
- GitHub Actions workflows for testing, linting, security audits
- Multi-version PostgreSQL testing (13-17)
- Automated releases with binary artifacts
- Docker build testing and publishing

**Documentation:**
- DEPLOYMENT.md - Comprehensive production deployment guide
- Enhanced README with production features
- Error code reference table
- Upgrade guide from 0.1.0 to 1.0.0

**Database:**
- Migration script: `rule_engine_postgre_extensions--0.1.0--1.0.0.sql`
- Extension SQL files for version 1.0.0
- Example initialization tables

### Changed

- **Version**: 0.1.0 → 1.0.0
- **Error Format**: All errors now include `error_code` and `timestamp`
- **Dependencies**: Added chrono for timestamp generation
- **Cargo.lock**: Now tracked for reproducible builds
- **Control File**: Updated with version 1.0.0 metadata
- **Install Script**: Updated to copy all SQL files

### Improved

- Centralized error handling with `create_error_response()`
- Module organization with dedicated error codes module
- Enhanced documentation with rustdoc comments
- Production-ready deployment options

### Migration from 0.1.0

```sql
-- Automatic upgrade (backward compatible)
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.0.0';

-- Verify
SELECT rule_engine_version();  -- Returns "1.0.0"
SELECT rule_engine_health_check();
```

**No breaking changes** - All existing `run_rule_engine()` calls work unchanged.

### Error Codes

| Code | Description |
|------|-------------|
| ERR001-002 | Empty inputs |
| ERR003-004 | Input too large (max 1MB) |
| ERR005-006 | Invalid JSON |
| ERR007-010 | Rule processing errors |
| ERR011-012 | Execution/serialization errors |

---

## [0.1.0] - 2024-10-31

### Added

- Initial release with basic rule engine functionality
- JSON/JSONB support with GRL syntax
- Input validation (1MB size limits)
- Comprehensive README and documentation
- English documentation files
- Helper functions for type conversion
- MIT License

### Changed

- Returns modified facts as JSON (not execution stats)
- Error messages as JSON objects
- Uses `pgrx::log!` for logging

### Fixed

- SQL function name mismatches
- Proper error handling for all Result types
- Input validation for empty and oversized inputs

---

[1.0.0]: https://github.com/KSD-CO/rule-engine-postgres/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/KSD-CO/rule-engine-postgres/releases/tag/v0.1.0
