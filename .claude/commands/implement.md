---
description: Orchestrate feature development with session persistence and specialist deployment
---

# Implement Feature Command

Orchestrate feature development with session persistence and specialist deployment.

## Step 0: Load Required Skills (MANDATORY)

**BEFORE doing anything else, use the Read tool to load these skill files:**

```
Read .claude/skills/state-management.md
Read .claude/skills/git-workflow.md
Read .claude/skills/jira.md
Read .claude/skills/quality-gates.md
Read .claude/skills/patterns.md
```

These skills contain the specific commands, checklists, and procedures needed to complete this workflow. Do not proceed until you have read them.

## Usage

```
/implement <issue-key>
```

## Workflow

### FIRST: Check for Resume (Use state-management skill)

Use the state-management skill to check if `.claude/state/issue-$ISSUE_KEY.md` exists.

**If EXISTS**: Resume from saved state
**If NOT exists**: Start new implementation

### Check Patterns Library

**Before coding**, review patterns for pitfalls in your feature's domain:

Scan `.claude/skills/patterns.md` for patterns relevant to this feature. Pay special attention to:
- Architecture patterns (service layer structure)
- Domain-specific patterns (CRM, Kafka, etc.)
- Common pitfalls (build tooling, testing)

Incorporate relevant patterns into your implementation approach.

### Step 0: Pre-Flight (Use git-workflow skill)

Use the git-workflow skill for:
1. Verify on main branch
2. Pull latest
3. Create feature branch
4. Create state file

### Step 1: Fetch Issue (Use jira skill)

Use the jira skill to get issue details.

### Step 2: Deploy Orchestrator

Use the orchestrator agent to:
1. Analyze issue requirements
2. Check if Design Phase is needed (HAS_UI + UI changes)
3. Create execution plan
4. Get user approval

### Step 3: Execute Design Phase (If Required)

If orchestrator plan includes Phase 1.5:
1. Deploy frontend-expert specialist
2. Create mockups in `docs/mockups/[issue-key]/`
3. Present to user for approval
4. **Do NOT proceed until design approved**

### Step 4: Implementation

Execute the plan, updating state file after each phase:
- Deploy appropriate specialists based on plan
- Track progress in state file
- Commit incrementally
- **Document key decisions** (see Decision Documentation below)

### Step 5: Verify (Use quality-gates skill)

Use the quality-gates skill to run build/test/coverage.

### Step 6: Report Status

Output summary of progress.

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

### Example:
```
<<<DECISION>>>
ACTION: Wrapped Kanban board with RefreshIndicator + CustomScrollView using SliverFillRemaining
REASONING: Need pull-to-refresh without breaking horizontal PageView swipe navigation. RefreshIndicator requires a scrollable child, but wrapping PageView directly would intercept horizontal gestures.
ALTERNATIVES: SmartRefresher package (rejected - adds dependency); GestureDetector with manual refresh (rejected - poor UX)
CATEGORY: ui
<<<END_DECISION>>>
```

### When to Document:
- Choosing between libraries/packages
- Architectural patterns (where to put code, how to structure)
- Widget/component selection
- Performance trade-offs
- API design choices

**Aim for 3-6 decisions per implementation.** Skip trivial decisions (variable naming, formatting).

---

ARGUMENTS: $1 (issue-key: Issue key, e.g., INS-1234)
