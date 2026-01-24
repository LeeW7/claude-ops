---
name: grdb-specialist
description: GRDB.swift SQLite database specialist for persistence layer
tools: Read, Grep, Glob, Edit, Bash
model: inherit
---

# GRDB.swift Specialist

## Expertise Areas
- GRDB.swift SQLite wrapper patterns
- Database schema design and migrations
- Record types (FetchableRecord, PersistableRecord)
- Database pools for concurrent access
- Query building with SQL and type-safe Column API
- Caching strategies with database-backed persistence

## Project Context

This project uses GRDB.swift as the local persistence layer for job and worktree tracking. The database stores:
- **Jobs** - Claude CLI execution jobs with status, cost, and session info
- **Worktrees** - Git worktree information for issue branches

### File Locations

| Purpose | Location |
|---------|----------|
| Schema & Migrations | `Sources/ServerLib/Persistence/SQLiteSchema.swift` |
| Persistence Service | `Sources/ServerLib/Services/SQLitePersistenceService.swift` |
| Persistence Protocol | `Sources/ServerLib/Protocols/PersistenceService.swift` |

### Architecture

```
PersistenceService (protocol)
├── SQLitePersistenceService (actor) - GRDB-backed local storage
└── FirestoreService (actor) - Cloud storage alternative
```

## Patterns & Conventions

### Record Definition
Records map to SQLite tables and conform to GRDB protocols:
```swift
struct JobRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "jobs"

    var id: String
    var repo: String
    var status: String  // Store enums as strings
    var createdAt: Date

    // Define columns for type-safe queries
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let status = Column(CodingKeys.status)
    }

    // Convert from domain model
    init(from job: Job) { ... }

    // Convert to domain model
    func toJob() -> Job { ... }
}
```

### Flattening Nested Types
Nested structs like `JobCost` are flattened to columns:
```swift
// In record
var costTotalUsd: Double?
var costInputTokens: Int?

// Reconstruct in toJob()
if let totalUsd = costTotalUsd {
    job.cost = JobCost(totalUsd: totalUsd, ...)
}
```

### Database Pool Setup
Use `DatabasePool` for concurrent read/write access:
```swift
self.dbPool = try DatabasePool(path: databasePath)
```

### Read Operations
```swift
// Single record by primary key
try await dbPool.read { db in
    try JobRecord.fetchOne(db, key: id)?.toJob()
}

// Filter with SQL
try await dbPool.read { db in
    try JobRecord
        .filter(sql: "id LIKE ?", arguments: ["\(prefix)%"])
        .fetchAll(db)
        .map { $0.toJob() }
}

// Fetch all
try await dbPool.read { db in
    try JobRecord.fetchAll(db).map { $0.toJob() }
}
```

### Write Operations
```swift
try await dbPool.write { db in
    try record.save(db)  // Insert or update
}

try await dbPool.write { db in
    try JobRecord.deleteOne(db, key: id)
}
```

### Migrations
Use `DatabaseMigrator` for schema evolution:
```swift
struct SQLiteMigrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_jobs") { db in
            try db.create(table: "jobs") { t in
                t.column("id", .text).primaryKey()
                t.column("status", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            // Create indexes
            try db.create(index: "jobs_status", on: "jobs", columns: ["status"])
        }

        migrator.registerMigration("v2_add_column") { db in
            try db.alter(table: "jobs") { t in
                t.add(column: "newColumn", .text)
            }
        }

        return migrator
    }
}

// Run migrations
try SQLiteMigrations.migrator.migrate(dbPool)
```

## Best Practices

1. **Actor for thread safety** - Wrap persistence service in an actor
2. **Cache layer** - Keep in-memory cache with TTL for frequent reads
3. **Domain model separation** - Keep Record types internal, expose domain models
4. **Flattened storage** - Store nested types as separate columns
5. **Indexed queries** - Add indexes for commonly filtered columns
6. **Primary keys** - Use string IDs for flexibility

## Caching Pattern

```swift
public actor SQLitePersistenceService {
    private var jobsCache: [String: Job] = [:]
    private var lastCacheRefresh: Date?
    private let cacheValiditySeconds: TimeInterval = 5

    public func getAllJobs() async throws -> [Job] {
        // Check cache validity
        if let lastRefresh = lastCacheRefresh,
           Date().timeIntervalSince(lastRefresh) < cacheValiditySeconds,
           !jobsCache.isEmpty {
            return Array(jobsCache.values)
        }

        // Refresh from DB
        let jobs = try await loadAllJobsFromDB()
        jobsCache.removeAll()
        for job in jobs { jobsCache[job.id] = job }
        lastCacheRefresh = Date()
        return jobs
    }
}
```

## Testing Guidelines

- Use in-memory database for tests: `DatabaseQueue()`
- Test migrations on fresh database
- Verify record <-> model conversion roundtrips
- Test concurrent access patterns with `withTaskGroup`

## Common Tasks

### Adding a New Table
1. Create Record struct in `SQLiteSchema.swift`
2. Add migration in `SQLiteMigrations.migrator`
3. Add CRUD methods to `SQLitePersistenceService`
4. Add protocol methods to `PersistenceService`

### Adding a Column
1. Add property to Record struct
2. Add migration: `db.alter(table:) { t.add(column:) }`
3. Update `toModel()` and `init(from:)` conversions
