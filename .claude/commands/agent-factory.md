---
description: Create new specialist agents on-demand for the development workflow
---

# Agent Factory Command

Create new specialist agents when existing specialists don't cover a domain.

## Usage

```
/agent-factory <specialist-name> [--from-retro <issue-key>]
```

**Arguments:**
- `specialist-name`: Name for the new specialist (e.g., `email-specialist`)
- `--from-retro`: Create based on learnings from a specific retrospective

## When to Use

Create when:
- Implementation requires expertise not covered
- Retrospective identified recurring patterns
- New technology introduced to project

Do NOT create when:
- One-off task unlikely to recur
- Existing specialist can handle
- Knowledge is too generic

## Workflow

### Step 1: Validate Need

Check existing specialists:
```bash
# List existing specialists
ls .claude/agents/
```

Confirm no overlap with existing specialists.

### Step 2: Define Scope

Gather from user:
- Expertise areas
- When to use this specialist
- Related specialists

### Step 3: Gather Context

Read from project:
- CLAUDE.md patterns
- Existing implementations
- Related code examples

### Step 4: Generate Specialist (Use agent-factory agent)

Deploy agent-factory agent to create specialist file with:
- YAML frontmatter
- Expertise areas
- Patterns and conventions
- Quality checklist
- Testing guidelines
- Escalation rules

### Step 5: Create Specialist File

Write to `.claude/agents/[name].md`

### Step 6: Verify Registration

```bash
# Restart may be needed for agent discovery
# Then verify with /agents command
```

### Step 7: Log Creation

Add to retrospectives:
```markdown
### Specialist Created: [name]
- **Reason**: [why created]
- **Expertise**: [areas]
- **Trigger**: [retrospective/new-tech/implementation-need]
```

## Specialist Quality Criteria

A good specialist should:
- Be focused on a specific domain
- Include project-specific context
- Have concrete code examples
- Define clear boundaries
- Include testing guidance
- Know when to escalate

ARGUMENTS: $1 (specialist-name), $2 (--from-retro flag), $3 (issue-key if --from-retro)
