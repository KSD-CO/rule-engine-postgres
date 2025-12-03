# Backward Chaining Guide - Rule Engine PostgreSQL

## 📚 What is Backward Chaining?

**Backward chaining** (goal-driven reasoning) starts with a desired goal and works backwards to determine what facts must be true to achieve that goal.

### Forward vs Backward Chaining

| Aspect | Forward Chaining | Backward Chaining |
|--------|------------------|-------------------|
| **Direction** | Facts → Conclusions | Goals → Prerequisites |
| **Strategy** | Data-driven | Goal-driven |
| **Use Case** | Event processing, monitoring | Diagnosis, planning, decision trees |
| **Example** | "User logged in → Send welcome email" | "Can approve loan? → Check credit → Verify income" |

## 🎯 When to Use Backward Chaining

### Best Use Cases

1. **Medical Diagnosis**
   - Goal: What illness does the patient have?
   - Work backwards: Symptoms → Conditions → Diagnosis

2. **Troubleshooting Systems**
   - Goal: What's causing the system failure?
   - Work backwards: Observations → Issues → Root Cause

3. **Loan/Credit Approval**
   - Goal: Should we approve this loan?
   - Work backwards: Decision → Eligibility → Prerequisites → Raw Data

4. **Eligibility Determination**
   - Goal: Is person eligible for benefit?
   - Work backwards: Eligibility → Requirements → Verification

5. **Planning & Scheduling**
   - Goal: Can we complete project on time?
   - Work backwards: Timeline → Resources → Dependencies

## 🏗️ Structure of Backward Chaining Rules

### 3-Layer Architecture

```
Layer 1 (Salience 100): GOAL RULES
    ↑ (depends on)
Layer 2 (Salience 200): INFERENCE RULES
    ↑ (depends on)
Layer 3 (Salience 300): BASE CHECKS
```

### Example Structure

```grl
// Layer 3: Base checks (highest salience - execute first)
rule "CheckCredit" salience 300 {
    when
        Applicant.creditScore >= 700
    then
        Checks.hasGoodCredit = true;
}

// Layer 2: Inference rules
rule "InferEligibility" salience 200 {
    when
        Checks.hasGoodCredit == true &&
        Checks.hasStableIncome == true
    then
        Eligibility.qualifiesForLoan = true;
}

// Layer 1: Goal rules (lowest salience - execute last)
rule "ApproveLoan" salience 100 {
    when
        Eligibility.qualifiesForLoan == true
    then
        Decision.approved = true;
        Decision.amount = calculateAmount();
}
```

## 📋 Case Studies

### Case Study 1: Medical Diagnosis

**Scenario**: Diagnose patient illness based on symptoms

**Facts Structure**:
```json
{
  "Patient": {
    "symptoms": {
      "fever": true,
      "cough": true,
      "fatigue": true
    },
    "vitals": {
      "temperature": 38.5
    }
  },
  "Rules": {
    "hasFlu": false,
    "hasPneumonia": false
  }
}
```

**Rule Chain**:
```
Symptoms (fever, cough)
    ↓ salience 200
Infer Condition (hasFlu = true)
    ↓ salience 100
Make Diagnosis (diagnosis = "Influenza")
```

**Rules**:
```grl
// Inference: Determine condition
rule "InferFlu" salience 200 {
    when
        Patient.symptoms.fever == true &&
        Patient.symptoms.cough == true &&
        Patient.vitals.temperature >= 38.0
    then
        Rules.hasFlu = true;
}

// Goal: Make diagnosis
rule "DiagnoseFlu" salience 100 {
    when
        Rules.hasFlu == true
    then
        Patient.diagnosis = "Influenza";
        Patient.treatment = "Rest, fluids, antiviral";
}
```

**Test**: [tests/fixtures/backward_chaining_diagnosis.grl](tests/fixtures/backward_chaining_diagnosis.grl)

### Case Study 2: IT Troubleshooting

**Scenario**: Identify root cause of system failure

**Facts Structure**:
```json
{
  "System": {
    "observations": {
      "serverNotResponding": true,
      "diskSpaceAvailable": 5,
      "memoryUsage": 95
    },
    "diagnostics": {
      "resourceExhaustion": false
    },
    "rootCause": "unknown"
  }
}
```

**Rule Chain**:
```
Observations (low disk, high memory)
    ↓ salience 200
Infer Issue (resourceExhaustion = true)
    ↓ salience 100
Identify Root Cause (rootCause = "Resource exhaustion")
```

**Test**: [tests/fixtures/backward_chaining_troubleshooting.grl](tests/fixtures/backward_chaining_troubleshooting.grl)

### Case Study 3: Loan Decision Tree

**Scenario**: Approve loan by verifying all prerequisites

**Facts Structure**:
```json
{
  "Applicant": {
    "data": {
      "creditScore": 720,
      "income": 80000
    },
    "checks": {
      "hasGoodCredit": false,
      "hasStableIncome": false
    },
    "eligibility": {
      "qualifiesForLoan": false
    },
    "decision": "pending"
  }
}
```

**Rule Chain (4 layers)**:
```
Raw Data (creditScore, income)
    ↓ salience 300
Base Checks (hasGoodCredit, hasStableIncome)
    ↓ salience 200
Eligibility (qualifiesForLoan)
    ↓ salience 100
Decision (approved/rejected)
```

**Full Example**:
```grl
// Layer 3: Base checks (salience 300)
rule "CheckGoodCredit" salience 300 {
    when
        Applicant.data.creditScore >= 700
    then
        Applicant.checks.hasGoodCredit = true;
}

rule "CheckStableIncome" salience 300 {
    when
        Applicant.data.income >= 50000
    then
        Applicant.checks.hasStableIncome = true;
}

// Layer 2: Eligibility inference (salience 200)
rule "InferEligibility" salience 200 {
    when
        Applicant.checks.hasGoodCredit == true &&
        Applicant.checks.hasStableIncome == true
    then
        Applicant.eligibility.qualifiesForLoan = true;
}

// Layer 1: Final decision (salience 100)
rule "ApproveLoan" salience 100 {
    when
        Applicant.eligibility.qualifiesForLoan == true
    then
        Applicant.decision = "approved";
        Applicant.interestRate = 3.5;
}
```

**Test**: [tests/fixtures/backward_chaining_loan_decision.grl](tests/fixtures/backward_chaining_loan_decision.grl)

## 🎨 Design Patterns

### Pattern 1: Goal-Check-Data

**Use**: Single-level prerequisites

```grl
// Goal
rule "AchieveGoal" salience 100 {
    when
        Checks.prerequisiteMet == true
    then
        Goal.achieved = true;
}

// Check
rule "CheckPrerequisite" salience 200 {
    when
        Data.value >= threshold
    then
        Checks.prerequisiteMet = true;
}
```

### Pattern 2: Multi-Level Decision Tree

**Use**: Complex eligibility determination

```grl
// Level 1: Final decision
rule "MakeDecision" salience 100 { ... }

// Level 2: Intermediate conditions
rule "InferConditionA" salience 200 { ... }
rule "InferConditionB" salience 200 { ... }

// Level 3: Base checks
rule "CheckDataX" salience 300 { ... }
rule "CheckDataY" salience 300 { ... }
```

### Pattern 3: Diagnostic Tree with Multiple Branches

**Use**: Medical diagnosis, troubleshooting

```grl
// Multiple possible diagnoses
rule "DiagnosisA" salience 100 {
    when Rules.hasConditionA == true
    then Result.diagnosis = "A";
}

rule "DiagnosisB" salience 100 {
    when Rules.hasConditionB == true
    then Result.diagnosis = "B";
}

// Infer conditions from symptoms
rule "InferA" salience 200 {
    when symptomX && symptomY
    then Rules.hasConditionA = true;
}

rule "InferB" salience 200 {
    when symptomZ && symptomW
    then Rules.hasConditionB = true;
}
```

## 💡 Best Practices

### 1. Use Salience for Execution Order

Higher salience = execute first

```grl
// Base checks first (300)
rule "CheckData" salience 300 { ... }

// Inference second (200)
rule "InferCondition" salience 200 { ... }

// Goal last (100)
rule "MakeDecision" salience 100 { ... }
```

### 2. Separate Concerns into Objects

```json
{
  "Data": { "raw facts" },
  "Checks": { "boolean flags" },
  "Eligibility": { "intermediate state" },
  "Decision": { "final outcome" }
}
```

### 3. Use Boolean Flags for Intermediate State

```json
{
  "Checks": {
    "hasGoodCredit": false,
    "hasStableIncome": false,
    "meetsAgeRequirement": false
  }
}
```

Rules set these flags, then higher-level rules check them.

### 4. Document the Chain

```grl
// Backward Chaining: Data -> Checks -> Eligibility -> Decision
// Flow: creditScore >= 700 -> hasGoodCredit -> qualifiesForLoan -> approved
```

### 5. Handle Failure Paths

```grl
// Success path
rule "Approve" salience 100 {
    when Eligibility.qualifies == true
    then Decision.approved = true;
}

// Failure path (lower salience)
rule "Reject" salience 90 {
    when Decision.approved == false
    then Decision.reason = "Requirements not met";
}
```

## 🧪 Testing Backward Chaining

### Test Structure

```rust
#[test]
fn test_backward_chaining() {
    // 1. Setup initial state with goal unachieved
    let facts = r#"{
        "Goal": {"achieved": false},
        "Checks": {"prerequisite": false},
        "Data": {"value": 100}
    }"#;

    // 2. Define rules in backward chain
    let rules = r#"
        rule "AchieveGoal" salience 100 {
            when Checks.prerequisite == true
            then Goal.achieved = true;
        }

        rule "CheckPrerequisite" salience 200 {
            when Data.value >= 50
            then Checks.prerequisite = true;
        }
    "#;

    // 3. Execute and verify chain worked backwards
    let result = run_rule_engine(facts, rules);

    assert_eq!(result["Checks"]["prerequisite"], true);
    assert_eq!(result["Goal"]["achieved"], true);
}
```

### SQL Testing

```sql
SELECT run_rule_engine(
    '{"Goal": {"achieved": false}, "Data": {"value": 100}}',
    'rule "Check" salience 200 { ... }
     rule "Achieve" salience 100 { ... }'
)::jsonb;
```

## 📊 Performance Considerations

### Salience and Execution Order

- Execution order: salience 300 → 200 → 100
- Higher salience rules fire first
- Use this to build prerequisite chains

### Minimize Rule Count

- Each rule has overhead
- Combine related checks where possible
- Balance clarity vs performance

### Cache Intermediate Results

Store boolean flags in `Checks` object:
```json
{
  "Checks": {
    "step1Done": false,
    "step2Done": false
  }
}
```

## 🔗 Related Resources

- **Tests**: [tests/test_backward_chaining.sql](tests/test_backward_chaining.sql)
- **Fixtures**: [tests/fixtures/backward_chaining_*.{json,grl}](tests/fixtures/)
- **Integration Tests**: [tests/integration_tests.rs](tests/integration_tests.rs:240-400)

## 📚 Further Reading

- Forward vs Backward Chaining: See [README.md](README.md)
- GRL Syntax Guide: rust-rule-engine wiki
- Salience Documentation: rust-rule-engine docs

---

**Created**: 2025-12-03
**Examples**: 3 complete case studies
**Tests**: 4 Rust tests + 6 SQL tests
