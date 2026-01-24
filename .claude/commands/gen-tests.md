---
description: Generate unit tests for specified code with test data factories
---

# Generate Unit Tests

Generate comprehensive unit tests for specified code.

## Step 0: Load Required Skills (MANDATORY)

**BEFORE doing anything else, use the Read tool to load these skill files:**

```
Read .claude/skills/quality-gates.md
```

This skill contains the test and coverage commands for your project. Do not proceed until you have read it.

## Usage

```
/gen-tests <target> [--coverage <threshold>]
```

**Arguments:**
- `target`: File path, class name, or method to test
- `--coverage`: Target coverage percentage (default: from CLAUDE.md)

## Workflow

### Step 1: Analyze Target

Read the target file/class/method to understand:
- Public API surface
- Dependencies to mock
- Edge cases to cover
- Existing patterns in codebase

### Step 2: Check Existing Tests

Look for existing test files:
- Identify test naming convention
- Check test framework in use
- Find test data factories

### Step 3: Invoke Testing Specialist

Use the testing-specialist agent to:
- Determine test structure
- Identify mocking strategy
- Plan test cases

### Step 4: Generate Tests

Create tests following project patterns:
- Arrange-Act-Assert structure
- Descriptive test names
- Proper mocking
- Edge case coverage

### Step 5: Create Test Data Factory (if needed)

If complex test data required:
- Create or extend test factory
- Use builder pattern
- Support common scenarios

### Step 6: Write Test File

Write test file to appropriate location based on language:
- Java: `src/test/java/...`
- TypeScript: `__tests__/` or `*.test.ts`
- Python: `tests/` or `test_*.py`

### Step 7: Verify Tests

```bash
# Run just the new tests
[TEST_COMMAND] --filter [test-name]

# Check coverage
[COVERAGE_COMMAND]
```

### Step 8: Report Results

```markdown
## Tests Generated for [target]

### Test File
`[path/to/test/file]`

### Tests Created
- [ ] `should[Action]When[Condition]` - [description]
- [ ] `should[Action]When[Condition]` - [description]

### Test Data Factory
- Created/Updated: `[factory-file]`
- New methods: [list]

### Next Steps
1. Review generated tests
2. Run full test suite
3. Check coverage report
```

## Test Generation Patterns

### Delegation to Testing Specialist

The testing-specialist handles framework-specific patterns:
- JUnit 5 for Java
- Jest/Vitest for TypeScript
- pytest for Python
- RSpec for Ruby
- Go testing for Go

ARGUMENTS: $1 (target: file/class/method to test), $2 (--coverage threshold)
