---
description: Generate Zephyr test cases from issue acceptance criteria
---

# Generate Zephyr Test Cases Command

Generate structured test cases from Jira issue acceptance criteria for Zephyr Scale.

## Step 0: Load Required Skills (MANDATORY)

**BEFORE doing anything else, use the Read tool to load this skill file:**

```
Read .claude/skills/jira.md
```

This skill contains Jira MCP integration patterns needed to fetch issue details.

## Usage

```
/gen-zephyr-tests <issue-key> [--output file|clipboard]
```

**Arguments:**
- `issue-key`: Jira issue to generate test cases from
- `--output`: Where to send output (default: display)

## Workflow

### Step 1: Fetch Issue Details (Use jira skill)

Get issue with:
- Summary
- Description
- Acceptance criteria

### Step 2: Parse Acceptance Criteria

Extract testable criteria:
- Given/When/Then statements
- Bullet point requirements
- Validation rules
- Edge cases mentioned

### Step 3: Generate Test Cases

For each acceptance criterion, create:
- Test case name: `TC-[ISSUE-KEY]-[NNN]`
- Objective
- Preconditions
- Step-by-step actions
- Expected results
- Labels (API, UI, Regression, etc.)

### Step 4: Categorize Test Cases

| Type | Description |
|------|-------------|
| **Happy Path** | Normal successful flow |
| **Validation** | Input validation, error handling |
| **Edge Case** | Boundary conditions |
| **Integration** | Cross-system verification |

### Step 5: Output Results

```markdown
## Generated Test Cases for [ISSUE-KEY]

### Test Case 1: TC-INS-123-001
**Name**: [Descriptive name]

**Objective**: [What this validates]

**Preconditions**:
- [Setup requirement 1]
- [Setup requirement 2]

**Test Steps**:
| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | [Action] | [Result] |
| 2 | [Action] | [Result] |

**Labels**: [API, UI, Regression, etc.]

---

### Test Case 2: TC-INS-123-002
[...]

## Test Case Generation Summary

| Category | Count |
|----------|-------|
| Happy Path | [N] |
| Validation | [N] |
| Edge Case | [N] |
| Integration | [N] |
| **Total** | [N] |

### Next Steps
1. Review generated test cases
2. Copy to Zephyr UI
3. Link to Jira issue
4. Execute and record results
```

## Test Generation Patterns

### From "Given/When/Then"
```
Given: Preconditions
When: Test step actions
Then: Expected results
```

### From Bullet Points
Each bullet → separate test case or test step depending on granularity.

### From Validation Rules
Each rule → validation test case with valid and invalid inputs.

ARGUMENTS: $1 (issue-key), $2 (--output flag), $3 (output destination)
