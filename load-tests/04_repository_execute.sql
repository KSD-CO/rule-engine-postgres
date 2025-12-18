-- pgbench script: Execute saved rules by name
-- This tests rule repository lookup and execution
-- NOTE: This test is disabled until rule repository functions are fully available

-- \set rule_num random(1, 100)
-- \set total_var random(1, 1000)

-- SELECT rule_execute_by_name(
--     format('test_rule_%s', :rule_num),
--     format('{"Order": {"total": %s, "discount": 0}}', 100 + (:total_var % 400))
-- )::jsonb;

SELECT 1; -- Placeholder
