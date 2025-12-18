-- pgbench script: Complex rule execution (multiple conditions and rules)
-- This tests performance with multiple rules and complex logic

\set tier_id random(1, 1000)
\set age_offset random(1, 100)
\set total_var random(1, 1000)
\set items_var random(1, 100)

SELECT run_rule_engine(
    format('{"Customer": {"tier": "%s", "age": %s}, "Order": {"total": %s, "items": %s, "discount": 0}}',
        CASE :tier_id % 3
            WHEN 0 THEN 'Gold'
            WHEN 1 THEN 'Silver'
            ELSE 'Bronze'
        END,
        20 + (:age_offset % 60),
        50 + (:total_var % 500),
        1 + (:items_var % 50)
    ),
    'rule "GoldTier" salience 10 {
        when Customer.tier == "Gold" && Order.total > 100
        then Order.discount = Order.total * 0.15;
    }
    rule "SilverTier" salience 5 {
        when Customer.tier == "Silver" && Order.total > 200
        then Order.discount = Order.total * 0.10;
    }
    rule "BulkDiscount" salience 8 {
        when Order.items >= 20
        then Order.discount = Order.total * 0.20;
    }
    rule "SeniorDiscount" salience 7 {
        when Customer.age >= 65
        then Order.discount = Order.discount + 0.05;
    }'
)::jsonb;
