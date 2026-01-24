---
description: Collect and calculate AI productivity metrics for Swift/Vapor retrospectives
---

# AI Statistics Skill

Collect and calculate AI productivity metrics for Swift projects.

## Metric Collection

```bash
# Get file counts
git diff --name-only HEAD~1 | wc -l           # Files changed
git diff --name-status HEAD~1 | grep "^A" | wc -l  # Files added

# Get line counts
git diff --stat HEAD~1 | tail -1  # Shows insertions/deletions
```

### Swift Test File Detection

| Pattern | Description |
|---------|-------------|
| `*Tests.swift` | XCTest test file |
| `Tests/**/*.swift` | Files in Tests directory |

### Swift Test Case Counting

```bash
# Count test methods in Swift files
grep -r "func test" Tests/ --include="*.swift" | wc -l

# Count XCTest assertions
grep -r "XCTAssert" Tests/ --include="*.swift" | wc -l
```

### Auto-Detect File Categories

```bash
# Swift source files changed
git diff --name-only HEAD~1 | grep "\.swift$"

# Categorize by location
# Sources/ServerLib/Services/*.swift -> Service Logic
# Sources/ServerLib/Models/*.swift -> Models/DTOs
# Sources/ServerLib/Controllers/*.swift -> API Controllers
# Sources/ClaudeOps/*.swift -> SwiftUI Views
# Tests/**/*.swift -> Test Code
```

## Time Estimation Rates

### Swift/Vapor Patterns

| Category | Lines | Rate (LOC/hr) |
|----------|-------|---------------|
| Service Logic (Actors) | N | 10 |
| API Controllers | N | 15 |
| SwiftUI Views | N | 15 |
| Test Code | N | 25 |
| Models/DTOs | N | 40 |
| Config/Boilerplate | N | 50 |

### Category Detection

```bash
# Service files (complex async logic)
git diff --name-only HEAD~1 | grep "Services/"

# Controller files (route handling)
git diff --name-only HEAD~1 | grep "Controllers/"

# Model files (data structures)
git diff --name-only HEAD~1 | grep "Models/"

# View files (SwiftUI)
git diff --name-only HEAD~1 | grep "Sources/ClaudeOps/"

# Test files
git diff --name-only HEAD~1 | grep "Tests/"
```

## Time Calculation

```
Estimated Hours = Σ (Lines per Category / Rate per Category)
```

Conservative estimate assumes:
- No copy-paste from existing code
- Fresh implementation
- Includes debugging time
- Includes code review time
- Includes async/actor complexity

## Update Cumulative Stats

After each `/ship`, update `.claude/retrospectives/cumulative-stats.json`:

```json
{
  "totalIssues": 0,
  "totalLinesAdded": 0,
  "totalLinesRemoved": 0,
  "totalTestsAdded": 0,
  "totalEstimatedHours": 0,
  "totalActualHours": 0,
  "averageTimeSavingsPercent": 0,
  "lastUpdated": "ISO-DATE"
}
```

## When to Use This Skill

- `/ship` - Collect metrics before creating PR
- `/retrospective` - Analyze metrics for learnings
- Quarterly reviews - Aggregate statistics
