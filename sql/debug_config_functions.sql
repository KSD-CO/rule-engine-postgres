-- Debug Configuration Functions (v2.0.0)
-- Control debug mode and persistence settings

-- Note: These functions will be registered via pgrx in Rust code:
--
-- debug_enable() -> VOID
--   Enable debug mode globally
--
-- debug_disable() -> VOID
--   Disable debug mode globally
--
-- debug_enable_persistence() -> VOID
--   Enable PostgreSQL persistence for debug events
--
-- debug_disable_persistence() -> VOID
--   Disable persistence (in-memory only)
--
-- debug_status() -> TABLE(debug_enabled BOOLEAN, persistence_enabled BOOLEAN)
--   Get current debug configuration

-- Placeholder comments for documentation
COMMENT ON SCHEMA public IS
'Debug configuration functions available:
- debug_enable() - Enable debug mode
- debug_disable() - Disable debug mode
- debug_enable_persistence() - Save events to PostgreSQL
- debug_disable_persistence() - In-memory only
- debug_status() - Check current config';
