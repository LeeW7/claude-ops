---
description: Swift/Vapor development patterns and learnings from retrospectives
---

# Development Patterns

> Actionable learnings graduated from retrospectives. Reference this before planning and implementing features.

## How to Use This File

| Phase | Action |
|-------|--------|
| `/plan` | Check domain-relevant patterns before designing |
| `/implement` | Review pitfalls in relevant domains before coding |
| `/retrospective` | Graduate new patterns here after validation |

---

## Architecture

- **[Service Layer] Use actors for thread-safe services** - All services managing state must be Swift actors for thread safety. Use `public actor MyService` not `public class`
  - *Source: CLAUDE.md code style*

- **[Dependency Injection] Use Application storage pattern** - Store services in `Application.storage` with typed keys, not global singletons
  ```swift
  struct MyServiceKey: StorageKey {
      typealias Value = MyService
  }
  ```
  - *Source: configure.swift patterns*

- **[Weak References] Avoid retain cycles in services** - Store `weak var app: Application?` in services to prevent memory leaks
  - *Source: ClaudeService.swift patterns*

## Vapor & API

- **[Routes] Register via RouteCollection** - Controllers implement `RouteCollection` and are registered in `routes.swift`
  - *Source: CLAUDE.md architecture*

- **[DTOs] Use Content protocol** - All API response types conform to Vapor's `Content` for automatic JSON encoding
  - *Source: CLAUDE.md code style*

- **[Errors] Use Abort for HTTP errors** - Throw `Abort(.notFound, reason: "message")` for proper HTTP status codes
  - *Source: JobController.swift patterns*

## Process Management

- **[PTY] Use script wrapper for unbuffered CLI output** - Wrap CLI commands with `script -q /dev/null <command>` to prevent output buffering
  - *Source: ClaudeService.swift patterns*

- **[Termination] Kill process groups** - Use `kill(-pid, SIGTERM)` with negative PID to terminate child processes
  - *Source: ClaudeService.swift patterns*

- **[PATH] Extend PATH for external CLIs** - Always add `/opt/homebrew/bin:/usr/local/bin` to process environment
  - *Source: ClaudeService.swift patterns*

## GRDB & Persistence

- **[Records] Flatten nested types** - Store nested structs as separate columns (e.g., `costTotalUsd`, `costInputTokens`)
  - *Source: SQLiteSchema.swift patterns*

- **[Caching] Use TTL-based memory cache** - Cache frequently accessed data with time-based invalidation (5 seconds default)
  - *Source: SQLitePersistenceService.swift patterns*

- **[Migrations] Use DatabaseMigrator** - Register versioned migrations that run on startup
  - *Source: SQLiteSchema.swift patterns*

## SwiftUI

- **[State] Use @EnvironmentObject for shared state** - Pass `ObservableObject` instances down the view hierarchy
  - *Source: ClaudeOpsApp.swift patterns*

- **[Async] Wrap async calls in Task** - SwiftUI button actions are synchronous, use `Task { await ... }`
  - *Source: MenuBarView.swift patterns*

- **[Menu Bar] Use MenuBarExtra with .window style** - For dropdown menu bar apps on macOS 14+
  - *Source: ClaudeOpsApp.swift patterns*

## Testing

- **[Actors] Use await for all actor method calls** - Test actors with async test methods
  - *Source: JobCancellationManagerTests.swift patterns*

- **[Concurrency] Use withTaskGroup for stress tests** - Test concurrent access patterns with task groups
  - *Source: JobCancellationManagerTests.swift patterns*

- **[@testable import] Access internal types** - Use `@testable import ServerLib` to test internal types
  - *Source: CLAUDE.md testing patterns*

---

## Graduation Criteria

A learning graduates from retrospective to pattern when:
1. **Reusable** - Applies to future features, not one-off
2. **Actionable** - Clear do/don't guidance
3. **Validated** - Worked in practice

---

*Last updated: 2026-01-24*
