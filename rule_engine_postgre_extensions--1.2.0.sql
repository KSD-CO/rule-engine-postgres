-- rule_engine_postgre_extensions v1.2.0
-- Production-ready PostgreSQL rule engine extension
-- Features: Forward chaining, Backward chaining, Rule Repository, Event Triggers

-- Load v1.0.0 base
\i rule_engine_postgre_extensions--1.0.0.sql

-- Apply v1.2.0 upgrade (Event Triggers)
\i migrations/002_rule_triggers.sql
