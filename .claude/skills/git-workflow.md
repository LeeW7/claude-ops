---
description: Git operations for feature development branches, commits, and PRs
---

# Git Workflow Skill

Git operations for feature development.

## Configuration

- **Main Branch**: `main`
- **Branch Prefix**: `feature/`

## Branch Naming Conventions

```
feature/[ISSUE-KEY]-short-description
```

Examples:
- `feature/INS-123-add-claim-sync`
- `feature/PROJ-456-fix-auth-bug`

## Pre-Flight Checks

```bash
# 1. Verify on main branch
git branch --show-current  # Should be main

# 2. Pull latest
git pull origin main

# 3. Check for uncommitted changes
git status --porcelain
# If output is not empty, warn user about uncommitted changes

# 4. Create feature branch
git checkout -b feature/[ISSUE-KEY]-[description]
```

## Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `refactor`: Code change that neither fixes a bug nor adds a feature
- `test`: Adding or updating tests
- `docs`: Documentation only
- `chore`: Maintenance tasks

**Example:**
```
feat(claims): Add claim sync from Guidewire

Implement ClaimSyncService to process claim change events
from Guidewire and sync to Dynamics CRM.

Closes INS-123
Co-Authored-By: Claude <noreply@anthropic.com>
```

## PR Creation

```bash
gh pr create --base main --title "<title>" --body "$(cat <<'EOF'
## Summary
<bullet points>

## Jira Issue
[ISSUE-KEY](https://your-domain.atlassian.net/browse/ISSUE-KEY)

## Changes
- [list of changes]

## Testing
- [ ] Unit tests pass
- [ ] Manual testing completed

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

## When to Use This Skill

- `/implement` - Pre-flight checks, branch creation
- `/ship` - Commit and PR creation
