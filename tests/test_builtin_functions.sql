-- Test Built-in Functions for Rule Engine PostgreSQL Extension
-- Tests all 24 built-in functions across 4 categories:
-- Date/Time, String, Math, and JSON functions

\echo '========================================='
\echo 'Testing Built-in Functions (v1.7.0)'
\echo '========================================='

-- Test 1: List All Functions
\echo ''
\echo 'Test 1: List All Built-in Functions'
\echo 'Expected: 24 functions across 4 categories'
SELECT category, COUNT(*) as count
FROM rule_function_list()
GROUP BY category
ORDER BY category;

-- Test 2: Direct Function Call - Round
\echo ''
\echo 'Test 2: Direct Function Call - Round'
\echo 'Expected: 3.14'
SELECT rule_function_call('Round', '[3.14159, 2]'::jsonb) AS round_result;

-- Test 3: Direct Function Call - IsValidEmail
\echo ''
\echo 'Test 3: Direct Function Call - IsValidEmail'
\echo 'Expected: true'
SELECT rule_function_call('IsValidEmail', '["user@example.com"]'::jsonb) AS email_valid;

\echo 'Expected: false'
SELECT rule_function_call('IsValidEmail', '["not-an-email"]'::jsonb) AS email_invalid;

-- Test 4: Math Functions in GRL - Round
\echo ''
\echo 'Test 4: Math Functions in GRL - Round'
\echo 'Expected: Order.finalPrice = 107.65'
SELECT run_rule_engine(
    '{
        "Order": {
            "subtotal": 100.00,
            "taxRate": 0.08,
            "finalPrice": 0
        }
    }',
    'rule "CalculateFinalPrice" {
        when
            Order.subtotal > 0
        then
            Order.finalPrice = Round(Order.subtotal * (1 + Order.taxRate), 2);
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Order' -> 'finalPrice' AS final_price;

-- Test 5: String Functions in GRL - Email Validation
\echo ''
\echo 'Test 5: String Functions in GRL - Email Validation'
\echo 'Expected: Customer.validEmail = true'
SELECT run_rule_engine(
    '{
        "Customer": {
            "email": "john.doe@example.com",
            "validEmail": false
        }
    }',
    'rule "ValidateEmail" {
        when
            Customer.email != nil
        then
            Customer.validEmail = IsValidEmail(Customer.email);
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Customer' -> 'validEmail' AS is_valid;

-- Test 6: String Functions - Contains & ToUpper
\echo ''
\echo 'Test 6: String Functions - Contains & ToUpper'
\echo 'Expected: Product.hasKeyword = true, Product.categoryUpper = ELECTRONICS'
SELECT run_rule_engine(
    '{
        "Product": {
            "name": "Smartphone Pro Max",
            "category": "electronics",
            "hasKeyword": false,
            "categoryUpper": ""
        }
    }',
    'rule "CheckProduct" {
        when
            Product.name != nil
        then
            Product.hasKeyword = Contains(Product.name, "Pro");
            Product.categoryUpper = ToUpper(Product.category);
    }'
) AS result \gset

\echo 'Result:'
SELECT
    :'result'::jsonb -> 'Product' -> 'hasKeyword' AS has_keyword,
    :'result'::jsonb -> 'Product' -> 'categoryUpper' AS category_upper;

-- Test 7: Math Functions - Min/Max
\echo ''
\echo 'Test 7: Math Functions - Min/Max'
\echo 'Expected: Order.minPrice = 10.5, Order.maxPrice = 99.99'
SELECT run_rule_engine(
    '{
        "Order": {
            "price1": 25.00,
            "price2": 10.50,
            "price3": 99.99,
            "minPrice": 0,
            "maxPrice": 0
        }
    }',
    'rule "PriceRange" {
        when
            Order.price1 > 0
        then
            Order.minPrice = Min(Order.price1, Order.price2, Order.price3);
            Order.maxPrice = Max(Order.price1, Order.price2, Order.price3);
    }'
) AS result \gset

\echo 'Result:'
SELECT
    :'result'::jsonb -> 'Order' -> 'minPrice' AS min_price,
    :'result'::jsonb -> 'Order' -> 'maxPrice' AS max_price;

-- Test 8: Math Functions - Abs & Sqrt
\echo ''
\echo 'Test 8: Math Functions - Abs & Sqrt'
\echo 'Expected: Result.absolute = 42, Result.squareRoot = 10'
SELECT run_rule_engine(
    '{
        "Result": {
            "negative": -42,
            "number": 100,
            "absolute": 0,
            "squareRoot": 0
        }
    }',
    'rule "MathOperations" {
        when
            Result.negative != nil
        then
            Result.absolute = Abs(Result.negative);
            Result.squareRoot = Sqrt(Result.number);
    }'
) AS result \gset

\echo 'Result:'
SELECT
    :'result'::jsonb -> 'Result' -> 'absolute' AS absolute,
    :'result'::jsonb -> 'Result' -> 'squareRoot' AS square_root;

-- Test 9: Math Functions - Floor & Ceil
\echo ''
\echo 'Test 9: Math Functions - Floor & Ceil'
\echo 'Expected: Price.floor = 42, Price.ceil = 43'
SELECT run_rule_engine(
    '{
        "Price": {
            "value": 42.7,
            "floor": 0,
            "ceil": 0
        }
    }',
    'rule "RoundingOperations" {
        when
            Price.value > 0
        then
            Price.floor = Floor(Price.value);
            Price.ceil = Ceil(Price.value);
    }'
) AS result \gset

\echo 'Result:'
SELECT
    :'result'::jsonb -> 'Price' -> 'floor' AS floor_value,
    :'result'::jsonb -> 'Price' -> 'ceil' AS ceil_value;

-- Test 10: String Functions - Trim & Length
\echo ''
\echo 'Test 10: String Functions - Trim & Length'
\echo 'Expected: Text.trimmed = "hello", Text.length = 5'
SELECT run_rule_engine(
    '{
        "Text": {
            "value": "  hello  ",
            "trimmed": "",
            "length": 0
        }
    }',
    'rule "TextProcessing" {
        when
            Text.value != nil
        then
            Text.trimmed = Trim(Text.value);
            Text.length = Length(Trim(Text.value));
    }'
) AS result \gset

\echo 'Result:'
SELECT
    :'result'::jsonb -> 'Text' -> 'trimmed' AS trimmed,
    :'result'::jsonb -> 'Text' -> 'length' AS length;

-- Test 11: String Functions - Substring
\echo ''
\echo 'Test 11: String Functions - Substring'
\echo 'Expected: Code.prefix = "ABC"'
SELECT run_rule_engine(
    '{
        "Code": {
            "value": "ABC-12345",
            "prefix": ""
        }
    }',
    'rule "ExtractPrefix" {
        when
            Code.value != nil
        then
            Code.prefix = Substring(Code.value, 0, 3);
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Code' -> 'prefix' AS prefix;

-- Test 12: String Functions - RegexMatch
\echo ''
\echo 'Test 12: String Functions - RegexMatch'
\echo 'Expected: Phone.isValid = true'
SELECT run_rule_engine(
    '{
        "Phone": {
            "number": "123-456-7890",
            "isValid": false
        }
    }',
    'rule "ValidatePhoneNumber" {
        when
            Phone.number != nil
        then
            Phone.isValid = RegexMatch(Phone.number, "^\\d{3}-\\d{3}-\\d{4}$");
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Phone' -> 'isValid' AS is_valid_phone;

-- Test 13: Date/Time Functions - Today & Now
\echo ''
\echo 'Test 13: Date/Time Functions - Today & Now'
\echo 'Expected: Event.date and Event.timestamp should be set'
SELECT run_rule_engine(
    '{
        "Event": {
            "date": "",
            "timestamp": ""
        }
    }',
    'rule "SetTimestamps" {
        when
            Event.date == ""
        then
            Event.date = Today();
            Event.timestamp = Now();
    }'
) AS result \gset

\echo 'Result:'
SELECT
    :'result'::jsonb -> 'Event' -> 'date' AS event_date,
    :'result'::jsonb -> 'Event' -> 'timestamp' AS event_timestamp;

-- Test 14: Date/Time Functions - DaysSince
\echo ''
\echo 'Test 14: Date/Time Functions - DaysSince'
\echo 'Expected: Order.daysSinceCreated should be > 0'
SELECT run_rule_engine(
    '{
        "Order": {
            "createdAt": "2024-01-01",
            "daysSinceCreated": 0
        }
    }',
    'rule "CalculateAge" {
        when
            Order.createdAt != nil
        then
            Order.daysSinceCreated = DaysSince(Order.createdAt);
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Order' -> 'daysSinceCreated' AS days_since;

-- Test 15: Date/Time Functions - AddDays
\echo ''
\echo 'Test 15: Date/Time Functions - AddDays'
\echo 'Expected: Subscription.expiresAt = 2024-02-01'
SELECT run_rule_engine(
    '{
        "Subscription": {
            "startDate": "2024-01-01",
            "expiresAt": ""
        }
    }',
    'rule "SetExpirationDate" {
        when
            Subscription.startDate != nil
        then
            Subscription.expiresAt = AddDays(Subscription.startDate, 31);
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Subscription' -> 'expiresAt' AS expires_at;

-- Test 16: Date/Time Functions - FormatDate
\echo ''
\echo 'Test 16: Date/Time Functions - FormatDate'
\echo 'Expected: Report.formattedDate in custom format'
SELECT run_rule_engine(
    '{
        "Report": {
            "date": "2024-12-20",
            "formattedDate": ""
        }
    }',
    'rule "FormatReportDate" {
        when
            Report.date != nil
        then
            Report.formattedDate = FormatDate(Report.date, "%B %d, %Y");
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Report' -> 'formattedDate' AS formatted_date;

-- Test 17: JSON Functions - JsonParse & JsonStringify
\echo ''
\echo 'Test 17: JSON Functions - JsonParse & JsonStringify'
\echo 'Expected: Parse and re-stringify JSON data'
SELECT run_rule_engine(
    '{
        "Data": {
            "jsonString": "{\"name\":\"John\",\"age\":30}",
            "parsed": null,
            "stringified": ""
        }
    }',
    'rule "ProcessJSON" {
        when
            Data.jsonString != nil
        then
            Data.parsed = JsonParse(Data.jsonString);
            Data.stringified = JsonStringify(Data.parsed);
    }'
) AS result \gset

\echo 'Result:'
SELECT
    :'result'::jsonb -> 'Data' -> 'parsed' AS parsed,
    :'result'::jsonb -> 'Data' -> 'stringified' AS stringified;

-- Test 18: JSON Functions - JsonGet
\echo ''
\echo 'Test 18: JSON Functions - JsonGet'
\echo 'Expected: Extract nested value from JSON'
SELECT run_rule_engine(
    '{
        "Config": {
            "settings": {"database": {"host": "localhost", "port": 5432}},
            "dbHost": ""
        }
    }',
    'rule "ExtractConfig" {
        when
            Config.settings != nil
        then
            Config.dbHost = JsonGet(Config.settings, "database.host");
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Config' -> 'dbHost' AS db_host;

-- Test 19: JSON Functions - JsonSet
\echo ''
\echo 'Test 19: JSON Functions - JsonSet'
\echo 'Expected: Update nested JSON value'
SELECT run_rule_engine(
    '{
        "User": {
            "profile": {"name": "John", "age": 30},
            "updatedProfile": null
        }
    }',
    'rule "UpdateProfile" {
        when
            User.profile != nil
        then
            User.updatedProfile = JsonSet(User.profile, "age", 31);
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'User' -> 'updatedProfile' AS updated_profile;

-- Test 20: Complex Rule - E-Commerce with Multiple Functions
\echo ''
\echo 'Test 20: Complex E-Commerce Rule with Multiple Functions'
\echo 'Expected: Comprehensive order processing with validation and calculations'
SELECT run_rule_engine(
    '{
        "Order": {
            "id": "ORD-12345",
            "createdAt": "2024-12-01",
            "subtotal": 99.99,
            "taxRate": 0.08,
            "total": 0,
            "finalTotal": 0,
            "daysSinceOrder": 0,
            "orderAge": "",
            "orderPrefix": ""
        },
        "Customer": {
            "email": "jane.smith@example.com",
            "emailValid": false,
            "tier": "gold",
            "tierUpper": "",
            "discountRate": 0
        }
    }',
    'rule "ProcessOrder" salience 100 {
        when
            Order.subtotal > 0 && Customer.email != nil
        then
            Customer.emailValid = IsValidEmail(Customer.email);
            Customer.tierUpper = ToUpper(Customer.tier);
            Order.total = Round(Order.subtotal * (1 + Order.taxRate), 2);
            Order.daysSinceOrder = DaysSince(Order.createdAt);
            Order.orderPrefix = Substring(Order.id, 0, 3);
    }

    rule "ApplyDiscount" salience 50 {
        when
            Customer.tierUpper == "GOLD" && Order.total > 50
        then
            Customer.discountRate = 0.10;
            Order.finalTotal = Round(Order.total * (1 - Customer.discountRate), 2);
    }

    rule "SetOrderAge" salience 10 {
        when
            Order.daysSinceOrder > 7
        then
            Order.orderAge = "old";
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb AS complete_result;

-- Test 21: Negative Test - Invalid Function Name
\echo ''
\echo 'Test 21: Negative Test - Invalid Function Name'
\echo 'Expected: Error message about unknown function'
SELECT rule_function_call('NonExistentFunction', '[]'::jsonb) AS error_result;

-- Test 22: String Functions - ToLower for Case-Insensitive Comparison
\echo ''
\echo 'Test 22: String Functions - ToLower for Case-Insensitive Comparison'
\echo 'Expected: Search.match = true'
SELECT run_rule_engine(
    '{
        "Search": {
            "query": "POSTGRES",
            "target": "PostgreSQL Database",
            "match": false
        }
    }',
    'rule "CaseInsensitiveSearch" {
        when
            Search.query != nil
        then
            Search.match = Contains(ToLower(Search.target), ToLower(Search.query));
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Search' -> 'match' AS search_match;

-- Test 23: Real-World Use Case - Loan Application with Functions
\echo ''
\echo 'Test 23: Real-World Use Case - Loan Application Processing'
\echo 'Expected: Complete loan application validation and calculation'
SELECT run_rule_engine(
    '{
        "Applicant": {
            "email": "applicant@bank.com",
            "emailValid": false,
            "name": "  john doe  ",
            "normalizedName": "",
            "creditScore": 750,
            "income": 75000.50,
            "debtToIncome": 0.28,
            "approved": false,
            "maxLoan": 0,
            "monthlyPayment": 0
        },
        "Application": {
            "submittedAt": "2024-11-15",
            "processingDays": 0,
            "status": "pending"
        }
    }',
    'rule "ValidateApplicant" salience 100 {
        when
            Applicant.email != nil && Applicant.name != nil
        then
            Applicant.emailValid = IsValidEmail(Applicant.email);
            Applicant.normalizedName = Trim(Applicant.name);
            Application.processingDays = DaysSince(Application.submittedAt);
    }

    rule "ApproveLoan" salience 50 {
        when
            Applicant.emailValid == true &&
            Applicant.creditScore >= 700 &&
            Applicant.debtToIncome < 0.35
        then
            Applicant.approved = true;
            Applicant.maxLoan = Round(Applicant.income * 3, 2);
            Applicant.monthlyPayment = Round(Applicant.maxLoan * 0.004, 2);
            Application.status = "approved";
    }

    rule "ExpediteProcessing" salience 25 {
        when
            Application.processingDays > 30 && Applicant.approved == false
        then
            Application.status = "expedite_review";
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb AS loan_application_result;

-- Test 24: Performance Test - Multiple Function Calls
\echo ''
\echo 'Test 24: Performance Test - Multiple Function Calls'
\echo 'Expected: Fast execution with many function calls'
\timing on
SELECT run_rule_engine(
    '{
        "Data": {
            "text1": "  hello world  ",
            "text2": "GOODBYE",
            "num1": 3.14159,
            "num2": -42.7,
            "date1": "2024-01-01",
            "result1": "",
            "result2": "",
            "result3": 0,
            "result4": 0,
            "result5": 0,
            "result6": ""
        }
    }',
    'rule "MultipleOperations" {
        when
            Data.text1 != nil
        then
            Data.result1 = ToUpper(Trim(Data.text1));
            Data.result2 = ToLower(Data.text2);
            Data.result3 = Round(Data.num1, 2);
            Data.result4 = Abs(Data.num2);
            Data.result5 = DaysSince(Data.date1);
            Data.result6 = Substring(Data.text1, 2, 5);
    }'
) AS result \gset
\timing off

\echo 'Result:'
SELECT :'result'::jsonb AS performance_result;

\echo ''
\echo '========================================='
\echo 'Built-in Functions Tests Complete!'
\echo '========================================='
