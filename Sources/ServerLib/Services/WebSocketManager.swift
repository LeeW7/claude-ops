import Vapor
import NIOCore
import NIOConcurrencyHelpers
import Foundation

/// Wrapper to store WebSocket with its EventLoop
private struct WebSocketConnection: @unchecked Sendable {
    let ws: WebSocket
    let eventLoop: EventLoop

    func send(_ text: String) {
        // Dispatch to the correct event loop
        eventLoop.execute {
            self.ws.send(text, promise: nil)
        }
    }

    func isSame(as other: WebSocket) -> Bool {
        return ws === other
    }
}

/// Manages WebSocket connections for real-time job streaming
/// Uses a lock instead of actor to avoid event loop hopping issues
public final class WebSocketManager: Sendable {
    /// Special key for global subscribers who want all job updates
    public static let globalChannel = "_global"

    /// Connected clients per job ID (or "_global" for all updates)
    private let connections: NIOLockedValueBox<[String: [WebSocketConnection]]>

    public init() {
        self.connections = NIOLockedValueBox([:])
    }

    /// Add a global WebSocket connection (receives all job status updates)
    public func addGlobalConnection(_ ws: WebSocket, eventLoop: EventLoop) {
        addConnection(ws, eventLoop: eventLoop, forJob: Self.globalChannel)
    }

    /// Remove a global WebSocket connection
    public func removeGlobalConnection(_ ws: WebSocket) {
        removeConnection(ws, forJob: Self.globalChannel)
    }

    /// Add a WebSocket connection for a job
    public func addConnection(_ ws: WebSocket, eventLoop: EventLoop, forJob jobId: String) {
        let connection = WebSocketConnection(ws: ws, eventLoop: eventLoop)
        connections.withLockedValue { dict in
            if dict[jobId] == nil {
                dict[jobId] = []
            }
            dict[jobId]?.append(connection)
        }
    }

    /// Remove a WebSocket connection
    public func removeConnection(_ ws: WebSocket, forJob jobId: String) {
        connections.withLockedValue { dict in
            dict[jobId]?.removeAll { $0.isSame(as: ws) }
            if dict[jobId]?.isEmpty == true {
                dict.removeValue(forKey: jobId)
            }
        }
    }

    /// Broadcast a message to all clients watching a job
    public func broadcast(to jobId: String, message: StreamMessage) {
        let clients = connections.withLockedValue { dict in
            dict[jobId] ?? []
        }

        guard !clients.isEmpty else { return }

        do {
            let data = try JSONEncoder().encode(message)
            let text = String(data: data, encoding: .utf8) ?? "{}"

            for client in clients {
                client.send(text)
            }
        } catch {
            // Silently fail - encoding error
        }
    }

    /// Broadcast raw text to all clients watching a job
    public func broadcastRaw(to jobId: String, text: String) {
        let clients = connections.withLockedValue { dict in
            dict[jobId] ?? []
        }

        for client in clients {
            client.send(text)
        }
    }

    /// Broadcast a job event to all global subscribers
    /// Used for job lifecycle events (created, completed, failed, etc.)
    public func broadcastGlobal(_ event: JobEvent) {
        let clients = connections.withLockedValue { dict in
            dict[Self.globalChannel] ?? []
        }

        guard !clients.isEmpty else { return }

        do {
            let data = try JSONEncoder().encode(event)
            let text = String(data: data, encoding: .utf8) ?? "{}"

            for client in clients {
                client.send(text)
            }
        } catch {
            // Silently fail - encoding error
        }
    }

    /// Get count of global subscribers
    public func globalClientCount() -> Int {
        return clientCount(forJob: Self.globalChannel)
    }

    /// Get count of connected clients for a job
    public func clientCount(forJob jobId: String) -> Int {
        return connections.withLockedValue { dict in
            dict[jobId]?.count ?? 0
        }
    }

    /// Check if any clients are connected to a job
    public func hasClients(forJob jobId: String) -> Bool {
        return clientCount(forJob: jobId) > 0
    }
}

// MARK: - Stream Message Types

/// Messages sent over WebSocket for job streaming
public struct StreamMessage: Codable, Sendable {
    public let type: StreamMessageType
    public let jobId: String
    public let timestamp: Date
    public let data: StreamData?

    public init(type: StreamMessageType, jobId: String, data: StreamData? = nil) {
        self.type = type
        self.jobId = jobId
        self.timestamp = Date()
        self.data = data
    }
}

public enum StreamMessageType: String, Codable, Sendable {
    case connected          // Initial connection established
    case statusChange       // Job status changed
    case assistantText      // Claude is outputting text
    case assistantThinking  // Claude is thinking
    case toolUse            // Claude is using a tool
    case toolResult         // Tool execution result
    case userInput          // User sent input
    case result             // Final result with cost
    case error              // Error occurred
    case disconnected       // Clean disconnect
}

public enum StreamData: Codable, Sendable {
    case text(String)
    case status(String)
    case tool(ToolUseData)
    case result(ResultData)
    case error(String)

    enum CodingKeys: String, CodingKey {
        case type, content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let content = try container.decode(String.self, forKey: .content)
            self = .text(content)
        case "status":
            let content = try container.decode(String.self, forKey: .content)
            self = .status(content)
        case "tool":
            let content = try container.decode(ToolUseData.self, forKey: .content)
            self = .tool(content)
        case "result":
            let content = try container.decode(ResultData.self, forKey: .content)
            self = .result(content)
        case "error":
            let content = try container.decode(String.self, forKey: .content)
            self = .error(content)
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown type"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let content):
            try container.encode("text", forKey: .type)
            try container.encode(content, forKey: .content)
        case .status(let content):
            try container.encode("status", forKey: .type)
            try container.encode(content, forKey: .content)
        case .tool(let content):
            try container.encode("tool", forKey: .type)
            try container.encode(content, forKey: .content)
        case .result(let content):
            try container.encode("result", forKey: .type)
            try container.encode(content, forKey: .content)
        case .error(let content):
            try container.encode("error", forKey: .type)
            try container.encode(content, forKey: .content)
        }
    }
}

public struct ToolUseData: Codable, Sendable {
    public let toolName: String
    public let toolId: String?
    public let input: String?

    public init(toolName: String, toolId: String? = nil, input: String? = nil) {
        self.toolName = toolName
        self.toolId = toolId
        self.input = input
    }
}

public struct ResultData: Codable, Sendable {
    public let sessionId: String?
    public let totalCostUsd: Double?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheReadTokens: Int?
    public let cacheCreationTokens: Int?
    public let duration: Double?

    public init(
        sessionId: String? = nil,
        totalCostUsd: Double? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheReadTokens: Int? = nil,
        cacheCreationTokens: Int? = nil,
        duration: Double? = nil
    ) {
        self.sessionId = sessionId
        self.totalCostUsd = totalCostUsd
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.duration = duration
    }
}

// MARK: - Global Job Events

/// Events broadcast to all global WebSocket subscribers
/// Used for job lifecycle updates so Flutter doesn't need to poll
public struct JobEvent: Codable, Sendable {
    public let type: JobEventType
    public let timestamp: Date
    public let job: JobEventData

    public init(type: JobEventType, job: JobEventData) {
        self.type = type
        self.timestamp = Date()
        self.job = job
    }
}

public enum JobEventType: String, Codable, Sendable {
    case jobCreated         // New job started
    case jobStatusChanged   // Status transition (running, blocked, etc.)
    case jobCompleted       // Job finished successfully
    case jobFailed          // Job errored
}

/// Minimal job data for events (avoid sending full job object)
public struct JobEventData: Codable, Sendable {
    public let id: String
    public let repo: String
    public let issueNum: Int
    public let issueTitle: String
    public let command: String
    public let status: String
    public let cost: JobCostData?

    public init(
        id: String,
        repo: String,
        issueNum: Int,
        issueTitle: String,
        command: String,
        status: String,
        cost: JobCostData? = nil
    ) {
        self.id = id
        self.repo = repo
        self.issueNum = issueNum
        self.issueTitle = issueTitle
        self.command = command
        self.status = status
        self.cost = cost
    }
}

public struct JobCostData: Codable, Sendable {
    public let totalUsd: Double
    public let inputTokens: Int
    public let outputTokens: Int

    public init(totalUsd: Double, inputTokens: Int, outputTokens: Int) {
        self.totalUsd = totalUsd
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}
