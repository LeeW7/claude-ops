import Vapor
import Foundation

/// Quick session status values
public enum QuickSessionStatus: String, Codable, CaseIterable, Sendable, Hashable {
    case idle
    case running
    case failed
    case expired
}

/// Message role in a quick session conversation
public enum QuickMessageRole: String, Codable, CaseIterable, Sendable {
    case user
    case assistant
    case system
    case tool
}

/// A quick task session for direct Claude interaction
public struct QuickSession: Content, Identifiable, Sendable, Hashable {
    /// Unique session identifier: quick-{unix_timestamp}
    public let id: String

    /// Repository slug: "owner/repo"
    public let repo: String

    /// Current session status
    public var status: QuickSessionStatus

    /// Path to git worktree (nil until created)
    public var worktreePath: String?

    /// Claude CLI session ID for --resume
    public var claudeSessionId: String?

    /// When session was created
    public let createdAt: Date

    /// Last activity timestamp
    public var lastActivity: Date

    /// Number of messages in session
    public var messageCount: Int

    /// Cumulative API cost
    public var totalCostUsd: Double

    /// Create a new quick session
    public init(repo: String) {
        let timestamp = Int(Date().timeIntervalSince1970)
        self.id = "quick-\(timestamp)"
        self.repo = repo
        self.status = .idle
        self.worktreePath = nil
        self.claudeSessionId = nil
        self.createdAt = Date()
        self.lastActivity = Date()
        self.messageCount = 0
        self.totalCostUsd = 0.0
    }

    /// Restore a session from persistence
    public init(
        id: String,
        repo: String,
        status: QuickSessionStatus,
        worktreePath: String?,
        claudeSessionId: String?,
        createdAt: Date,
        lastActivity: Date,
        messageCount: Int,
        totalCostUsd: Double
    ) {
        self.id = id
        self.repo = repo
        self.status = status
        self.worktreePath = worktreePath
        self.claudeSessionId = claudeSessionId
        self.createdAt = createdAt
        self.lastActivity = lastActivity
        self.messageCount = messageCount
        self.totalCostUsd = totalCostUsd
    }

    /// Coding keys for JSON
    enum CodingKeys: String, CodingKey {
        case id
        case repo
        case status
        case worktreePath = "worktree_path"
        case claudeSessionId = "claude_session_id"
        case createdAt = "created_at"
        case lastActivity = "last_activity"
        case messageCount = "message_count"
        case totalCostUsd = "total_cost_usd"
    }

    /// Path to the log file for this session
    public var logPath: String {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-ops/logs")
            .path
        return "\(logsDir)/session_\(id).log"
    }

    /// Ensure the logs directory exists
    public static func ensureLogsDirectory() {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-ops/logs")
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    }
}

/// A message in a quick session conversation
public struct QuickMessage: Content, Identifiable, Sendable {
    /// Unique message identifier
    public let id: UUID

    /// Session this message belongs to
    public let sessionId: String

    /// Message role (user, assistant, system, tool)
    public let role: QuickMessageRole

    /// Message content
    public let content: String

    /// When message was created
    public let timestamp: Date

    /// API cost for assistant messages
    public var costUsd: Double?

    /// Tool name for tool messages
    public var toolName: String?

    /// Tool input JSON for tool messages
    public var toolInput: String?

    /// Create a new message
    public init(
        sessionId: String,
        role: QuickMessageRole,
        content: String,
        costUsd: Double? = nil,
        toolName: String? = nil,
        toolInput: String? = nil
    ) {
        self.id = UUID()
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.costUsd = costUsd
        self.toolName = toolName
        self.toolInput = toolInput
    }

    /// Restore a message from persistence
    public init(
        id: UUID,
        sessionId: String,
        role: QuickMessageRole,
        content: String,
        timestamp: Date,
        costUsd: Double?,
        toolName: String?,
        toolInput: String?
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.costUsd = costUsd
        self.toolName = toolName
        self.toolInput = toolInput
    }

    /// Coding keys for JSON
    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case role
        case content
        case timestamp
        case costUsd = "cost_usd"
        case toolName = "tool_name"
        case toolInput = "tool_input"
    }
}

/// Response for session with messages
public struct QuickSessionWithMessages: Content {
    public let session: QuickSession
    public let messages: [QuickMessage]

    public init(session: QuickSession, messages: [QuickMessage]) {
        self.session = session
        self.messages = messages
    }

    /// Custom decoding to unflatten session fields
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AllCodingKeys.self)

        // Decode session fields
        let id = try container.decode(String.self, forKey: .id)
        let repo = try container.decode(String.self, forKey: .repo)
        let status = try container.decode(QuickSessionStatus.self, forKey: .status)
        let worktreePath = try container.decodeIfPresent(String.self, forKey: .worktreePath)
        let claudeSessionId = try container.decodeIfPresent(String.self, forKey: .claudeSessionId)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        let lastActivity = try container.decode(Date.self, forKey: .lastActivity)
        let messageCount = try container.decode(Int.self, forKey: .messageCount)
        let totalCostUsd = try container.decode(Double.self, forKey: .totalCostUsd)

        self.session = QuickSession(
            id: id,
            repo: repo,
            status: status,
            worktreePath: worktreePath,
            claudeSessionId: claudeSessionId,
            createdAt: createdAt,
            lastActivity: lastActivity,
            messageCount: messageCount,
            totalCostUsd: totalCostUsd
        )

        // Decode messages
        self.messages = try container.decode([QuickMessage].self, forKey: .messages)
    }

    /// Custom encoding to flatten session fields
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AllCodingKeys.self)
        try container.encode(session.id, forKey: .id)
        try container.encode(session.repo, forKey: .repo)
        try container.encode(session.status, forKey: .status)
        try container.encodeIfPresent(session.worktreePath, forKey: .worktreePath)
        try container.encodeIfPresent(session.claudeSessionId, forKey: .claudeSessionId)
        try container.encode(session.createdAt, forKey: .createdAt)
        try container.encode(session.lastActivity, forKey: .lastActivity)
        try container.encode(session.messageCount, forKey: .messageCount)
        try container.encode(session.totalCostUsd, forKey: .totalCostUsd)
        try container.encode(messages, forKey: .messages)
    }

    enum AllCodingKeys: String, CodingKey {
        case id
        case repo
        case status
        case worktreePath = "worktree_path"
        case claudeSessionId = "claude_session_id"
        case createdAt = "created_at"
        case lastActivity = "last_activity"
        case messageCount = "message_count"
        case totalCostUsd = "total_cost_usd"
        case messages
    }
}
