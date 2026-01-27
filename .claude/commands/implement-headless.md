---
description: Non-interactive headless implementation runner for CI/automation
argument-hint: <issue-number>
---

# Headless Implementation Runner

**SYSTEM NOTICE:** You are running in a NON-INTERACTIVE headless environment.
You cannot ask questions or wait for user input. You must act autonomously and EXIT.

---

## The Async Protocol

### Step 1: Read Context
The prompt contains a `CONTEXT:` block with:
- `=== ISSUE #[N]: [Title] ===` - The issue number and title
- `--- DESCRIPTION ---` - The issue body (this is your implementation plan)
- `--- COMMENT HISTORY ---` - Previous conversation and user overrides

### Step 2: Check Conversation State
Analyze the comment history to determine your action:

| State | Action |
|-------|--------|
| User provided specific direction | **Execute it**, then EXIT |
| User's last comment was a question to you | **Answer it** via `gh issue comment`, then EXIT |
| You need critical info to proceed | **Post a question** via `gh issue comment`, then EXIT |
| No blocking issues | **Implement the feature**, then EXIT |

### Step 3: Execute or Exit
- If blocked: Post a comment with your question and EXIT immediately
- If unblocked: Implement, create PR, update issue, EXIT

---

## Output Rules

- **DO NOT** use conversational filler ("Sure, I can help with that!")
- **DO NOT** ask "Would you like to proceed?"
- **DO NOT** wait for user confirmation
- **ACTION:** Validate, implement, test, commit, push, PR, EXIT

---

## Decision Documentation

As you implement, document your key technical decisions using this EXACT format (the server parses this):

```
<<<DECISION>>>
ACTION: [Specific technical choice - be precise about classes/patterns/libraries used]
REASONING: [WHY this approach - what problem does it solve, what constraints did you consider]
ALTERNATIVES: [What else you considered and why you rejected it, or "None considered"]
CATEGORY: [architecture|library|pattern|storage|api|testing|ui|performance|other]
<<<END_DECISION>>>
```

### Example 1 - Widget Choice:
```
<<<DECISION>>>
ACTION: Wrapped Kanban board with RefreshIndicator + CustomScrollView using SliverFillRemaining
REASONING: Need pull-to-refresh without breaking horizontal PageView swipe navigation. RefreshIndicator requires a scrollable child, but wrapping PageView directly would intercept horizontal gestures. CustomScrollView with SliverFillRemaining preserves the PageView while enabling vertical overscroll detection.
ALTERNATIVES: Considered SmartRefresher package (rejected - adds dependency for simple feature); Considered GestureDetector with manual refresh logic (rejected - poor UX, no native pull animation)
CATEGORY: ui
<<<END_DECISION>>>
```

### Example 2 - State Management:
```
<<<DECISION>>>
ACTION: Added decisions field to Job model and IssueBoardProvider
REASONING: Decisions are job-specific data that needs to persist across app sessions and be accessible from multiple screens. Following existing pattern where Job contains all job metadata.
ALTERNATIVES: Considered separate DecisionsProvider (rejected - would duplicate job lookups and complicate state sync)
CATEGORY: architecture
<<<END_DECISION>>>
```

### When to Document Decisions:
- Choosing between libraries/packages
- Architectural patterns (where to put code, how to structure)
- Widget/component selection
- Performance trade-offs
- API design choices
- Anything where you considered multiple approaches

### Guidelines:
- **Be specific:** "RefreshIndicator" not "a refresh widget"
- **Explain the WHY:** constraints, trade-offs, requirements that drove the choice
- **Mention rejected alternatives** when relevant
- **Aim for 3-6 decisions** per implementation
- **Skip trivial decisions** (variable naming, formatting)

---

## Prerequisites

**Read these before proceeding:**
- `.claude/patterns.md` - Known pitfalls and patterns (if exists)
- `.claude/commands/implement.md` - Implementation workflow
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
## Implementation Already In Progress

Another implementation run is currently active for this issue.

**Action Required:** Please wait for the current run to complete, or manually remove the `in-progress` label if the previous run failed without cleanup.
EOF
)"
```
Then **EXIT**.

### 0.2: Validate Issue Has Required Sections

Parse the issue body and verify these sections exist:
- `## Acceptance Criteria` (required)
- `## Implementation Phases` OR `## Technical Approach` (required)

**If missing required sections:** STOP, add blocked label, comment, and EXIT:
```bash
gh issue edit [ISSUE_NUMBER] --add-label "blocked"
gh issue comment [ISSUE_NUMBER] --body "$(cat <<'EOF'
## Issue Not Ready for Implementation

This issue is missing required sections for implementation:

- [ ] `## Acceptance Criteria` - Found: [YES/NO]
- [ ] `## Implementation Phases` or `## Technical Approach` - Found: [YES/NO]

**Action Required:** Please run `/plan-headless [ISSUE_NUMBER]` first to create a complete implementation plan.
EOF
)"
```
Then **EXIT with failure** - this is a blocked state, not a success.

### 0.3: Validate Planning Artifacts Exist

Check for mockups and architecture documentation:
```bash
ls docs/mockups/issue-[ISSUE_NUMBER]/ 2>/dev/null
cat docs/mockups/issue-[ISSUE_NUMBER]/ARCHITECTURE.md 2>/dev/null
```

**If mockup directory does not exist:** STOP, add blocked label, comment, and EXIT:
```bash
gh issue edit [ISSUE_NUMBER] --add-label "blocked"
gh issue comment [ISSUE_NUMBER] --body "$(cat <<'EOF'
## Planning Artifacts Missing

No mockups or architecture documentation found for this issue.

**Expected location:** `docs/mockups/issue-[ISSUE_NUMBER]/`

The issue description references mockups that do not exist in the repository.

**Action Required:** Please run `/plan-headless [ISSUE_NUMBER]` first to create:
- `index.html` - Mobile mockup (430px)
- `web.html` - Desktop mockup (1440px)
- `ARCHITECTURE.md` - Technical documentation
EOF
)"
```
Then **EXIT with failure** - this is a blocked state, not a success.

### 0.4: Add In-Progress Label

```bash
gh issue edit [ISSUE_NUMBER] --add-label "in-progress"
```

---

## Phase 1: Git Safety & Branch Setup

### 1.1: Check Current State

```bash
git status --porcelain
git branch --show-current
```

### 1.2: Generate Branch Name

Create a slug from the issue title:
1. Get issue title: `gh issue view [ISSUE_NUMBER] --json title --jq '.title'`
2. Convert to kebab-case (lowercase, replace spaces with hyphens, remove special chars)
3. Truncate to 30 characters
4. Format: `feature/issue-[ISSUE_NUMBER]-[slug]`

**Example:** Issue #123 "Add Dark Mode Toggle" → `feature/issue-123-add-dark-mode-toggle`

### 1.3: Branch Logic

**Decision Tree:**

```
Is current branch main/master?
├─ YES → Create new branch: git checkout -b feature/issue-[ISSUE_NUMBER]-[slug]
└─ NO → Is working tree dirty (uncommitted changes)?
        ├─ YES → STOP (fail safe - don't overwrite manual work)
        └─ NO → Does feature branch exist?
                ├─ YES → Check it out: git checkout feature/issue-[ISSUE_NUMBER]-[slug]
                └─ NO → Create it: git checkout -b feature/issue-[ISSUE_NUMBER]-[slug]
```

**If dirty working tree detected:** STOP and comment:
```bash
gh issue comment [ISSUE_NUMBER] --body "$(cat <<'EOF'
## Implementation Blocked: Dirty Working Tree

Found uncommitted changes on branch `[BRANCH_NAME]`. Cannot proceed without risking overwrite of manual work.

**Files with uncommitted changes:**
```
[git status output here]
```

**Action Required:** Please commit or stash these changes manually, then trigger implementation again.
EOF
)"
gh issue edit [ISSUE_NUMBER] --add-label "blocked" --remove-label "in-progress"
```
Then **EXIT**.

### 1.4: Sync with Remote

```bash
git pull origin feature/issue-[ISSUE_NUMBER]-[slug] --rebase || true
```

---

## Phase 2: Resume Detection

### 2.1: Check State File

```bash
# Check if state file exists
ls .claude/state/issue-[ISSUE_NUMBER].md
```

### 2.2: Check Git History

```bash
# Get commits on this branch for this issue
git log --oneline main..HEAD --grep="feat(#[ISSUE_NUMBER])"
```

### 2.3: Determine Starting Point

**Rule: Git is King**

| State File Says | Git History Shows | Action |
|-----------------|-------------------|--------|
| Phase 2 complete | Phase 1, Phase 2 commits exist | Resume at Phase 3 |
| Phase 3 complete | Only Phase 1 commit exists | Resume at Phase 2 (state file lied) |
| No state file | Phase 1, Phase 2 commits exist | Resume at Phase 3 (create state file) |
| No state file | No commits | Start from Phase 1 |

### 2.4: Create/Update State File

If no state file exists:
```bash
cp .claude/state/TEMPLATE.md .claude/state/issue-[ISSUE_NUMBER].md
```

---

## Phase 3: Create Execution Plan

### 3.1: Read Patterns Library

```bash
cat .claude/patterns.md 2>/dev/null || echo "No patterns file found"
```

**Scan for patterns related to your feature's domain** (navigation, Firebase, Riverpod, layout, UX) and incorporate them into your implementation approach.

### 3.2: Parse Implementation Phases

Extract phases from issue body. Expected format:
```markdown
## Implementation Phases
### Phase 1: [Name]
- [ ] Task 1
- [ ] Task 2

### Phase 2: [Name]
- [ ] Task 1
```

### 3.3: Load Planning Artifacts

```bash
# Read architecture for technical approach
cat docs/mockups/issue-[ISSUE_NUMBER]/ARCHITECTURE.md

# Note mockup files for UI reference
ls docs/mockups/issue-[ISSUE_NUMBER]/*.html
```

**Headless Override:** Do NOT wait for user approval. You have pre-approval. Proceed.

---

## Phase 4: Implementation Loop

For each phase that is NOT already complete:

### 4.1: Deploy Appropriate Specialists

Based on the phase requirements, deploy with Task tool:

**For UI Features:**
```
Use Task tool with flutter-specialist:
"Implement [feature] following:
- **UI mockups in docs/mockups/issue-[N]/*.html** (MATCH THESE EXACTLY)
- Architecture doc in docs/mockups/issue-[N]/ARCHITECTURE.md
- Material 3 design system with seed color Colors.blueGrey
- Use Gap(Insets.*) for spacing, never SizedBox
- Use Theme.of(context).colorScheme.* for colors, never hardcoded
- Use @riverpod annotations for state management
- Use @freezed for data models

The mockups are the source of truth for visual design."
```

**For Backend/Firebase Features:**
```
Use Task tool with firebase-specialist:
"Implement [feature] following:
- **Architecture doc in docs/mockups/issue-[N]/ARCHITECTURE.md**
- Data models and API design from architecture
- Firestore security rules as specified
- Use @freezed for all data models
- Use @riverpod for providers"
```

**For Tests:**
```
Use Task tool with testing-specialist:
"Create tests for [feature] after implementation.
- Widget tests for UI components
- Unit tests for business logic
- Provider tests for state management
- Follow existing test patterns in test/ directory"
```

**Headless Override:** Specialists should work autonomously. Suppress interactive prompts.

### 4.2: Run Code Generation

```bash
dart run build_runner build --delete-conflicting-outputs
```

**If code generation fails:**
- Check for syntax errors in `@freezed` or `@riverpod` annotated classes
- Verify imports are correct
- Attempt to fix (1-2 retries)
- If still failing: STOP and post detailed error comment

### 4.3: Run Flutter Analyze

```bash
flutter analyze
```

**If analysis fails:**
- Attempt to fix the issues (1-2 retries)
- If still failing: STOP and post detailed error comment

### 4.4: Run Design System Audit

Check for coding standard violations:

```bash
# Check for hardcoded colors (should use Theme.of(context).colorScheme.*)
grep -rn "Colors\." lib/ --include="*.dart" | grep -v "Colors.blueGrey" | head -20

# Check for SizedBox spacing (should use Gap)
grep -rn "SizedBox(" lib/ --include="*.dart" | grep -E "height:|width:" | head -20
```

**If violations found in files changed by this issue:**
- Fix the violations (iterate until clean)
- Only fix violations in files changed by this issue
- Non-blocking if violations are in unrelated files

### 4.5: Commit Phase Work

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(#[ISSUE_NUMBER]): Phase [N] - [phase_name]

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

### 4.6: Push to Remote (Save Point)

```bash
git push -u origin HEAD
```

**Critical:** Push after EVERY phase. If timeout occurs, work is preserved on remote.

### 4.7: Update State File

Update `.claude/state/issue-[ISSUE_NUMBER].md` with:
- Current phase: completed
- Next phase: [N+1]
- Files modified this phase
- Timestamp

### 4.8: Repeat for Next Phase

---

## Phase 5: Quality Gates

After all implementation phases complete:

### 5.1: Get Dependencies

```bash
flutter pub get
```

### 5.2: Run Code Generation (Final)

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 5.3: Flutter Analyze

```bash
flutter analyze
```

### 5.4: Run Tests

```bash
flutter test
```

**If tests fail:** STOP and post detailed error comment:

```bash
gh issue comment [ISSUE_NUMBER] --body "$(cat <<'EOF'
## Implementation Failed: Tests Not Passing

Implementation completed but tests are failing. **No PR has been created.**

### Error Output (last 50 lines)
```
[truncated test output here]
```

### What Was Completed
- Phase 1: [Name] - Completed
- Phase 2: [Name] - Completed
- Phase 3: [Name] - Completed
- Quality Gates: FAILED at `flutter test`

### Suggested Next Steps
1. Review the test failures above
2. Check branch `feature/issue-[ISSUE_NUMBER]-[slug]` for the implementation
3. Fix failing tests manually or provide guidance in a comment

### Files Changed
- `lib/...` (N files)
- `test/...` (N files)
EOF
)"
gh issue edit [ISSUE_NUMBER] --add-label "blocked" --remove-label "in-progress"
```
Then **EXIT**.

### 5.5: Design System Compliance (Final)

Check for hardcoded colors and SizedBox usage in changed files and fix any remaining violations.

---

## Phase 6: Create/Update Pull Request

### 6.1: Check for Existing PR

```bash
gh pr list --head feature/issue-[ISSUE_NUMBER]-[slug] --json number,url --jq '.[0]'
```

### 6.2: Create or Update PR

**If PR exists:** Just push (already done in Phase 4.6). PR auto-updates.

**If no PR exists:** Create draft PR with rich description:

```bash
gh pr create --draft --title "feat(#[ISSUE_NUMBER]): [Issue Title]" --body "$(cat <<'EOF'
## Summary
[Brief description from issue]

## Acceptance Criteria
[Copy from issue body - these will be verified by reviewer]

## Technical Approach
[Copy from issue body]

## Changes Made
### Files Modified
- `path/to/file1.dart` - [description]
- `path/to/file2.dart` - [description]

### Tests Added/Modified
- `test/path/to/test.dart` - [description]

## Phases Completed
- [x] Phase 1: [Name]
- [x] Phase 2: [Name]
- [x] Phase 3: [Name]

## Quality Gates
- [x] `flutter pub get` - Passed
- [x] `dart run build_runner build` - Passed
- [x] `flutter analyze` - Passed
- [x] `flutter test` - Passed

## Mockups Reference
See: `docs/mockups/issue-[ISSUE_NUMBER]/`

---
Closes #[ISSUE_NUMBER]

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### 6.3: Get PR Number

```bash
PR_NUMBER=$(gh pr list --head feature/issue-[ISSUE_NUMBER]-[slug] --json number --jq '.[0].number')
PR_URL=$(gh pr list --head feature/issue-[ISSUE_NUMBER]-[slug] --json url --jq '.[0].url')
```

---

## Phase 7: Update Issue

### 7.1: Check Off Acceptance Criteria

Update the issue body, changing:
- `- [ ]` to `- [x]` for each completed acceptance criterion

```bash
gh issue edit [ISSUE_NUMBER] --body "[updated body with checked criteria]"
```

### 7.2: Update Labels

```bash
gh issue edit [ISSUE_NUMBER] --add-label "ready-for-review" --remove-label "in-progress"
```

### 7.3: Post Success Comment

```bash
gh issue comment [ISSUE_NUMBER] --body "$(cat <<'EOF'
## Implementation Complete

I have implemented the changes and opened PR #[PR_NUMBER] for review.

### Summary
- **Phases Completed:** [N] of [N]
- **Files Changed:** [count]
- **All Quality Gates Passed**

### Pull Request
[PR_URL]

### Changes Overview
- [Brief list of main changes]

### Next Steps
Please review the draft PR and mark it ready for review when satisfied.
EOF
)"
```

---

## Phase 8: EXIT

**EXIT immediately.** Do not wait for response.

---

## Error Handling Reference

| Error Type | Retries | Action on Failure |
|------------|---------|-------------------|
| Code generation fails | 2 | Stop, comment with error, add `blocked` label |
| `flutter analyze` fails | 2 | Fix issues, retry |
| `flutter test` fails | 0 | Stop, comment with error, add `blocked` label |
| Design audit fails | 2 | Fix violations in changed files, retry |
| Git push fails | 2 | Stop, comment with error, add `blocked` label |
| Network/API errors | 2 | Retry, then stop and comment |

### Error Comment Template

```bash
gh issue comment [ISSUE_NUMBER] --body "$(cat <<'EOF'
## Implementation Failed: [Error Type]

Implementation stopped at **Phase [N]: [Name]**.

### Error Output (last 50 lines)
```
[truncated error output]
```

### What Was Completed
- [x] Phase 1: [Name]
- [x] Phase 2: [Name]
- [ ] Phase 3: [Name] - FAILED HERE

### Branch State
All completed work has been committed and pushed to `feature/issue-[ISSUE_NUMBER]-[slug]`.

### Suggested Next Steps
1. [Specific suggestion based on error]
2. [Additional guidance]

### To Resume
Fix the issue and trigger implementation again. The agent will resume from Phase [N].
EOF
)"
gh issue edit [ISSUE_NUMBER] --add-label "blocked" --remove-label "in-progress"
```

---

## Checklist Before Exit

- [ ] Checked for `in-progress` label (concurrent run protection)
- [ ] Validated required issue sections exist
- [ ] Validated planning artifacts exist (mockups, ARCHITECTURE.md)
- [ ] Read `.claude/patterns.md` (if exists)
- [ ] Added `in-progress` label
- [ ] Verified git branch state (not dirty)
- [ ] Created or checked out feature branch
- [ ] Detected resume point (state file + git history)
- [ ] Deployed specialists as needed
- [ ] Ran code generation after each phase
- [ ] Committed after each phase with format: `feat(#N): Phase X - name`
- [ ] Pushed after each phase (save points)
- [ ] Updated state file after each phase
- [ ] Ran final quality gates (pub get + build_runner + analyze + test)
- [ ] Created/updated draft PR with rich description
- [ ] Checked off acceptance criteria in issue body
- [ ] Updated labels (`in-progress` → `ready-for-review` or `blocked`)
- [ ] Posted summary comment on issue
- [ ] **EXIT**

---

ARGUMENTS: $1 (issue-number: GitHub issue number from CONTEXT block)
