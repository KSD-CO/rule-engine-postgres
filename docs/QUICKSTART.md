# 🚀 Quick Start Guide - 5 Minutes to Your First Rule

Get rule-engine-postgres running in under 5 minutes with this step-by-step guide.

---

## Prerequisites

Before starting, ensure you have:
- ✅ **PostgreSQL 16 or 17** installed
- ✅ **Linux/macOS** or Windows with WSL2
- ✅ **sudo/admin access** for installation

Not sure if you have PostgreSQL? Run:
```bash
psql --version
# Should show: psql (PostgreSQL) 16.x or 17.x
```

---

## Step 1: Install the Extension (Choose One Method)

### 🎯 Option A: Docker (Easiest - No Installation)

Perfect if you just want to try it out:

```bash
# Pull and run the pre-built Docker image
docker run -d \
  --name rule-engine-postgres \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=postgres \
  jamesvu/rule-engine-postgres:latest

# Wait 5 seconds for startup, then connect
sleep 5
psql -h localhost -U postgres -d postgres
```

✅ Done! Extension is already loaded. Skip to [Step 2](#step-2-enable-the-extension).

---

### 🎯 Option B: One-Liner Install (Ubuntu/Debian)

Best for permanent installation:

```bash
# Download and run the install script
curl -fsSL https://raw.githubusercontent.com/KSD-CO/rule-engine-postgres/main/quick-install.sh | bash
```

This script will:
- ✅ Detect your OS and PostgreSQL version
- ✅ Download the correct pre-built package
- ✅ Install the extension
- ✅ Verify installation

**Expected output:**
```
✅ Installing from pre-built package...
✅ Extension installed successfully!
✅ Verification successful!
```

---

### 🎯 Option C: Manual Download (Any OS)

If the script doesn't work:

1. **Download the package** for your system from [Releases](https://github.com/KSD-CO/rule-engine-postgres/releases/latest)

2. **Install it:**

   **Ubuntu/Debian:**
   ```bash
   sudo dpkg -i postgresql-16-rule-engine_1.5.0_amd64.deb
   ```

   **RHEL/CentOS/Rocky:**
   ```bash
   sudo rpm -i postgresql16-rule-engine-1.5.0-1.x86_64.rpm
   ```

   **macOS (Homebrew):**
   ```bash
   brew install postgresql@16
   # Then follow build from source instructions
   ```

---

## Step 2: Enable the Extension

Connect to your PostgreSQL database:

```bash
# If using Docker:
psql -h localhost -U postgres -d postgres

# If local installation:
sudo -u postgres psql -d your_database
```

Then enable the extension:

```sql
-- IMPORTANT: Install pgcrypto first (required for v1.6.0+)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create the rule engine extension
CREATE EXTENSION IF NOT EXISTS rule_engine_postgre_extensions;

-- Verify it's working
SELECT rule_engine_version();
```

**Expected output:**
```
 rule_engine_version
---------------------
 1.6.0
(1 row)
```

**Note:** The `pgcrypto` extension is required for credential encryption in External Data Sources.

✅ **Success!** The extension is ready to use.

---

## Step 3: Run Your First Rule

Let's create a simple discount rule:

### Example 1: Simple Discount Rule

```sql
-- Execute a rule that gives 10% discount for orders over $100
SELECT run_rule_engine(
    '{"Order": {"total": 150, "discount": 0}}',
    'rule "Discount" {
        when Order.total > 100
        then Order.discount = Order.total * 0.10;
    }'
)::jsonb;
```

**Result:**
```json
{
  "Order": {
    "total": 150,
    "discount": 15
  }
}
```

✅ **It worked!** The rule calculated a $15 discount (10% of $150).

---

### Example 2: Save and Reuse Rules

Instead of writing rules inline, save them for reuse:

```sql
-- 1. Save the rule once
SELECT rule_save(
    'discount_rule',
    'rule "VIPDiscount" {
        when Order.total > 100 && Customer.tier == "VIP"
        then Order.discount = Order.total * 0.20;
    }',
    '1.0.0',
    'VIP customer discount rule',
    'Initial version'
);
```

**Result:** `1` (rule ID)

```sql
-- 2. Execute it multiple times by name (no GRL text needed!)
SELECT rule_execute_by_name(
    'discount_rule',
    '{"Order": {"total": 200}, "Customer": {"tier": "VIP"}}'
)::jsonb;
```

**Result:**
```json
{
  "Order": {
    "total": 200,
    "discount": 40
  },
  "Customer": {
    "tier": "VIP"
  }
}
```

✅ **Stored rules are cleaner and reusable!**

---

### Example 3: Backward Chaining (Goal Queries)

Check if a goal can be proven:

```sql
-- Can this user vote?
SELECT query_backward_chaining(
    '{"User": {"age": 25}}',
    'rule "VotingAge" {
        when User.age >= 18
        then User.canVote = true;
    }',
    'User.canVote == true'
)::jsonb;
```

**Result:**
```json
{
  "provable": true,
  "proof_trace": "VotingAge",
  "goals_explored": 1,
  "rules_evaluated": 1,
  "query_time_ms": 0.85
}
```

✅ **Goal proven!** User can vote because they're 18+.

---

## Step 4: Try a Real-World Example

### E-Commerce Dynamic Pricing

Create a complete pricing system with multiple rules:

```sql
-- Save tiered discount rules
SELECT rule_save(
    'ecommerce_pricing',
    '
    rule "GoldTier" salience 10 {
        when
            Customer.tier == "Gold" &&
            Order.itemCount >= 10
        then
            Order.discount = 0.15;
    }

    rule "SilverTier" salience 5 {
        when
            Customer.tier == "Silver" &&
            Order.itemCount >= 5
        then
            Order.discount = 0.10;
    }

    rule "BulkDiscount" salience 1 {
        when
            Order.itemCount >= 20
        then
            Order.discount = 0.20;
    }
    ',
    '1.0.0',
    'E-commerce tiered pricing',
    'Multi-tier discount system'
);

-- Test with Gold customer buying 12 items
SELECT rule_execute_by_name(
    'ecommerce_pricing',
    '{"Customer": {"tier": "Gold"}, "Order": {"itemCount": 12, "discount": 0}}'
)::jsonb;
```

**Result:**
```json
{
  "Customer": {"tier": "Gold"},
  "Order": {
    "itemCount": 12,
    "discount": 0.15
  }
}
```

✅ **15% discount applied!** (Gold tier with 10+ items)

---

## Next Steps

### 📚 Learn More

- **[Installation Guide](INSTALLATION.md)** - Detailed installation for all platforms
- **[Usage Guide](USAGE_GUIDE.md)** - Complete feature walkthrough
- **[API Reference](api-reference.md)** - All functions and syntax
- **[Real-World Examples](examples/use-cases.md)** - Banking, Healthcare, SaaS examples

### 🎯 Common Use Cases

- **E-Commerce**: Dynamic pricing, inventory rules ([example](examples/use-cases.md#1-e-commerce-dynamic-pricing-engine))
- **Banking**: Loan approval, fraud detection ([example](examples/use-cases.md#2-banking-loan-approval-automation))
- **SaaS**: Usage-based billing ([example](examples/use-cases.md#3-saas-usage-based-billing-tiers))
- **Insurance**: Claims auto-approval ([example](examples/use-cases.md#4-insurance-claims-auto-approval))
- **Healthcare**: Patient risk assessment ([example](examples/use-cases.md#5-healthcare-patient-risk-assessment))

### 🔧 Advanced Features

- **Rule Versioning**: Manage multiple versions of rules
- **Event Triggers**: Auto-execute rules on table changes
- **Webhooks**: Call external APIs from rules
- **Testing Framework**: Test rules with assertions
- **Performance Monitoring**: Track execution stats

---

## Troubleshooting

### ❌ "Extension not found"

```sql
ERROR:  extension "rule_engine_postgre_extensions" is not available
```

**Solution:** Extension not installed. Go back to [Step 1](#step-1-install-the-extension-choose-one-method).

---

### ❌ "Permission denied"

```bash
ERROR: could not open extension control file
```

**Solution:** Use `sudo` or run as postgres user:
```bash
sudo -u postgres psql -d your_database
```

---

### ❌ Docker container not starting

```bash
docker: Error response from daemon: Conflict. The container name "/rule-engine-postgres" is already in use.
```

**Solution:** Remove old container:
```bash
docker rm -f rule-engine-postgres
# Then run the docker run command again
```

---

### 🆘 Still Having Issues?

- **[Full Troubleshooting Guide](TROUBLESHOOTING.md)** - Common errors and fixes
- **[GitHub Issues](https://github.com/KSD-CO/rule-engine-postgres/issues)** - Report bugs
- **[GitHub Discussions](https://github.com/KSD-CO/rule-engine-postgres/discussions)** - Ask questions

---

## Summary

🎉 **Congratulations!** You now have:

- ✅ Installed rule-engine-postgres
- ✅ Created and executed your first rule
- ✅ Saved rules for reuse
- ✅ Tried backward chaining
- ✅ Built a real-world pricing system

**Total time:** ~5 minutes

---

**Ready for more?** Check out the [Usage Guide](USAGE_GUIDE.md) for advanced features!
