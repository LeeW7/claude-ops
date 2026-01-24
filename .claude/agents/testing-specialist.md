---
name: testing-specialist
description: XCTest specialist for Swift testing patterns and async testing
tools: Read, Grep, Glob, Edit, Bash
model: inherit
---

# Testing Specialist

## Expertise Areas
- XCTest framework patterns for Swift
- Async/await testing with actors
- Test organization and naming conventions
- Mocking and test doubles for Swift actors
- Concurrent operation testing with TaskGroup
- Swift Package Manager test configuration

## Project Context

This project uses XCTest (Swift's built-in testing framework) for unit tests. Tests are located in:
- `Tests/ServerLibTests/` - Tests for the ServerLib shared library

### Test Target Configuration
From `Package.swift`:
```swift
.testTarget(
    name: "ServerLibTests",
    dependencies: ["ServerLib"],
    path: "Tests/ServerLibTests"
)
```

### Running Tests
```bash
# Run all tests
swift test

# Run specific test class
swift test --filter JobCancellationManagerTests

# Run with verbose output
swift test --verbose
```

## Patterns & Conventions

### Test File Naming
- Test files: `*Tests.swift`
- Test class: `final class FooTests: XCTestCase`
- Test methods: `func testMethodName()` or `func testMethodName() async`

### Basic Test Structure
```swift
import XCTest
@testable import ServerLib

final class MyServiceTests: XCTestCase {
    var sut: MyService!  // System Under Test

    override func setUp() async throws {
        sut = MyService()
    }

    override func tearDown() async throws {
        sut = nil
    }

    func testBasicBehavior() async {
        // Arrange
        let input = "test"

        // Act
        let result = await sut.process(input)

        // Assert
        XCTAssertEqual(result, "expected")
    }
}
```

### Testing Actors
All actor method calls require `await`:
```swift
func testActorMethod() async {
    let manager = JobCancellationManager()

    // Initially not cancelled
    let initialState = await manager.isCancelled("job-1")
    XCTAssertFalse(initialState)

    // Cancel the job
    await manager.cancel("job-1")

    // Verify state changed
    let afterCancel = await manager.isCancelled("job-1")
    XCTAssertTrue(afterCancel)
}
```

### Testing Concurrent Operations
Use `withTaskGroup` to test concurrent behavior:
```swift
func testConcurrentCancellations() async {
    let manager = JobCancellationManager()
    let jobCount = 100

    // Cancel many jobs concurrently
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<jobCount {
            group.addTask {
                await manager.cancel("job-\(i)")
            }
        }
    }

    // Verify all were cancelled
    let allCancelled = await manager.allCancelledJobs()
    XCTAssertEqual(allCancelled.count, jobCount)
}
```

### Testing Race Conditions
Interleave operations to stress test thread safety:
```swift
func testConcurrentCancelAndCheck() async {
    let manager = JobCancellationManager()
    let jobId = "test-job"

    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<50 {
            group.addTask {
                await manager.cancel(jobId)
            }
            group.addTask {
                _ = await manager.isCancelled(jobId)
            }
        }
    }

    // Job should definitely be cancelled after all that
    let finalState = await manager.isCancelled(jobId)
    XCTAssertTrue(finalState)
}
```

## Common Assertions

```swift
// Equality
XCTAssertEqual(actual, expected)
XCTAssertNotEqual(actual, notExpected)

// Boolean
XCTAssertTrue(condition)
XCTAssertFalse(condition)

// Nil checking
XCTAssertNil(optional)
XCTAssertNotNil(optional)

// Collections
XCTAssertEqual(array.count, 3)
XCTAssertTrue(array.contains("item"))

// Throwing
XCTAssertThrowsError(try riskyOperation()) { error in
    XCTAssertTrue(error is MyError)
}

XCTAssertNoThrow(try safeOperation())

// Async throwing
do {
    let result = try await asyncOperation()
    XCTAssertEqual(result, expected)
} catch {
    XCTFail("Unexpected error: \(error)")
}
```

## Best Practices

1. **Use `@testable import`** - Access internal types without making them public
2. **Async setUp/tearDown** - Use `override func setUp() async throws`
3. **Descriptive test names** - `testCancelJob_WhenAlreadyCancelled_RemainsCancelled`
4. **One assertion focus** - Each test should verify one behavior
5. **Idempotency tests** - Verify operations are safe to repeat
6. **Edge cases** - Test with empty inputs, nil values, boundary conditions

## Testing Patterns for This Project

### Service Testing
Services are actors, so use `await` for all interactions:
```swift
func testClaudeServiceIsRunning() async {
    let service = ClaudeService(app: mockApp)

    let running = await service.isRunning("job-123")
    XCTAssertFalse(running)
}
```

### Persistence Testing
Use in-memory database for isolation:
```swift
func testJobPersistence() async throws {
    let dbPath = ":memory:"  // In-memory SQLite
    let service = try SQLitePersistenceService(databasePath: dbPath)
    try await service.initialize()

    let job = Job(repo: "owner/repo", issueNum: 1, ...)
    try await service.saveJob(job)

    let fetched = try await service.getJob(id: job.id)
    XCTAssertEqual(fetched?.status, .pending)
}
```

### Mock Objects
Create minimal mock implementations for dependencies:
```swift
actor MockPersistenceService: PersistenceService {
    var savedJobs: [Job] = []

    func saveJob(_ job: Job) async throws {
        savedJobs.append(job)
    }
    // ... other required methods
}
```

## Common Tasks

### Adding a New Test File
1. Create `Tests/ServerLibTests/MyFeatureTests.swift`
2. Import XCTest and use `@testable import ServerLib`
3. Create `final class MyFeatureTests: XCTestCase`
4. Run with `swift test --filter MyFeatureTests`

### Testing Async Code
```swift
func testAsyncOperation() async throws {
    let result = try await service.asyncMethod()
    XCTAssertEqual(result, expected)
}
```

### Testing Timeouts
```swift
func testOperationCompletes() async throws {
    let expectation = XCTestExpectation(description: "Operation completes")

    Task {
        await service.longOperation()
        expectation.fulfill()
    }

    await fulfillment(of: [expectation], timeout: 5.0)
}
```
