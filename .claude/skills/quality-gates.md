---
description: Swift Package Manager quality checks for build, test, and lint operations
---

# Quality Gates Skill

Swift Package Manager quality checks for claude-ops project.

## Commands

| Gate | Command |
|------|---------|
| Build Debug | `swift build` |
| Build Release | `swift build -c release` |
| Test | `swift test` |
| Test Specific | `swift test --filter <TestClass>` |
| Test Verbose | `swift test --verbose` |
| Lint | `swiftlint` (if configured) |

## Execution Order

1. **Build** - Verify code compiles
2. **Test** - Run test suite
3. **Lint** - Check code style (optional)

## Failure Handling

| Gate | On Failure |
|------|------------|
| Build | **BLOCK** - Cannot proceed, fix compilation errors |
| Test | **BLOCK** - Cannot proceed, fix failing tests |
| Lint | **WARN** - Note issues, can proceed |

## Running Quality Gates

```bash
# Quick build check
swift build

# Full quality gate check
swift build && swift test

# Run specific test class
swift test --filter JobCancellationManagerTests

# Build release and create app bundle
swift build -c release && ./bundle-app.sh
```

## Common Build Issues

### Missing Dependencies
```bash
# Resolve and fetch dependencies
swift package resolve
```

### Clean Build
```bash
# Clean build artifacts
swift package clean
swift build
```

### macOS Version Issues
This project requires macOS 14+ (set in Package.swift platforms).

## Test Patterns

### Running All Tests
```bash
swift test
```

### Running a Specific Test
```bash
swift test --filter "testCancelJob"
```

### Verbose Output
```bash
swift test --verbose 2>&1 | head -100
```

## When to Use This Skill

- `/implement` - After completing implementation
- `/ship` - Before creating commit/PR
- `/gen-tests` - After generating tests
