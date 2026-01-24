---
description: Capture learnings and improve the workflow after completing a feature
---

# Retrospective Command

Capture learnings and insights after completing a feature implementation.

## Step 0: Load Required Skills (MANDATORY)

**BEFORE doing anything else, use the Read tool to load these skill files:**

```
Read .claude/skills/ai-statistics.md
Read .claude/skills/jira.md
Read .claude/skills/patterns.md
```

These skills contain project-specific metrics, Jira integration patterns, and the patterns library for graduating learnings.

## Usage

```
/retrospective <issue-key>
```

## Workflow

### Step 1: Gather Context (Use jira skill)

Fetch issue details, comments, and history.

### Step 2: Collect Statistics (Use ai-statistics skill)

Read AI statistics from state file:
- Code metrics
- Test metrics
- Time estimation vs actual

### Step 3: Analyze Implementation

Review:
- What went well
- What was challenging
- Patterns discovered
- Specialist gaps identified

### Step 4: Document Learnings

Update `.claude/retrospectives/[quarter].md` with:
- Issue summary
- Key learnings
- Pattern recommendations
- Specialist recommendations

### Step 5: Graduate Patterns

**Evaluate each "Patterns to Reuse" item** for graduation to `.claude/skills/patterns.md`:

**Graduation criteria** - Pattern is:
1. **Reusable** - Applies to future features, not one-off
2. **Actionable** - Clear do/don't guidance
3. **Validated** - Worked in practice

**If pattern qualifies**, add to appropriate section in `.claude/skills/patterns.md`:
```markdown
- **[Domain] Pattern name** - Brief actionable description
  - *Source: Issue #[ISSUE-KEY]*
```

Update the `*Last updated:*` date at the bottom of patterns.md.

### Step 6: Update Cumulative Stats

Update `.claude/retrospectives/cumulative-stats.json` with:
- Total issues completed
- Total lines written
- Total time saved
- Running averages

### Step 7: Create New Specialists (If Needed)

If patterns identified that should be codified:
- Use `/agent-factory` to create new specialist
- Document the decision

### Step 8: Report Summary

Output:
- Learnings captured
- Statistics updated
- **Patterns graduated** (list any patterns added to patterns.md, or "None - learnings were one-off")
- Any new specialists created
- Recommendations for future

ARGUMENTS: $1 (issue-key: Issue key of completed feature)
