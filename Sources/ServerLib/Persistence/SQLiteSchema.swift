import Foundation
import GRDB

// MARK: - Job Record

/// SQLite record for Job model
struct JobRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "jobs"

    var id: String
    var repo: String
    var repoSlug: String
    var issueNum: Int
    var issueTitle: String
    var command: String
    var status: String
    var startTime: Int
    var completedTime: Int?
    var logPath: String
    var localPath: String
    var fullCommand: String
    var error: String?
    var sessionId: String?
    var createdAt: Date
    var updatedAt: Date

    // Flattened cost fields
    var costTotalUsd: Double?
    var costInputTokens: Int?
    var costOutputTokens: Int?
    var costCacheReadTokens: Int?
    var costCacheCreationTokens: Int?
    var costModel: String?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let repo = Column(CodingKeys.repo)
        static let repoSlug = Column(CodingKeys.repoSlug)
        static let issueNum = Column(CodingKeys.issueNum)
        static let issueTitle = Column(CodingKeys.issueTitle)
        static let command = Column(CodingKeys.command)
        static let status = Column(CodingKeys.status)
        static let startTime = Column(CodingKeys.startTime)
        static let completedTime = Column(CodingKeys.completedTime)
        static let logPath = Column(CodingKeys.logPath)
        static let localPath = Column(CodingKeys.localPath)
        static let fullCommand = Column(CodingKeys.fullCommand)
        static let error = Column(CodingKeys.error)
        static let sessionId = Column(CodingKeys.sessionId)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    /// Convert from Job model
    init(from job: Job) {
        self.id = job.id
        self.repo = job.repo
        self.repoSlug = job.repoSlug
        self.issueNum = job.issueNum
        self.issueTitle = job.issueTitle
        self.command = job.command
        self.status = job.status.rawValue
        self.startTime = job.startTime
        self.completedTime = job.completedTime
        self.logPath = job.logPath
        self.localPath = job.localPath
        self.fullCommand = job.fullCommand
        self.error = job.error
        self.sessionId = job.sessionId
        self.createdAt = job.createdAt
        self.updatedAt = job.updatedAt

        if let cost = job.cost {
            self.costTotalUsd = cost.totalUsd
            self.costInputTokens = cost.inputTokens
            self.costOutputTokens = cost.outputTokens
            self.costCacheReadTokens = cost.cacheReadTokens
            self.costCacheCreationTokens = cost.cacheCreationTokens
            self.costModel = cost.model
        }
    }

    /// Convert to Job model
    func toJob() -> Job {
        var job = Job(
            repo: repo,
            issueNum: issueNum,
            issueTitle: issueTitle,
            command: command,
            localPath: localPath
        )

        // Override computed fields with stored values
        job.status = JobStatus(rawValue: status) ?? .pending
        job.completedTime = completedTime
        job.error = error
        job.sessionId = sessionId
        job.updatedAt = updatedAt

        // Reconstruct cost if present
        if let totalUsd = costTotalUsd {
            job.cost = JobCost(
                totalUsd: totalUsd,
                inputTokens: costInputTokens ?? 0,
                outputTokens: costOutputTokens ?? 0,
                cacheReadTokens: costCacheReadTokens ?? 0,
                cacheCreationTokens: costCacheCreationTokens ?? 0,
                model: costModel ?? "unknown"
            )
        }

        return job
    }
}

// MARK: - Worktree Record

/// SQLite record for WorktreeInfo
struct WorktreeRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "worktrees"

    var issueKey: String
    var path: String
    var repo: String
    var issueNum: Int
    var branch: String
    var createdAt: Date

    enum Columns {
        static let issueKey = Column(CodingKeys.issueKey)
        static let path = Column(CodingKeys.path)
        static let repo = Column(CodingKeys.repo)
        static let issueNum = Column(CodingKeys.issueNum)
        static let branch = Column(CodingKeys.branch)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    /// Convert from WorktreeInfo
    init(from info: WorktreeService.WorktreeInfo) {
        self.issueKey = info.issueKey
        self.path = info.path
        self.repo = info.repo
        self.issueNum = info.issueNum
        self.branch = info.branch
        self.createdAt = info.createdAt
    }

    /// Convert to WorktreeInfo
    func toWorktreeInfo() -> WorktreeService.WorktreeInfo {
        WorktreeService.WorktreeInfo(
            issueKey: issueKey,
            path: path,
            repo: repo,
            issueNum: issueNum,
            branch: branch,
            createdAt: createdAt
        )
    }
}

// MARK: - Quick Session Record

/// SQLite record for QuickSession model
struct QuickSessionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "quick_sessions"

    var id: String
    var repo: String
    var status: String
    var worktreePath: String?
    var claudeSessionId: String?
    var createdAt: Date
    var lastActivity: Date
    var messageCount: Int
    var totalCostUsd: Double

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let repo = Column(CodingKeys.repo)
        static let status = Column(CodingKeys.status)
        static let worktreePath = Column(CodingKeys.worktreePath)
        static let claudeSessionId = Column(CodingKeys.claudeSessionId)
        static let createdAt = Column(CodingKeys.createdAt)
        static let lastActivity = Column(CodingKeys.lastActivity)
        static let messageCount = Column(CodingKeys.messageCount)
        static let totalCostUsd = Column(CodingKeys.totalCostUsd)
    }

    /// Convert from QuickSession model
    init(from session: QuickSession) {
        self.id = session.id
        self.repo = session.repo
        self.status = session.status.rawValue
        self.worktreePath = session.worktreePath
        self.claudeSessionId = session.claudeSessionId
        self.createdAt = session.createdAt
        self.lastActivity = session.lastActivity
        self.messageCount = session.messageCount
        self.totalCostUsd = session.totalCostUsd
    }

    /// Convert to QuickSession model
    func toQuickSession() -> QuickSession {
        QuickSession(
            id: id,
            repo: repo,
            status: QuickSessionStatus(rawValue: status) ?? .idle,
            worktreePath: worktreePath,
            claudeSessionId: claudeSessionId,
            createdAt: createdAt,
            lastActivity: lastActivity,
            messageCount: messageCount,
            totalCostUsd: totalCostUsd
        )
    }
}

// MARK: - Quick Message Record

/// SQLite record for QuickMessage model
struct QuickMessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "quick_messages"

    var id: String  // UUID as string
    var sessionId: String
    var role: String
    var content: String
    var timestamp: Date
    var costUsd: Double?
    var toolName: String?
    var toolInput: String?

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let sessionId = Column(CodingKeys.sessionId)
        static let role = Column(CodingKeys.role)
        static let content = Column(CodingKeys.content)
        static let timestamp = Column(CodingKeys.timestamp)
        static let costUsd = Column(CodingKeys.costUsd)
        static let toolName = Column(CodingKeys.toolName)
        static let toolInput = Column(CodingKeys.toolInput)
    }

    /// Convert from QuickMessage model
    init(from message: QuickMessage) {
        self.id = message.id.uuidString
        self.sessionId = message.sessionId
        self.role = message.role.rawValue
        self.content = message.content
        self.timestamp = message.timestamp
        self.costUsd = message.costUsd
        self.toolName = message.toolName
        self.toolInput = message.toolInput
    }

    /// Convert to QuickMessage model
    func toQuickMessage() -> QuickMessage {
        QuickMessage(
            id: UUID(uuidString: id) ?? UUID(),
            sessionId: sessionId,
            role: QuickMessageRole(rawValue: role) ?? .user,
            content: content,
            timestamp: timestamp,
            costUsd: costUsd,
            toolName: toolName,
            toolInput: toolInput
        )
    }
}

// MARK: - Migrations

/// Database migrations for SQLite schema
struct SQLiteMigrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // Migration v1: Create jobs table
        migrator.registerMigration("v1_create_jobs") { db in
            try db.create(table: "jobs") { t in
                t.column("id", .text).primaryKey()
                t.column("repo", .text).notNull()
                t.column("repoSlug", .text).notNull()
                t.column("issueNum", .integer).notNull()
                t.column("issueTitle", .text).notNull()
                t.column("command", .text).notNull()
                t.column("status", .text).notNull()
                t.column("startTime", .integer).notNull()
                t.column("completedTime", .integer)
                t.column("logPath", .text).notNull()
                t.column("localPath", .text).notNull()
                t.column("fullCommand", .text).notNull()
                t.column("error", .text)
                t.column("sessionId", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()

                // Cost fields (flattened)
                t.column("costTotalUsd", .double)
                t.column("costInputTokens", .integer)
                t.column("costOutputTokens", .integer)
                t.column("costCacheReadTokens", .integer)
                t.column("costCacheCreationTokens", .integer)
                t.column("costModel", .text)
            }

            // Indexes for common queries
            try db.create(index: "jobs_status", on: "jobs", columns: ["status"])
            try db.create(index: "jobs_startTime", on: "jobs", columns: ["startTime"])
            try db.create(index: "jobs_repo_issue", on: "jobs", columns: ["repoSlug", "issueNum"])
        }

        // Migration v2: Create worktrees table
        migrator.registerMigration("v2_create_worktrees") { db in
            try db.create(table: "worktrees") { t in
                t.column("issueKey", .text).primaryKey()
                t.column("path", .text).notNull()
                t.column("repo", .text).notNull()
                t.column("issueNum", .integer).notNull()
                t.column("branch", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        // Migration v3: Create quick_sessions table
        migrator.registerMigration("v3_create_quick_sessions") { db in
            try db.create(table: "quick_sessions") { t in
                t.column("id", .text).primaryKey()
                t.column("repo", .text).notNull()
                t.column("status", .text).notNull()
                t.column("worktreePath", .text)
                t.column("claudeSessionId", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("lastActivity", .datetime).notNull()
                t.column("messageCount", .integer).notNull().defaults(to: 0)
                t.column("totalCostUsd", .double).notNull().defaults(to: 0.0)
            }

            // Indexes
            try db.create(index: "quick_sessions_repo", on: "quick_sessions", columns: ["repo"])
            try db.create(index: "quick_sessions_lastActivity", on: "quick_sessions", columns: ["lastActivity"])
        }

        // Migration v4: Create quick_messages table
        migrator.registerMigration("v4_create_quick_messages") { db in
            try db.create(table: "quick_messages") { t in
                t.column("id", .text).primaryKey()
                t.column("sessionId", .text).notNull()
                    .references("quick_sessions", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("costUsd", .double)
                t.column("toolName", .text)
                t.column("toolInput", .text)
            }

            // Indexes
            try db.create(index: "quick_messages_sessionId", on: "quick_messages", columns: ["sessionId"])
            try db.create(index: "quick_messages_timestamp", on: "quick_messages", columns: ["timestamp"])
        }

        return migrator
    }
}
