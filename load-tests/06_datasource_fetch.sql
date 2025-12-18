-- pgbench script: External datasource fetch with caching
-- This tests API fetching, caching, and performance
-- NOTE: Requires datasource to be registered first (see setup.sql)

\set customer_id random(1, 1000)

SELECT rule_datasource_fetch(
    1,  -- datasource_id (created in setup)
    format('/api/v1/customer/%s', :customer_id),
    '{}'::JSONB
);
