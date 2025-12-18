-- pgbench script: Simple rule execution (1 condition)
-- This tests basic forward chaining performance

\set total random(50, 500)

SELECT run_rule_engine(
    format('{"Order": {"total": %s, "discount": 0}}', :total),
    'rule "SimpleDiscount" {
        when Order.total > 100
        then Order.discount = Order.total * 0.10;
    }'
)::jsonb;
