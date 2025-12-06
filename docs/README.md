# Documentation Index

Welcome to the PostgreSQL Rule Engine documentation! This directory contains comprehensive guides, examples, and references.

## Quick Links

- [Main README](../README.md) - Project overview and quick start
- [Contributing](../CONTRIBUTING.md) - How to contribute
- [Changelog](../CHANGELOG.md) - Version history and upgrade guides

---

## 📚 User Guides

### Getting Started

- **[Backward Chaining Guide](guides/backward-chaining.md)**
  Complete guide to goal-driven reasoning with backward chaining

- **[Rule Repository Quick Reference](guides/rule-repository-quick-reference.md)** ⭐ NEW
  Quick reference for versioning, tagging, and rule management

### Features (v1.1.0+)

- **[Rule Repository RFC](rfcs/0001-rule-repository.md)** ⭐ NEW
  Technical design and architecture for rule versioning system

### Deployment

- **[Docker Deployment](deployment/docker.md)**
  Deploy with Docker and Docker Compose

- **[Build from Source](deployment/build-from-source.md)**
  Manual build and installation instructions

- **[Distribution Guide](deployment/distribution.md)**
  Publishing packages and distribution strategies

---

## 🔧 Technical Documentation

### API Reference

- **[Complete API Reference](api-reference.md)**
  Detailed documentation for all functions, parameters, and return values

- **[Integration Patterns](integration-patterns.md)**
  Best practices for triggers, JSONB, batch processing, and optimization

---

## 💡 Examples and Use Cases

### Real-World Examples

- **[Use Cases](examples/use-cases.md)**
  Production-ready examples including:
  - E-Commerce: Dynamic pricing engine
  - Banking: Loan approval automation
  - SaaS: Usage-based billing tiers
  - Insurance: Claims auto-approval
  - Healthcare: Patient risk assessment
  - Backward chaining: Loan eligibility verification

---

## 🛠️ Development Resources

> **Note**: These documents are internal development notes and may be outdated.

### Development Documentation

- **[Work Summary](development/WORK_SUMMARY.md)** - Development progress and milestones
- **[Status Update](development/STATUS_UPDATE.md)** - Current project status
- **[Refactoring Plan](development/REFACTORING_PLAN.md)** - Architecture refactoring notes
- **[Refactoring Status](development/REFACTORING_STATUS.md)** - Refactoring progress
- **[Test Summary](development/TEST_SUMMARY.md)** - Test coverage and results
- **[Native Backward Chaining](development/NATIVE_BACKWARD_CHAINING.md)** - Implementation notes
- **[BC Implementation Summary](development/NATIVE_BC_IMPLEMENTATION_SUMMARY.md)** - Backward chaining details
- **[Backward Chaining Summary](development/BACKWARD_CHAINING_SUMMARY.md)** - BC feature summary
- **[CI Fix Summary](development/CI_FIX_SUMMARY.md)** - CI/CD fixes
- **[Compilation Fix Summary](development/COMPILATION_FIX_SUMMARY.md)** - Build fixes
- **[Final Summary](development/FINAL_SUMMARY.md)** - Project summary
- **[Build and Install](development/BUILD_AND_INSTALL.md)** - Legacy build notes

---

## 📖 Documentation Structure

```
docs/
├── README.md                     # This file
├── api-reference.md              # Complete API documentation
├── integration-patterns.md       # Integration best practices
├── guides/
│   └── backward-chaining.md      # Backward chaining guide
├── examples/
│   └── use-cases.md              # Real-world examples
├── deployment/
│   ├── docker.md                 # Docker deployment
│   ├── build-from-source.md      # Build instructions
│   └── distribution.md           # Distribution guide
└── development/                  # Internal development docs
    └── ...
```

---

## 🔍 Finding What You Need

### I want to...

**Get started quickly**
→ [Main README Quick Start](../README.md#quick-start)

**Learn backward chaining**
→ [Backward Chaining Guide](guides/backward-chaining.md)

**See real-world examples**
→ [Use Cases](examples/use-cases.md)

**Deploy with Docker**
→ [Docker Guide](deployment/docker.md)

**Build from source**
→ [Build Guide](deployment/build-from-source.md)

**Learn all API functions**
→ [API Reference](api-reference.md)

**Optimize performance**
→ [Integration Patterns](integration-patterns.md#performance-optimization)

**Use triggers and JSONB**
→ [Integration Patterns](integration-patterns.md)

**Contribute to the project**
→ [Contributing Guide](../CONTRIBUTING.md)

**Check version history**
→ [Changelog](../CHANGELOG.md)

---

## 🤝 Getting Help

- **Documentation Issues**: [Report here](https://github.com/KSD-CO/rule-engine-postgres/issues)
- **Questions**: [GitHub Discussions](https://github.com/KSD-CO/rule-engine-postgres/discussions)
- **Bug Reports**: [GitHub Issues](https://github.com/KSD-CO/rule-engine-postgres/issues)

---

## 📝 Improving Documentation

Found something unclear? Documentation improvements are always welcome!

See [Contributing Guide](../CONTRIBUTING.md#documentation) for how to help improve these docs.

---

**Last Updated**: 2025-01-18
**Version**: 1.0.0
