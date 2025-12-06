# RFCs (Request for Comments)

This directory contains design documents for major features being added to the Rule Engine PostgreSQL extension.

## What is an RFC?

An RFC is a design document that:
- Describes the motivation and use cases for a feature
- Proposes a technical design and implementation approach
- Lists alternatives considered
- Identifies potential issues and trade-offs
- Serves as documentation for the decision-making process

## When to write an RFC?

Write an RFC when:
- Adding a major new feature (Phase 1+ in ROADMAP.md)
- Making breaking changes to existing APIs
- Introducing new dependencies or architectural changes
- Making performance-critical modifications

You don't need an RFC for:
- Bug fixes
- Documentation improvements
- Small refactorings
- Minor feature additions

## RFC Process

1. **Draft:** Copy `0000-template.md` to `XXXX-feature-name.md`
2. **Discussion:** Open a GitHub issue linking to your RFC
3. **Iteration:** Update based on feedback
4. **Decision:** Maintainers approve/reject the RFC
5. **Implementation:** Create PRs referencing the RFC number

## RFC Status

- **Draft:** Under discussion
- **Accepted:** Approved for implementation
- **Implemented:** Feature is live
- **Rejected:** Not moving forward
- **Superseded:** Replaced by another RFC

## Active RFCs

| Number | Title | Status | Author | Date |
|--------|-------|--------|--------|------|
| 0001 | Rule Repository & Versioning | Draft | - | 2025-12-06 |
| 0002 | Rule Execution Statistics | Draft | - | 2025-12-06 |
| 0003 | Rule Testing Framework | Draft | - | 2025-12-06 |

## How to contribute

1. Read existing RFCs to understand the format
2. Fork the repository
3. Create your RFC using the template
4. Submit a PR with your RFC
5. Engage in discussion on the PR

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for more details.
