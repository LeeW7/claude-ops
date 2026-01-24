# Implementation State: Issue [ISSUE_KEY]

> This file tracks implementation progress for session persistence.
> Updated automatically by `/implement` and `/ship` commands.

## Issue Details

- **Issue**: [ISSUE_KEY]
- **Title**: [Issue title from Jira]
- **Branch**: `feature/[issue-key]-[description]`
- **Started**: [TIMESTAMP]
- **Status**: in-progress

## Progress Checklist

### Phase 0: Pre-Flight
- [ ] Verified on main branch initially
- [ ] Pulled latest changes
- [ ] Created feature branch
- [ ] State file created

### Phase 1: Planning
- [ ] Read issue requirements
- [ ] Reviewed related docs/mockups
- [ ] Created execution plan
- [ ] User approved plan

### Phase 1.5: Design (UI Projects Only)

> **Conditional Phase**: Only if `HAS_UI=true` and issue has UI changes.

- [ ] Created mockup directory: `docs/mockups/[issue-key]/`
- [ ] Created responsive HTML mockups
  - [ ] `mobile.html` (< 768px)
  - [ ] `tablet.html` (768px - 1024px)
  - [ ] `desktop.html` (> 1024px)
  - [ ] `index.html` (preview page)
- [ ] Presented mockups to user for review
- [ ] User approved visual design
- [ ] Documented design decisions
- [ ] Identified reusable components

### Phase 2: Analysis
- [ ] Identified components affected
- [ ] Mapped to specialists needed
- [ ] Checked for existing patterns to follow

### Phase 3: Implementation
- [ ] [Component 1 changes]
- [ ] [Component 2 changes]
- [ ] [Component N changes]

### Phase 4: Testing
- [ ] Unit tests written/updated
- [ ] Tests pass
- [ ] Build succeeds
- [ ] Coverage requirements met ({{COVERAGE_THRESHOLD}}%)

### Phase 5: Ship
- [ ] Changes committed
- [ ] Pushed to remote
- [ ] PR created
- [ ] Issue updated
- [ ] Ready for review

## Current Phase

**Currently on**: Phase [N] - [Phase Name]

**Next action**: [What needs to be done next]

## Blockers

- None

## Notes

[Any important context, decisions made, or things to remember]

## Files Changed

- [ ] `path/to/file` - [description]

## AI Statistics

> Captured by `/ship` command. Used for productivity analysis in `/retrospective`.

### Code Metrics
- **Files Changed**: [COUNT]
- **Files Added**: [COUNT]
- **Lines Added**: [COUNT]
- **Lines Removed**: [COUNT]
- **Net Lines**: [+/- COUNT]

### Test Metrics
- **Test Files Added**: [COUNT]
- **Test Cases Added**: [COUNT]
- **Coverage Achieved**: [PERCENTAGE]%

### Complexity Indicators
- **Services Modified**: [COUNT]
- **New Classes Created**: [COUNT]

### Time Estimation (Conservative)
- **Estimated Manual Dev Time**: [HOURS] hours
- **Actual AI-Assisted Time**: [HOURS] hours
- **Time Savings**: [HOURS] hours ([PERCENTAGE]%)

---

*Last updated: [TIMESTAMP]*
