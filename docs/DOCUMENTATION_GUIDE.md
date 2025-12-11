# 📚 Documentation Guide

Welcome to the rule-engine-postgres documentation! This guide helps you navigate all our docs.

---

## 📖 Documentation Structure

We've organized docs into three main categories for easy navigation:

### 1️⃣ Getting Started (New Users)
Start here if you're new to rule-engine-postgres.

| Document | Description | Time |
|----------|-------------|------|
| **[Quick Start](QUICKSTART.md)** | Run your first rule in 5 minutes | 5 min |
| **[Installation Guide](INSTALLATION.md)** | Detailed install for all platforms | 10-15 min |
| **[Troubleshooting](TROUBLESHOOTING.md)** | Fix common issues | As needed |

---

### 2️⃣ User Guides (Learning)
Learn how to use all features effectively.

| Document | Description | Level |
|----------|-------------|-------|
| **[Usage Guide](USAGE_GUIDE.md)** | Complete feature walkthrough | Beginner |
| **[Backward Chaining](guides/backward-chaining.md)** | Goal-driven reasoning guide | Intermediate |
| **[Webhooks](WEBHOOKS.md)** | HTTP callouts and retry logic | Intermediate |
| **[Testing Framework](PHASE2_DEVELOPER_EXPERIENCE.md)** | Test rules with assertions | Advanced |
| **[Use Cases](examples/use-cases.md)** | Real-world production examples | All levels |

---

### 3️⃣ Reference (Look Up)
Quick reference when you need specific info.

| Document | Description | Use When |
|----------|-------------|----------|
| **[API Reference](api-reference.md)** | All functions and syntax | Need function signature |
| **[Integration Patterns](integration-patterns.md)** | Triggers, JSONB, performance | Integrating with app |
| **[Upgrade Instructions](UPGRADE_INSTRUCTIONS.md)** | Version migration guide | Upgrading version |
| **[Roadmap](ROADMAP.md)** | Future plans | Planning long-term |

---

### 4️⃣ Development (Contributors)
For developers working on the extension.

| Document | Description | Use When |
|----------|-------------|----------|
| **[Build from Source](deployment/build-from-source.md)** | Manual build instructions | Building locally |
| **[Docker Deployment](deployment/docker.md)** | Docker and Compose | Containerizing |
| **[Distribution Guide](deployment/distribution.md)** | Package distribution | Creating packages |
| **[RFC: Rule Repository](rfcs/0001-rule-repository.md)** | Technical design | Understanding internals |

---

## 🗺️ Quick Navigation

### "I want to..."

#### ...get started quickly
→ [Quick Start Guide](QUICKSTART.md) (5 minutes)

#### ...install on my system
→ [Installation Guide](INSTALLATION.md)
- Docker: Section "Method 1"
- Ubuntu/Debian: Section "Method 2" or "Method 3"
- RHEL/Rocky: Section "Method 3"
- Build from source: Section "Method 4"

#### ...learn all features
→ [Usage Guide](USAGE_GUIDE.md)

#### ...fix an error
→ [Troubleshooting Guide](TROUBLESHOOTING.md)
- Search for your error code (ERR001, ERR002, etc.)
- Check common installation issues
- Check runtime errors section

#### ...see real examples
→ [Use Cases](examples/use-cases.md)
- E-commerce pricing
- Banking loan approval
- SaaS billing
- Insurance claims
- Healthcare risk assessment

#### ...look up a function
→ [API Reference](api-reference.md)
- Forward chaining functions
- Backward chaining functions
- Rule repository functions
- Trigger functions

#### ...use backward chaining
→ [Backward Chaining Guide](guides/backward-chaining.md)

#### ...call webhooks from rules
→ [Webhooks Guide](WEBHOOKS.md)

#### ...integrate with my app
→ [Integration Patterns](integration-patterns.md)
- Database triggers
- JSONB storage
- Performance optimization
- Application patterns

#### ...upgrade to latest version
→ [Upgrade Instructions](UPGRADE_INSTRUCTIONS.md)

#### ...contribute code
→ [Build from Source](deployment/build-from-source.md) + [CONTRIBUTING.md](../CONTRIBUTING.md)

---

## 📋 Recommended Reading Order

### For Beginners

1. **[Quick Start](QUICKSTART.md)** - Get hands-on experience first
2. **[Installation Guide](INSTALLATION.md)** - Proper installation for your system
3. **[Usage Guide](USAGE_GUIDE.md)** - Learn all features systematically
4. **[Use Cases](examples/use-cases.md)** - See real-world applications
5. **[API Reference](api-reference.md)** - Bookmark for later reference

### For Experienced Developers

1. **[Quick Start](QUICKSTART.md)** - Quick overview
2. **[API Reference](api-reference.md)** - Function signatures
3. **[Use Cases](examples/use-cases.md)** - Real-world patterns
4. **[Integration Patterns](integration-patterns.md)** - Advanced integration
5. **[RFC](rfcs/0001-rule-repository.md)** - Technical internals

### For System Administrators

1. **[Installation Guide](INSTALLATION.md)** - Production deployment
2. **[Docker Deployment](deployment/docker.md)** - Containerization
3. **[Troubleshooting](TROUBLESHOOTING.md)** - Issue resolution
4. **[Upgrade Instructions](UPGRADE_INSTRUCTIONS.md)** - Version management

---

## 🔍 How to Find Information Fast

### Using Search

**In GitHub:**
1. Press `/` to activate search
2. Type your keyword (e.g., "backward chaining")
3. Filter by "Code" or "Issues"

**In Local Clone:**
```bash
# Search all markdown files
grep -r "backward chaining" docs/

# Search specific doc
grep "rule_save" docs/api-reference.md
```

### By Error Code

All error codes are documented in:
- [Troubleshooting](TROUBLESHOOTING.md) - Solutions
- [API Reference](api-reference.md) - Error code table

### By Feature

| Feature | Primary Doc | Additional Docs |
|---------|-------------|-----------------|
| **Forward Chaining** | [Usage Guide](USAGE_GUIDE.md) | [API Ref](api-reference.md), [Use Cases](examples/use-cases.md) |
| **Backward Chaining** | [Backward Chaining Guide](guides/backward-chaining.md) | [API Ref](api-reference.md) |
| **Rule Versioning** | [Usage Guide](USAGE_GUIDE.md) | [RFC](rfcs/0001-rule-repository.md) |
| **Event Triggers** | [Usage Guide](USAGE_GUIDE.md) | [Integration](integration-patterns.md) |
| **Webhooks** | [Webhooks Guide](WEBHOOKS.md) | [API Ref](api-reference.md) |
| **Testing** | [Phase 2 Guide](PHASE2_DEVELOPER_EXPERIENCE.md) | - |

---

## 📱 Documentation by Platform

### Docker Users
1. [Quick Start](QUICKSTART.md) - Method 1 (Docker)
2. [Docker Deployment](deployment/docker.md)
3. [Troubleshooting](TROUBLESHOOTING.md) - Docker section

### Ubuntu/Debian Users
1. [Installation Guide](INSTALLATION.md) - Method 2 or 3
2. [Troubleshooting](TROUBLESHOOTING.md) - Ubuntu section

### RHEL/Rocky/AlmaLinux Users
1. [Installation Guide](INSTALLATION.md) - Method 3
2. [Troubleshooting](TROUBLESHOOTING.md) - RHEL section

### macOS Users
1. [Installation Guide](INSTALLATION.md) - Method 4 (Build from Source)
2. [Build from Source](deployment/build-from-source.md)

### Windows (WSL2) Users
1. Install WSL2 with Ubuntu
2. Follow Ubuntu documentation

---

## 🎯 Documentation by Use Case

### E-Commerce Application
- [Use Case: E-Commerce Pricing](examples/use-cases.md#1-e-commerce-dynamic-pricing-engine)
- [Integration Patterns](integration-patterns.md)
- [Event Triggers](USAGE_GUIDE.md) (for auto-discounts)

### Banking/Finance Application
- [Use Case: Loan Approval](examples/use-cases.md#2-banking-loan-approval-automation)
- [Backward Chaining Guide](guides/backward-chaining.md) (for eligibility)

### SaaS Application
- [Use Case: Usage-Based Billing](examples/use-cases.md#3-saas-usage-based-billing-tiers)
- [Event Triggers](USAGE_GUIDE.md) (for auto-tier calculation)

### Insurance Application
- [Use Case: Claims Auto-Approval](examples/use-cases.md#4-insurance-claims-auto-approval)
- [Webhooks](WEBHOOKS.md) (for notifications)

### Healthcare Application
- [Use Case: Risk Assessment](examples/use-cases.md#5-healthcare-patient-risk-assessment)
- [Backward Chaining](guides/backward-chaining.md) (for diagnosis)

---

## 💡 Documentation Tips

### For Best Learning Experience

1. **Start with hands-on**: Don't just read, try examples in [Quick Start](QUICKSTART.md)
2. **Use real data**: Adapt examples to your actual use case
3. **Read error messages**: They contain the error code - search for it
4. **Check timestamps**: Some docs reference specific versions

### When You're Stuck

1. **Search first**: Use GitHub search or `grep`
2. **Check Troubleshooting**: Most common issues are documented
3. **Read related sections**: API Reference + Use Cases + Guide
4. **Ask for help**: [GitHub Discussions](https://github.com/KSD-CO/rule-engine-postgres/discussions)

### Contributing to Docs

Found a typo or unclear section?

1. **Quick fix**: Click "Edit this file" on GitHub
2. **Major change**: Open an issue first to discuss
3. **New example**: Add to [Use Cases](examples/use-cases.md)

---

## 📌 Important Documents (Bookmark These)

### Must-Read
- ✅ [Quick Start](QUICKSTART.md)
- ✅ [Installation Guide](INSTALLATION.md)
- ✅ [Troubleshooting](TROUBLESHOOTING.md)

### Reference (Keep Open)
- 📖 [API Reference](api-reference.md)
- 💼 [Use Cases](examples/use-cases.md)

### Occasionally Needed
- 🔧 [Integration Patterns](integration-patterns.md)
- 📡 [Webhooks](WEBHOOKS.md)
- 🎯 [Backward Chaining](guides/backward-chaining.md)

---

## 🔄 Documentation Versions

This documentation is for **rule-engine-postgres v1.5.0**.

**Version-specific docs:**
- v1.5.0: Webhooks support added
- v1.4.0: Testing framework added
- v1.3.0: Templates and debugging added
- v1.2.0: Event triggers added
- v1.1.0: Rule repository added
- v1.0.0: Initial release

**Upgrading?** See [Upgrade Instructions](UPGRADE_INSTRUCTIONS.md)

---

## 📧 Documentation Feedback

Help us improve! If you:
- Found a typo or error
- Have a suggestion for clarity
- Want a new example
- Need a specific guide

**Open an issue:** [Documentation Issue](https://github.com/KSD-CO/rule-engine-postgres/issues/new?labels=documentation)

---

## 🌟 Popular Pages (Most Viewed)

1. [Quick Start](QUICKSTART.md) - Getting started fast
2. [Installation Guide](INSTALLATION.md) - Installation methods
3. [API Reference](api-reference.md) - Function lookup
4. [Use Cases](examples/use-cases.md) - Real-world examples
5. [Troubleshooting](TROUBLESHOOTING.md) - Fixing errors

---

## 📚 External Resources

### Official PostgreSQL Docs
- [PostgreSQL Extensions](https://www.postgresql.org/docs/current/extend-extensions.html)
- [JSON Functions](https://www.postgresql.org/docs/current/functions-json.html)
- [Triggers](https://www.postgresql.org/docs/current/triggers.html)

### GRL Language
- [Grule Rule Engine](https://github.com/hyperjumptech/grule-rule-engine)
- [rust-rule-engine](https://github.com/haydnba/rust-rule-engine)

### Related Topics
- [Rule Engines Comparison](https://en.wikipedia.org/wiki/Business_rules_engine)
- [Forward vs Backward Chaining](https://en.wikipedia.org/wiki/Forward_chaining)

---

**Happy Reading! 📖**

If you're new, start with [Quick Start](QUICKSTART.md) →
