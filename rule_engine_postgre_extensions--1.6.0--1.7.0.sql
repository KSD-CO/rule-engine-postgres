-- Migration from v1.6.0 to v1.7.0
-- Adds built-in functions library with 24 functions

-- New SQL wrapper functions for built-in functions
CREATE OR REPLACE FUNCTION rule_function_call(
    function_name text,
    args_json jsonb
) RETURNS jsonb
LANGUAGE c
AS 'MODULE_PATHNAME', 'rule_function_call_wrapper';

CREATE OR REPLACE FUNCTION rule_function_list()
RETURNS TABLE(
    function_name text,
    category text,
    description text
)
LANGUAGE c
AS 'MODULE_PATHNAME', 'rule_function_list_wrapper';

-- No schema changes required - built-in functions work via preprocessing
-- All existing rules continue to work without modification
-- Users can now use 24 built-in functions in GRL when conditions:
--   Date/Time: DaysSince, AddDays, FormatDate, Now, Today
--   String: IsValidEmail, Contains, RegexMatch, ToUpper, ToLower, Trim, Length, Substring
--   Math: Round, Abs, Min, Max, Floor, Ceil, Sqrt
--   JSON: JsonParse, JsonStringify, JsonGet, JsonSet
