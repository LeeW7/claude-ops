---
description: Analyze a Jira issue or create a new one with technical specs
---

# Plan Feature Command

Analyze an existing Jira issue to create an execution plan, OR create a new issue with user stories and technical specifications.

## Step 0: Load Required Skills (MANDATORY)

**BEFORE doing anything else, use the Read tool to load these skill files:**

```
Read .claude/skills/jira.md
Read .claude/skills/patterns.md
```

These skills contain Jira MCP integration patterns and learnings from past implementations.

## Usage

```
/plan <issue-key>           # Analyze existing issue (e.g., /plan INS-123)
/plan "<description>"       # Create new issue (e.g., /plan "Add password reset")
```

## FIRST: Determine Mode

Check if the argument is an issue key (e.g., `INS-123`, `PROJ-456`) or a description:
- **Issue key pattern**: Letters, dash, numbers (e.g., `INS-123`)
- **Description**: Everything else (quoted or unquoted text)

---

## Mode A: Existing Issue (`/plan INS-123`)

### Step 1: Fetch Issue Details (Use jira skill)

Fetch the issue using MCP:
- Summary, description, acceptance criteria
- Current status and assignee
- Related issues and links

### Step 2: Check Patterns Library

Scan `.claude/skills/patterns.md` for patterns related to this feature's domain. Incorporate relevant learnings into the plan.

### Step 3: Gather Project Context

Read CLAUDE.md to understand:
- Architecture patterns
- Service layer conventions
- Testing requirements

### Step 4: Create Execution Plan

Analyze the issue and create a detailed execution plan:
- Break down into implementable steps
- Identify which specialists are needed
- Note any dependencies or blockers
- Estimate complexity

### Step 5: Present Plan for Approval

Output the execution plan and wait for user approval before proceeding to `/implement`.

---

## Mode B: New Feature (`/plan "description"`)

### Step 1: Search for Existing Work (Use jira skill)

Before creating a new issue, search Jira for related work:
- Use JQL to find existing issues covering this feature
- Check for duplicates or related issues
- Look for similar past implementations

### Step 2: Check Patterns Library

Scan `.claude/skills/patterns.md` for patterns related to this feature's domain. Incorporate relevant learnings into the design.

### Step 3: Gather Project Context

Read CLAUDE.md to understand:
- Architecture patterns
- Service layer conventions
- Testing requirements

### Step 4: Design the Feature

Create:
- User stories with acceptance criteria
- Technical specification
- Implementation approach

### Step 5: Create Jira Issue (Use jira skill)

Use the Jira MCP tools to create the issue with:
- Summary and description (markdown format)
- User stories with acceptance criteria
- Technical specification

### Step 6: Report Created Issue

Output issue key and URL.

---

ARGUMENTS: $1 (issue-key OR feature-description)
