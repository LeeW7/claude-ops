---
description: Comprehensive code review with security, performance, and architecture analysis
---

# Review PR Command

Perform comprehensive code review with security, performance, and architecture analysis.

## Usage

```
/review-pr <pr-number> [--quick] [--security-only] [--perf-only]
```

**Flags:**
- `--quick`: Skip security and performance deep-dive
- `--security-only`: Only run security review
- `--perf-only`: Only run performance review

## Workflow

### Step 1: Fetch PR Details

```bash
# Get PR information
gh pr view <pr-number>

# Get list of changed files
gh pr diff <pr-number> --name-only

# Get the full diff
gh pr diff <pr-number>
```

### Step 2: Understand Context

- Read linked issue for requirements
- Check PR description
- Understand scope of changes

### Step 3: Code Quality Review

Check for:
- **Style & Conventions**: Consistent with codebase patterns
- **Architecture**: Aligns with project structure (see CLAUDE.md)
- **Error Handling**: Proper exception handling, no swallowed errors
- **Test Coverage**: New code has tests, edge cases covered
- **Documentation**: Complex logic explained, public APIs documented
- **DRY Principle**: No unnecessary duplication
- **SOLID Principles**: Single responsibility, proper abstractions

### Step 4: Security Review

Unless `--quick` or `--perf-only` flag, check OWASP Top 10:

- **Injection**: SQL, command, LDAP injection vulnerabilities
- **Auth Issues**: Session handling, password storage, token management
- **Sensitive Data**: Hardcoded secrets, credentials in logs, PII exposure
- **Access Control**: Authorization checks on endpoints, privilege escalation
- **XSS**: Output encoding, user input in HTML/JS
- **Dependencies**: Known vulnerabilities in added dependencies
- **Input Validation**: All external input validated and sanitized

### Step 5: Performance Review

Unless `--quick` or `--security-only` flag, check for:

- **N+1 Queries**: Database calls inside loops
- **Missing Indexes**: Queries on non-indexed fields
- **Memory Issues**: Large collections in memory, stream handling
- **Blocking Calls**: Sync operations that should be async
- **Algorithm Efficiency**: O(n²) or worse where O(n) possible
- **Caching**: Repeated expensive operations that could be cached

### Step 6: Generate Review Report

```markdown
## Code Review: PR #[NUMBER]

**Title**: [PR Title]
**Author**: [Author]
**Files Changed**: [Count]

### Summary
[1-2 sentence summary of changes]

### Checklist Results
- [ ] Code quality
- [ ] Tests adequate
- [ ] Architecture aligned
- [ ] Security reviewed
- [ ] Performance reviewed

### Inline Comments
[File-specific comments with line numbers]

### Required Changes (Blocking)
- [ ] [Critical issue that must be fixed]

### Suggestions (Non-Blocking)
- [ ] [Nice-to-have improvement]

### Security Findings
[Any security concerns]

### Performance Findings
[Any performance concerns]
```

### Step 7: Submit Review (Optional)

```bash
# Approve
gh pr review <pr-number> --approve

# Request changes
gh pr review <pr-number> --request-changes --body "..."

# Comment only
gh pr review <pr-number> --comment --body "..."
```

## Review Verdict Guidelines

| Verdict | When to Use |
|---------|-------------|
| **Approve** | No blocking issues, suggestions only |
| **Request Changes** | Security issues, bugs, or critical problems |
| **Comment** | Need clarification, minor suggestions |

ARGUMENTS: $1 (pr-number: PR number to review), $2+ (flags)
