---
description: Finalize implementation with quality gates, security/perf review, and PR creation
---

# Ship Feature Command

Finalize implementation by running quality gates, security/performance checks, creating commits, and creating PR.

## Step 0: Load Required Skills (MANDATORY)

**BEFORE doing anything else, use the Read tool to load these skill files:**

```
Read .claude/skills/quality-gates.md
Read .claude/skills/git-workflow.md
Read .claude/skills/ai-statistics.md
Read .claude/skills/jira.md
```

These skills contain project-specific commands and configurations needed for this workflow.

## Usage

```
/ship <issue-key> [commit-type] [--skip-security] [--skip-perf]
```

**Flags:**
- `--skip-security`: Skip security review (not recommended)
- `--skip-perf`: Skip performance review

## Workflow

### Step 1: Verify Branch

Ensure on correct feature branch for the issue (per git-workflow skill).

### Step 2: Run Quality Gates

Run build, test, coverage checks using commands from quality-gates skill. **Block if any fail.**

### Step 3: Security Review

Unless `--skip-security` flag, perform security review using OWASP Top 10:

- **Injection**: Check for SQL injection, command injection, LDAP injection
- **Broken Auth**: Review session management, password handling
- **Sensitive Data**: Scan for hardcoded secrets, credentials in logs
- **XXE**: Check XML parsing configuration
- **Access Control**: Verify authorization on endpoints
- **Security Misconfiguration**: Check error handling, headers
- **XSS**: Review output encoding, Content Security Policy
- **Insecure Deserialization**: Check for untrusted data handling
- **Vulnerable Dependencies**: Run `npm audit` / `mvn dependency-check:check` / `pip-audit`
- **Logging**: Ensure security events logged, no sensitive data in logs

**Block ship if critical issues found.**

### Step 4: Performance Review

Unless `--skip-perf` flag, check for common performance issues:

- **N+1 Queries**: Look for loops with database calls
- **Missing Indexes**: Check queries against indexed fields
- **Memory Leaks**: Review object lifecycle, stream handling
- **Unbounded Collections**: Check for lists that could grow unbounded
- **Blocking Operations**: Identify sync operations that should be async
- **Caching Opportunities**: Identify repeated expensive operations

**Warn but don't block unless critical.**

### Step 5: Collect AI Statistics

Gather metrics for retrospective (per ai-statistics skill):
- Files changed/added
- Lines added/removed
- Test coverage achieved

### Step 6: Create Commit

Create conventional commit (per git-workflow skill):
- Type from argument or inferred (feat/fix/refactor)
- Scope from issue
- Description from changes
- Issue reference

### Step 7: Create PR

Create pull request (per git-workflow skill):
- Summary of changes
- Link to issue
- Test plan
- AI statistics

### Step 8: Update Issue

Update Jira issue status and add PR link (per jira skill).

### Step 9: Report Summary

Output:
- Commit hash
- PR URL
- Quality gate results
- Security/perf findings
- AI statistics

ARGUMENTS: $1 (issue-key: Issue key), $2 (commit-type: feat|fix|refactor|docs|test), $3+ (flags)
