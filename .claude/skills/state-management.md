---
description: Manage implementation state files for session persistence across conversations
---

# State Management Skill

Manage implementation state files for session persistence.

## State File Location

```
.claude/state/issue-[ISSUE_KEY].md
```

## Create State File (New Feature)

```bash
# Copy template
cp .claude/state/TEMPLATE.md .claude/state/issue-[ISSUE_KEY].md

# Update with issue details
# - Issue key
# - Title
# - Branch name
# - Started date
# - Status: in-progress
```

## Check for Existing State (Resume)

```bash
# Check if state file exists
if [ -f ".claude/state/issue-[ISSUE_KEY].md" ]; then
  echo "Resuming from existing state"
  # Read current phase and next action
else
  echo "Starting new implementation"
  # Create new state file
fi
```

When resuming:
1. Read current phase
2. Read next action
3. Check any blockers
4. Continue from where left off

## Update State Progress

After completing each phase or significant step:
1. Mark completed items with `[x]`
2. Update "Current Phase" section
3. Update "Next action"
4. Add any blockers
5. Update "Files Changed" list

## State File Phases

| Phase | Description |
|-------|-------------|
| Phase 0 | Pre-Flight (branch creation, state file) |
| Phase 1 | Planning (requirements, execution plan) |
| Phase 1.5 | Design (mockups - if HAS_UI=true) |
| Phase 2 | Analysis (components, specialists) |
| Phase 3 | Implementation (code changes) |
| Phase 4 | Testing (tests, coverage) |
| Phase 5 | Ship (commit, PR, issue update) |

## When to Use This Skill

- `/implement` - Create and update state throughout
- `/ship` - Read state for AI statistics, mark complete
- `/retrospective` - Read final state for metrics
