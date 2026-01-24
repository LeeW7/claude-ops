---
description: Non-interactive headless revision runner for processing feedback
argument-hint: <issue-number>
---

# Headless Revision Runner

**SYSTEM NOTICE:** You are running in a NON-INTERACTIVE headless environment.
You cannot ask questions or wait for user input. You must act autonomously and EXIT.

---

## Purpose

This command processes user feedback on an existing implementation and makes the requested changes.
It differs from `implement-headless` in that:
- It uses the existing feature branch (no new branch creation)
- It reads feedback from the most recent `## Revision Requested` comment
- It pushes fixes to the same PR
- It posts a completion comment summarizing changes made

---

## The Async Protocol

### Step 1: Read Context
The prompt contains a `CONTEXT:` block with:
- `=== ISSUE #[N]: [Title] ===` - The issue number and title
- `--- DESCRIPTION ---` - The issue body (original implementation plan)
- `--- COMMENT HISTORY ---` - Previous conversation including revision feedback

### Step 2: Parse Feedback
Find the MOST RECENT comment starting with `## Revision Requested`.
This contains:
- Text feedback describing what needs to change
- Optional screenshot showing the problem

### Step 3: Execute Revision
- Check out the existing feature branch
- Make the requested changes
- Run quality gates
- Push to the same branch (auto-updates PR)
- Post completion comment

---

## Output Rules

- **DO NOT** use conversational filler ("Sure, I can help with that!")
- **DO NOT** ask "Would you like to proceed?"
- **DO NOT** wait for user confirmation
- **ACTION:** Parse feedback, fix issues, test, commit, push, EXIT

---

## Prerequisites

**Read these before proceeding:**
- `.claude/patterns.md` - Known pitfalls and patterns (if exists)
- `.claude/skills/quality-gates.md` - Quality gates

---

## Phase 0: Pre-Flight Checks

### 0.1: Concurrent Run Protection

```bash
gh issue view [ISSUE_NUMBER] --json labels --jq '.labels[].name' | grep -q "in-progress"
```

**If `in-progress` label exists:** STOP immediately and comment:
```bash
gh issue comment [ISSUE_NUMBER] --body "$(cat <<'EOF'
## Revision Already In Progress

Another revision or implementation run is currently active for this issue.

**Action Required:** Please wait for the current run to complete, or manually remove the `in-progress` label if the previous run failed without cleanup.
EOF
)"
```
Then **EXIT**.

### 0.2: Find Open PR

```bash
gh pr list --repo [REPO] --json number,headRefName,url | jq '.[] | select(.headRefName | contains("issue-[ISSUE_NUMBER]"))'
```

**If no PR exists:** STOP and comment:
```bash
gh issue comment [ISSUE_NUMBER] --body "$(cat <<'EOF'
## Revision Failed: No PR Found

Cannot process revision feedback - no open pull request found for this issue.

**Expected:** A PR with branch pattern `feature/issue-[ISSUE_NUMBER]-*`

**Action Required:** Please ensure implementation has been completed first.
EOF
)"
```
Then **EXIT**.

### 0.3: Parse Revision Feedback

Read the issue comments and find the MOST RECENT `## Revision Requested` section:

```bash
gh issue view [ISSUE_NUMBER] --json comments --jq '.comments | reverse | .[] | select(.body | startswith("## Revision Requested")) | .body' | head -1
```

**If no feedback found:** STOP and comment:
```bash
gh issue comment [ISSUE_NUMBER] --body "$(cat <<'EOF'
## Revision Failed: No Feedback Found

Cannot process revision - no `## Revision Requested` comment found.

**Action Required:** Please submit feedback via the app or add a comment starting with `## Revision Requested`.
EOF
)"
```
Then **EXIT**.

### 0.4: Add In-Progress Label

```bash
gh issue edit [ISSUE_NUMBER] --add-label "in-progress"
```

---

## Phase 1: Branch Setup

### 1.1: Get Branch Name from PR

```bash
BRANCH=$(gh pr list --json number,headRefName | jq -r '.[] | select(.headRefName | contains("issue-[ISSUE_NUMBER]")) | .headRefName')
```

### 1.2: Checkout and Sync

```bash
git fetch origin
git checkout $BRANCH
git pull origin $BRANCH --rebase
```

**If checkout fails or conflicts:** STOP and comment with the error.

---

## Phase 2: Understand the Feedback

### 2.1: Analyze Feedback Content

Parse the revision feedback to understand:
1. **What's wrong** - The problem being reported
2. **Expected behavior** - What should happen instead
3. **Screenshot analysis** - If provided, analyze what's visible

### 2.2: Locate Relevant Code

Based on the feedback, identify:
- Which files need modification
- Which components/functions are involved
- Related test files

### 2.3: Read Patterns Library

```bash
cat .claude/patterns.md 2>/dev/null || echo "No patterns file found"
```

Check for patterns related to the feedback domain.

---

## Phase 3: Implement Fixes

### 3.1: Make Changes

Based on the feedback analysis:
- Fix the identified issues
- Follow existing code patterns
- Maintain consistency with the rest of the implementation

### 3.2: Run Code Generation (if needed)

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 3.3: Run Quality Gates

```bash
flutter pub get
flutter analyze
flutter test
```

**If tests fail:** Attempt to fix (1-2 retries). If still failing, STOP and comment with details.

---

## Phase 4: Commit and Push

### 4.1: Commit Changes

```bash
git add -A
git commit -m "$(cat <<'EOF'
fix(#[ISSUE_NUMBER]): Address revision feedback

- [Summary of changes made]

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

### 4.2: Push to Branch

```bash
git push origin HEAD
```

This automatically updates the existing PR.

---

## Phase 5: Update Issue

### 5.1: Remove In-Progress Label

```bash
gh issue edit [ISSUE_NUMBER] --remove-label "in-progress"
```

### 5.2: Post Completion Comment

```bash
gh issue comment [ISSUE_NUMBER] --body "$(cat <<'EOF'
## Revision Complete

I have addressed the feedback and pushed the changes to the PR.

### Feedback Addressed
> [Quote the original feedback]

### Changes Made
- [List of specific changes]

### Files Modified
- `path/to/file1.dart` - [description]
- `path/to/file2.dart` - [description]

### Quality Gates
- [x] `flutter analyze` - Passed
- [x] `flutter test` - Passed

The PR has been automatically updated. Please review the changes.
EOF
)"
```

---

## Phase 6: EXIT

**EXIT immediately.** Do not wait for response.

---

## Error Handling Reference

| Error Type | Retries | Action on Failure |
|------------|---------|-------------------|
| No PR found | 0 | Stop, comment with error |
| No feedback found | 0 | Stop, comment with error |
| Branch checkout fails | 0 | Stop, comment with error |
| `flutter analyze` fails | 2 | Fix issues, retry |
| `flutter test` fails | 2 | Fix issues, retry, then stop with comment |
| Git push fails | 2 | Stop, comment with error |

### Error Comment Template

```bash
gh issue comment [ISSUE_NUMBER] --body "$(cat <<'EOF'
## Revision Failed: [Error Type]

Revision stopped due to an error.

### Error Output
```
[error output]
```

### Feedback Being Addressed
> [Original feedback]

### What Was Attempted
- [Description of attempted changes]

### Suggested Next Steps
1. [Specific suggestion based on error]
2. Review the branch manually: `git checkout $BRANCH`

### To Retry
Fix the underlying issue and trigger revision again.
EOF
)"
gh issue edit [ISSUE_NUMBER] --remove-label "in-progress"
```

---

## Checklist Before Exit

- [ ] Checked for `in-progress` label (concurrent run protection)
- [ ] Verified PR exists for this issue
- [ ] Found and parsed revision feedback
- [ ] Added `in-progress` label
- [ ] Checked out existing feature branch
- [ ] Made requested changes
- [ ] Ran quality gates (analyze + test)
- [ ] Committed with descriptive message
- [ ] Pushed to branch (PR auto-updated)
- [ ] Removed `in-progress` label
- [ ] Posted completion comment
- [ ] **EXIT**

---

ARGUMENTS: $1 (issue-number: GitHub issue number from CONTEXT block)
