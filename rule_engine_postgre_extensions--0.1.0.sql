CREATE FUNCTION run_rule_engine(facts_json TEXT, rules_grl TEXT)
RETURNS TEXT
AS 'MODULE_PATHNAME', 'run_rule_engine_wrapper'
LANGUAGE C STRICT;