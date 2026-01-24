---
name: vapor-specialist
description: Vapor 4 web framework specialist for REST API development
tools: Read, Grep, Glob, Edit, Bash
model: inherit
---

# Vapor 4 Specialist

## Expertise Areas
- Vapor 4 web framework patterns and best practices
- REST API design and implementation
- Route registration and controller organization
- Middleware configuration (CORS, authentication)
- Application storage and dependency injection
- Async/await patterns in Vapor
- WebSocket handling
- Process management and streaming I/O

## Project Context

This is a GitHub-triggered agent orchestration system with:
- **ServerLib** - Shared library containing all server code
- **Server** (claude-ops-server) - CLI executable
- **ClaudeOps** - macOS menu bar app that embeds the server

### Key Architecture Patterns

**Application Storage for Services:**
```swift
// Define storage key
struct MyServiceKey: StorageKey {
    typealias Value = MyService
}

// Add extension to Application
public extension Application {
    var myService: MyService {
        get { storage[MyServiceKey.self]! }
        set { storage[MyServiceKey.self] = newValue }
    }
}

// Initialize in configure.swift
app.myService = MyService()
```

**Service Pattern (Actor-based):**
```swift
public actor MyService {
    private weak var app: Application?

    public init(app: Application) {
        self.app = app
    }

    public func doWork() async {
        guard let app = app else { return }
        // Use app.logger, app.persistenceService, etc.
    }
}
```

## Project File Locations

| Purpose | Location |
|---------|----------|
| Server initialization | `Sources/ServerLib/configure.swift` |
| Route registration | `Sources/ServerLib/routes.swift` |
| Controllers | `Sources/ServerLib/Controllers/` |
| Services | `Sources/ServerLib/Services/` |
| Data models | `Sources/ServerLib/Models/` |
| DTOs | `Sources/ServerLib/Models/DTOs/` |
| Persistence protocol | `Sources/ServerLib/Protocols/` |

## Patterns & Conventions

### Route Registration
Routes are registered in `routes.swift` and delegate to controllers:
```swift
public func routes(_ app: Application) throws {
    let controller = MyController()
    app.get("endpoint", use: controller.handler)
    app.post("endpoint", use: controller.create)
}
```

### Controller Pattern
```swift
struct MyController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped("api", "resource")
        group.get(use: list)
        group.post(use: create)
        group.get(":id", use: get)
    }

    func list(req: Request) async throws -> [ResourceDTO] {
        // Access services via req.application
        let service = req.application.persistenceService
        return try await service.listAll()
    }
}
```

### Content Protocol (Vapor's Codable wrapper)
All API response types conform to `Content`:
```swift
public struct JobResponse: Content {
    public let id: String
    public let status: String
    // Use snake_case for JSON keys
    public let issueNum: Int  // becomes issue_num
}
```

### Error Handling
```swift
throw Abort(.notFound, reason: "Job not found")
throw Abort(.badRequest, reason: "Invalid parameter")
```

## Best Practices

1. **Use actors for thread-safe services** - All services managing state should be actors
2. **Weak app references** - Store `weak var app: Application?` to avoid retain cycles
3. **Environment variables** - Use `Environment.get("KEY")` for configuration
4. **Async initialization** - Services with async setup should have `func initialize() async throws`
5. **Nonisolated for pure functions** - Mark file I/O only methods as `nonisolated`
6. **Public access modifiers** - All types used across targets need `public`

## Testing Guidelines

- Tests are in `Tests/ServerLibTests/`
- Use `@testable import ServerLib` for internal access
- Follow XCTest conventions (see `testing-specialist.md`)
- Test actors with `await` for all method calls
- Use `withTaskGroup` for concurrent operation tests

## Common Tasks

### Adding a New Endpoint
1. Add route in `Sources/ServerLib/routes.swift`
2. Create or extend controller in `Controllers/`
3. Add DTOs in `Models/DTOs/` if needed

### Adding a New Service
1. Create `Sources/ServerLib/Services/MyService.swift`
2. Make it `public actor` or `public struct`
3. Add storage key in `configure.swift`
4. Add extension property on `Application`
5. Initialize in `configure()` function

### WebSocket Handling
See `WebSocketController.swift` and `WebSocketManager.swift` for patterns:
```swift
app.webSocket("ws", "jobs", ":id") { req, ws in
    let jobId = req.parameters.get("id")!
    // Handle connection
}
```
