---
description: Non-interactive headless retrospective runner for CI/automation
argument-hint: <issue-number>
---

# Headless Retrospective Runner

**SYSTEM NOTICE:** You are running in a NON-INTERACTIVE headless environment.
You cannot ask questions or wait for user input. You must act autonomously and EXIT.

---

## The Async Protocol

### Step 1: Read Context
The prompt contains a `CONTEXT:` block with:
- `=== ISSUE #[N]: [Title] ===` - The issue number and title
- `--- DESCRIPTION ---` - The issue body
- `--- COMMENT HISTORY ---` - Previous conversation

### Step 2: Check Conversation State
Analyze the comment history to determine your action:

| State | Action |
|-------|--------|
| User provided specific direction | **Execute it**, then EXIT |
| User's last comment was a question to you | **Answer it** via `gh issue comment`, then EXIT |
| You need critical info to proceed | **Post a question** via `gh issue comment`, then EXIT |
| No blocking issues | **Generate retrospective**, then EXIT |

### Step 3: Execute or Exit
- If blocked: Post a comment with your question and EXIT immediately
- If unblocked: Generate retrospective, update all outputs, EXIT

---

## Output Rules

- **DO NOT** use conversational filler ("Sure, I can help with that!")
- **DO NOT** ask "Would you like to proceed?"
- **DO NOT** wait for user confirmation
- **ACTION:** Validate, collect metrics, analyze, write outputs, EXIT

---

## Prerequisites

**Read these before proceeding:**
- `.claude/skills/ai-statistics.md` - Metrics collection
- `.claude/skills/github-issues.md` - Issue/PR details

---

## Phase 0: Pre-Flight Checks

### 0.1: Validate PR is Merged

```bash
# Find PR associated with this issue
PR_INFO=$(gh pr list --search "[ISSUE_NUMBER]" --state merged --json number,title,url,mergedAt --jq '.[0]')
```

**If no merged PR found:** STOP, add blocked label, comment, and EXIT:
```bash
gh issue edit [ISSUE_NUMBER] --add-label "blocked"
gh issue comment [ISSUE_NUMBER] --body "$(cat <<'EOF'
## Retrospective Blocked: No Merged PR Found

Cannot generate retrospective - no merged PR found for this issue.

**Issue Status**: [OPEN/CLOSED]

**Checked for:** PRs containing "#[ISSUE_NUMBER]" in title or body

**Action Required:**
1. Complete the implementation of the feature
2. Create and merge a PR that references this issue (e.g., "Closes #[ISSUE_NUMBER]")
3. Trigger retrospective again after PR is merged
EOF
)"
```
Then **EXIT with failure** - this is a blocked state, not a success.

### 0.2: Check for Existing Retrospective

```bash
# Check if retrospective already exists in quarterly file
grep -q "## Issue #[ISSUE_NUMBER]:" .claude/retrospectives/2026-q1.md
```

**If retrospective already exists:** STOP, add blocked label, comment, and EXIT:
```bash
gh issue edit [ISSUE_NUMBER] --add-label "blocked"
gh issue comment [ISSUE_NUMBER] --body "$(cat <<'EOF'
## Retrospective Already Exists

A retrospective entry for Issue #[ISSUE_NUMBER] already exists in `.claude/retrospectives/2026-q1.md`.

**Action Required:** If you want to regenerate, manually remove the existing entry first, then trigger retrospective again.
EOF
)"
```
Then **EXIT with failure** - this is a blocked state, not a success.

### 0.3: Validate State File Exists (Warning Only)

```bash
ls .claude/state/issue-[ISSUE_NUMBER].md 2>/dev/null
```

**If state file does not exist:** Continue with warning (metrics will be less detailed).

---

## Phase 1: Collect Data

### 1.1: Get Issue Details

```bash
gh issue view [ISSUE_NUMBER] --json title,body,labels,closedAt
```

Extract:
- Title
- Acceptance criteria
- Implementation phases
- Labels (for complexity hints)

### 1.2: Get PR Details

```bash
# Get the merged PR
PR_NUMBER=$(gh pr list --search "[ISSUE_NUMBER]" --state merged --json number --jq '.[0].number')

# Get PR details
gh pr view $PR_NUMBER --json title,body,additions,deletions,changedFiles,commits,mergedAt,url
```

### 1.3: Get Commit History

```bash
# Get commits from the PR
gh pr view $PR_NUMBER --json commits --jq '.commits[].messageHeadline'
```

### 1.4: Read State File (if exists)

```bash
cat .claude/state/issue-[ISSUE_NUMBER].md 2>/dev/null
```

Extract:
- Phases completed
- Blockers encountered
- Notes
- Any existing AI statistics

### 1.5: Calculate Git Statistics

```bash
# Get the feature branch name
BRANCH_NAME=$(gh pr view $PR_NUMBER --json headRefName --jq '.headRefName')

# Files changed
gh pr view $PR_NUMBER --json changedFiles --jq '.changedFiles'

# Lines added/removed
gh pr view $PR_NUMBER --json additions,deletions --jq '"\(.additions) added, \(.deletions) removed"'

# Test files
gh pr diff $PR_NUMBER --name-only | grep -c "_test\.dart$" || echo 0

# New widgets
gh pr diff $PR_NUMBER | grep -c "^\+.*class.*extends.*Widget" || echo 0

# New providers
gh pr diff $PR_NUMBER | grep -c "^\+.*@riverpod" || echo 0
```

### 1.6: Get PR Review Comments (for insights)

```bash
gh pr view $PR_NUMBER --json comments,reviews --jq '.comments[].body, .reviews[].body'
```

---

## Phase 2: Analyze & Generate Insights

### 2.1: Determine Complexity Score

Based on:
- Lines changed (< 500 = 3-4, 500-1500 = 5-6, 1500-3000 = 7-8, > 3000 = 9-10)
- Number of files (< 10 = low, 10-25 = medium, > 25 = high)
- Features touched (from file paths)
- Blockers encountered (from state file)

### 2.2: Identify Specialists Used

Scan commit messages and state file for:
- `flutter-specialist` mentions
- `firebase-specialist` mentions
- `testing-specialist` mentions
- Direct implementation (no specialist)

### 2.3: Generate "What Went Well"

Analyze these sources to identify positives:
- **Commit messages**: Look for patterns like "clean", "efficient", "working"
- **State file notes**: Look for successful patterns
- **PR body**: Look for "Phases Completed" section
- **Test coverage**: If tests added, note it
- **Architecture**: If follows feature-first pattern, note it

Generate 3-5 bullet points highlighting:
- Clean architecture decisions
- Successful patterns used
- Good test coverage
- Efficient implementations
- Proper use of project conventions (Riverpod, Freezed, Material 3)

### 2.4: Generate "What Could Improve"

Analyze these sources to identify improvements:
- **State file blockers**: What caused delays?
- **PR comments/reviews**: What feedback was given?
- **Commit history**: Multiple fix commits indicate issues
- **Test coverage**: Missing tests?
- **PR iterations**: Many commits = complex debugging

Generate 2-4 bullet points highlighting:
- Missing test coverage
- Patterns that caused rework
- Areas needing documentation
- Technical debt introduced

### 2.5: Extract Patterns Learned

From state file notes and commit messages, identify:
- New patterns discovered
- Workarounds implemented
- Project-specific learnings

Format: `**[Pattern Name]**: [Description]`

### 2.6: Calculate Time Estimation

Use rates from `.claude/skills/ai-statistics.md`:

| Category | Pattern | LOC/hour |
|----------|---------|----------|
| Widget Code | presentation/, *_widget.dart | 15 |
| Provider/State | @riverpod, controllers/ | 10 |
| Test Code | *_test.dart | 20 |
| Models (freezed) | @freezed, domain/ | 40 |
| Config/Routes | router.dart, config/ | 50 |
| Firebase Integration | firebase/, data/ | 12 |

Calculate:
1. Get lines per category from PR diff
2. Apply rates
3. Sum for estimated manual hours
4. Estimate AI-assisted time (typically 3-8 hours based on complexity)
5. Calculate savings percentage

---

## Phase 3: Write Outputs

### 3.1: Append to Quarterly Retrospective File

Append to `.claude/retrospectives/2026-q1.md`:

```markdown
---

## Issue #[ISSUE_NUMBER]: [Title]

**Completed**: [DATE from PR mergedAt]
**PR**: [#PR_NUMBER](PR_URL)
**Complexity**: [SCORE]/10
**Specialists Used**: [list or "None (direct implementation)"]

### What Went Well
- [Generated point 1]
- [Generated point 2]
- [Generated point 3]

### What Could Improve
- [Generated point 1]
- [Generated point 2]

### Patterns Learned
- **[Pattern 1]**: [Description]
- **[Pattern 2]**: [Description]

### Files Created
| Type | File | Purpose |
|------|------|---------|
| [Type] | `path/to/file` | [Purpose] |

### AI Statistics
- **Files Changed**: [N]
- **Files Added**: [N]
- **Lines Added**: [N]
- **Lines Removed**: [N]
- **Net Lines**: [+/- N]
- **Test Files**: [N]
- **Test Cases Added**: [N]

### Calculation Breakdown
| Category | Lines | Rate (LOC/hr) | Est. Hours |
|----------|-------|---------------|------------|
| Widget Code | [N] | 15 | [N/15] |
| Provider/State | [N] | 10 | [N/10] |
| Test Code | [N] | 20 | [N/20] |
| Models (freezed) | [N] | 40 | [N/40] |
| Firebase Integration | [N] | 12 | [N/12] |
| Config/Routes | [N] | 50 | [N/50] |
| **Total** | **[N]** | - | **[SUM]** |

- **Estimated Manual Dev Time**: [SUM] hours
- **Actual AI-Assisted Time**: ~[N] hours
- **Time Savings**: [DIFF] hours ([PERCENT]%)

### Action Items
- [ ] [Generated action 1]
- [ ] [Generated action 2]

---
```

### 3.2: Update Cumulative Stats JSON

Read `.claude/retrospectives/cumulative-stats.json`, update, and write back:

```bash
# Read current stats
cat .claude/retrospectives/cumulative-stats.json
```

Update:
- `lastUpdated`: Today's date
- `totalFeatures`: Increment by 1
- `totals.filesChanged`: Add this PR's count
- `totals.filesAdded`: Add this PR's count
- `totals.linesAdded`: Add this PR's count
- `totals.linesRemoved`: Add this PR's count
- `totals.testFilesAdded`: Add this PR's count
- `totals.testCasesAdded`: Add this PR's count
- `totals.estimatedHoursSaved`: Add this feature's savings
- `quarterlyBreakdown.2026-q1`: Update counts
- `features`: Append new feature object

### 3.3: Post Issue Comment

```bash
gh issue comment [ISSUE_NUMBER] --body "$(cat <<'EOF'
## Retrospective Complete

I have generated the retrospective for this feature.

### Summary
- **Complexity**: [SCORE]/10
- **Files Changed**: [N]
- **Lines Added**: [N]
- **Time Savings**: [HOURS] hours ([PERCENT]%)

### Key Learnings
- [Top 2-3 patterns learned]

### Outputs Updated
- `.claude/retrospectives/2026-q1.md` - Entry appended
- `.claude/retrospectives/cumulative-stats.json` - Totals updated

### Cumulative Statistics (All Time)
- **Total Features**: [N]
- **Total Lines Added**: [N]
- **Total Hours Saved**: [N] hours
EOF
)"
```

### 3.4: Commit and Create PR

```bash
# Rename branch to include "retrospective" (enables pre-commit hook validation)
# This ensures the hook blocks any non-docs changes
CURRENT_BRANCH=$(git branch --show-current)
RETRO_BRANCH="claude-ops/issue-[ISSUE_NUMBER]-retrospective"
if [ "$CURRENT_BRANCH" != "$RETRO_BRANCH" ]; then
    git branch -m "$RETRO_BRANCH"
fi

# Stage only retrospective files (pre-commit hook will block if other files staged)
git add .claude/retrospectives/

# Commit with retrospective message
git commit -m "$(cat <<'EOF'
docs: Add retrospective for Issue #[ISSUE_NUMBER]

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"

# Push the branch
git push -u origin HEAD
```

### 3.5: Create PR with Auto-Merge

```bash
# Create PR targeting the default branch
PR_URL=$(gh pr create \
  --title "docs: Retrospective for Issue #[ISSUE_NUMBER]" \
  --body "$(cat <<'EOF'
## Retrospective Documentation

This PR adds the retrospective analysis for Issue #[ISSUE_NUMBER].

### Changes
- `.claude/retrospectives/2026-q1.md` - New retrospective entry
- `.claude/retrospectives/cumulative-stats.json` - Updated totals

### Safety
- ✅ Only modifies `.claude/retrospectives/` (enforced by pre-commit hook)
- ✅ No code changes
- ✅ Auto-generated documentation

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)")

echo "Created PR: $PR_URL"

# Enable auto-merge (will merge when checks pass)
gh pr merge --auto --squash

echo "Auto-merge enabled - PR will merge when checks pass"
```

**Note:** The pre-commit hook validates that retrospective branches can ONLY modify `.claude/retrospectives/` files. Any attempt to modify code will be blocked.

---

## Phase 4: EXIT

**EXIT immediately.** Do not wait for response.

---

## Error Handling Reference

| Error Type | Action |
|------------|--------|
| No merged PR found | Add `blocked` label, comment, EXIT with failure |
| Retrospective already exists | Add `blocked` label, comment, EXIT with failure |
| State file missing | Continue with warning (metrics less detailed) |
| Git push fails | Retry once, then add `blocked` label, comment and EXIT |
| PR creation fails | Add `blocked` label, comment with error, EXIT with failure |
| Auto-merge enable fails | Log warning, continue (PR can be merged manually) |
| Pre-commit hook blocks | Fix staged files, only stage .claude/retrospectives/ |
| JSON parse error | Use safe defaults, continue |

### Error Comment Template

```bash
gh issue edit [ISSUE_NUMBER] --add-label "blocked"
gh issue comment [ISSUE_NUMBER] --body "$(cat <<'EOF'
## Retrospective Failed: [Error Type]

Retrospective generation stopped.

### Error Details
```
[error output]
```

### What Was Attempted
- [ ] PR validation - [PASS/FAIL]
- [ ] Data collection - [PASS/FAIL]
- [ ] Analysis generation - [PASS/FAIL]
- [ ] File outputs - [PASS/FAIL]

### Suggested Next Steps
1. [Specific suggestion]
2. Trigger retrospective again after fixing
EOF
)"
```
Then **EXIT with failure** - this is a blocked state, not a success.

---

## Checklist Before Exit

- [ ] Validated merged PR exists for this issue
- [ ] Checked retrospective doesn't already exist
- [ ] Collected issue details
- [ ] Collected PR statistics (files, lines, commits)
- [ ] Read state file (if exists)
- [ ] Generated complexity score
- [ ] Generated "What Went Well" (3-5 points)
- [ ] Generated "What Could Improve" (2-4 points)
- [ ] Generated "Patterns Learned"
- [ ] Calculated time estimation
- [ ] Appended entry to `.claude/retrospectives/2026-q1.md`
- [ ] Updated `.claude/retrospectives/cumulative-stats.json`
- [ ] Posted summary comment on issue
- [ ] Committed changes (only .claude/retrospectives/ files)
- [ ] Pushed branch to origin
- [ ] Created PR with descriptive title
- [ ] Enabled auto-merge on PR
- [ ] **EXIT**

---

ARGUMENTS: $1 (issue-number: GitHub issue number of the completed feature)
