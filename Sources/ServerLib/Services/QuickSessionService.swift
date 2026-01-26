import Vapor
import Foundation

/// Service for managing quick task sessions
public actor QuickSessionService {
    private weak var app: Application?

    /// WebSocket connections for session streaming
    private var sessionConnections: [String: [(WebSocket, EventLoop)]] = [:]

    public init(app: Application) {
        self.app = app
    }

    // MARK: - Session Management

    /// Create a new quick session
    public func createSession(repo: String) async throws -> QuickSession {
        guard let app = app else {
            throw QuickSessionError.serviceUnavailable
        }

        // Verify repo exists in repo_map
        guard let repoMap = app.repoMap,
              let localPath = repoMap.getPath(for: repo) else {
            throw QuickSessionError.repoNotFound(repo)
        }

        // Create session
        var session = QuickSession(repo: repo)

        // Create worktree for the session
        let worktreePath = try await app.worktreeService.getOrCreateWorktree(
            repo: repo,
            issueNum: 0,  // Use 0 for quick sessions
            mainRepoPath: localPath
        )
        session.worktreePath = worktreePath

        // Save session
        try await app.persistenceService.saveQuickSession(session)

        app.logger.info("[QuickSession] Created session \(session.id) for \(repo)")

        return session
    }

    /// Get a session by ID
    public func getSession(id: String) async throws -> QuickSession? {
        guard let app = app else {
            throw QuickSessionError.serviceUnavailable
        }
        return try await app.persistenceService.getQuickSession(id: id)
    }

    /// Get all sessions
    public func getAllSessions() async throws -> [QuickSession] {
        guard let app = app else {
            throw QuickSessionError.serviceUnavailable
        }
        return try await app.persistenceService.getAllQuickSessions()
    }

    /// Get a session with its messages
    public func getSessionWithMessages(id: String) async throws -> QuickSessionWithMessages? {
        guard let app = app else {
            throw QuickSessionError.serviceUnavailable
        }

        guard let session = try await app.persistenceService.getQuickSession(id: id) else {
            return nil
        }

        let messages = try await app.persistenceService.getQuickMessages(sessionId: id)
        return QuickSessionWithMessages(session: session, messages: messages)
    }

    /// Delete a session and clean up resources
    public func deleteSession(id: String) async throws {
        guard let app = app else {
            throw QuickSessionError.serviceUnavailable
        }

        guard let session = try await app.persistenceService.getQuickSession(id: id) else {
            throw QuickSessionError.sessionNotFound(id)
        }

        // Clean up worktree if exists
        if session.worktreePath != nil,
           let repoMap = app.repoMap,
           let localPath = repoMap.getPath(for: session.repo) {
            await app.worktreeService.removeWorktree(
                repo: session.repo,
                issueNum: 0,
                mainRepoPath: localPath
            )
        }

        // Delete messages and session
        try await app.persistenceService.deleteQuickMessages(sessionId: id)
        try await app.persistenceService.deleteQuickSession(id: id)

        // Delete log file
        try? FileManager.default.removeItem(atPath: session.logPath)

        // Close any WebSocket connections
        closeConnections(forSession: id)

        app.logger.info("[QuickSession] Deleted session \(id) and log file")
    }

    // MARK: - Message Handling

    /// Send a message to Claude in the session context
    public func sendMessage(sessionId: String, content: String) async throws -> QuickMessage {
        guard let app = app else {
            throw QuickSessionError.serviceUnavailable
        }

        guard var session = try await app.persistenceService.getQuickSession(id: sessionId) else {
            throw QuickSessionError.sessionNotFound(sessionId)
        }

        guard session.status != .running else {
            throw QuickSessionError.sessionBusy
        }

        guard let worktreePath = session.worktreePath else {
            throw QuickSessionError.noWorktree
        }

        // Save user message
        let userMessage = QuickMessage(
            sessionId: sessionId,
            role: .user,
            content: content
        )
        try await app.persistenceService.saveQuickMessage(userMessage)

        // Update session status
        session.status = .running
        session.lastActivity = Date()
        session.messageCount += 1
        try await app.persistenceService.saveQuickSession(session)

        // Broadcast status change
        broadcastToSession(sessionId, message: [
            "type": "statusChange",
            "data": ["status": "running"]
        ])

        // Execute Claude CLI
        Task {
            await executeClaudeCommand(
                session: session,
                prompt: content,
                worktreePath: worktreePath
            )
        }

        return userMessage
    }

    // MARK: - Claude CLI Execution

    /// Execute Claude CLI with the -p flag
    private func executeClaudeCommand(session: QuickSession, prompt: String, worktreePath: String) async {
        guard let app = app else { return }

        var mutableSession = session

        // Create log file for this session (nonisolated file operations)
        QuickSession.ensureLogsDirectory()
        let logPath = session.logPath

        // Helper to append to log file
        @Sendable func appendToLog(_ message: String) {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            let logURL = URL(fileURLWithPath: logPath)
            if FileManager.default.fileExists(atPath: logPath) {
                if let handle = try? FileHandle(forUpdating: logURL) {
                    handle.seekToEndOfFile()
                    if let data = line.data(using: .utf8) {
                        handle.write(data)
                    }
                    try? handle.close()
                }
            } else {
                try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
            }
        }

        // Initialize log file
        let header = "=== Quick Session: \(session.id) ===\n"
        try? header.write(toFile: logPath, atomically: true, encoding: .utf8)
        app.logger.info("[QuickSession] Created log file: \(logPath)")

        appendToLog("=== Quick Session: \(session.id) ===")
        appendToLog("Repo: \(session.repo)")
        appendToLog("Worktree: \(worktreePath)")
        appendToLog("Prompt: \(prompt)")
        appendToLog("")

        // Build command
        // Note: --verbose is required when using --print with --output-format stream-json
        var arguments = ["-p", prompt, "--print", "--verbose", "--output-format", "stream-json", "--dangerously-skip-permissions"]

        // Add --resume if we have a previous session ID
        if let claudeSessionId = session.claudeSessionId {
            arguments.insert(contentsOf: ["--resume", claudeSessionId], at: 2)
            appendToLog("Resuming session: \(claudeSessionId)")
        }

        let claudePath = findClaudePath()

        appendToLog("Command: \(claudePath) \(arguments.joined(separator: " "))")
        appendToLog("")
        app.logger.info("[QuickSession] Executing: \(claudePath) \(arguments.joined(separator: " ").prefix(100))...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-l", "-c", "cd '\(worktreePath)' && '\(claudePath)' \(arguments.map { "'\($0)'" }.joined(separator: " "))"]
        process.currentDirectoryURL = URL(fileURLWithPath: worktreePath)

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin"
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(extraPaths):\(existingPath)"
        } else {
            env["PATH"] = "\(extraPaths):/usr/bin:/bin"
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var assistantContent = ""
        var totalCost: Double = 0
        var claudeSessionId: String?
        var inputTokens: Int = 0
        var outputTokens: Int = 0

        do {
            try process.run()

            // Process stdout in real-time
            let handle = stdoutPipe.fileHandleForReading
            var buffer = Data()

            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }

                buffer.append(chunk)

                // Process complete lines
                while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = buffer[..<newlineIndex]
                    buffer = Data(buffer[(newlineIndex + 1)...])

                    guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespaces),
                          !line.isEmpty,
                          let jsonData = line.data(using: .utf8),
                          let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                          let type = event["type"] as? String else {
                        continue
                    }

                    // Process different event types
                    switch type {
                    case "assistant":
                        // Extract text content
                        if let message = event["message"] as? [String: Any],
                           let content = message["content"] as? [[String: Any]] {
                            for item in content {
                                if let itemType = item["type"] as? String {
                                    if itemType == "text", let text = item["text"] as? String {
                                        assistantContent += text
                                        appendToLog("[Assistant] \(text)")
                                        broadcastToSession(session.id, message: [
                                            "type": "assistantText",
                                            "content": text
                                        ])
                                    } else if itemType == "tool_use", let toolName = item["name"] as? String {
                                        let input = item["input"] as? [String: Any]
                                        appendToLog("[Tool] \(toolName): \(input ?? [:])")
                                        broadcastToSession(session.id, message: [
                                            "type": "toolUse",
                                            "data": [
                                                "tool": toolName,
                                                "input": input ?? [:]
                                            ]
                                        ])
                                    }
                                }
                            }
                        }

                    case "result":
                        claudeSessionId = event["session_id"] as? String
                        totalCost = event["total_cost_usd"] as? Double ?? 0

                        if let usage = event["usage"] as? [String: Any] {
                            inputTokens = usage["input_tokens"] as? Int ?? 0
                            outputTokens = usage["output_tokens"] as? Int ?? 0
                        }

                        // Extract result text
                        if let resultText = event["result"] as? String {
                            assistantContent = resultText
                        }

                        appendToLog("")
                        appendToLog("=== Result ===")
                        appendToLog("Cost: $\(String(format: "%.4f", totalCost))")
                        appendToLog("Input tokens: \(inputTokens)")
                        appendToLog("Output tokens: \(outputTokens)")
                        appendToLog("Claude session: \(claudeSessionId ?? "none")")

                    default:
                        break
                    }
                }
            }

            process.waitUntilExit()

            // Save assistant message
            let assistantMessage = QuickMessage(
                sessionId: session.id,
                role: .assistant,
                content: assistantContent,
                costUsd: totalCost
            )
            try await app.persistenceService.saveQuickMessage(assistantMessage)

            // Update session
            mutableSession.status = .idle
            mutableSession.lastActivity = Date()
            mutableSession.messageCount += 1
            mutableSession.totalCostUsd += totalCost
            mutableSession.claudeSessionId = claudeSessionId
            try await app.persistenceService.saveQuickSession(mutableSession)

            // Broadcast result
            broadcastToSession(session.id, message: [
                "type": "result",
                "content": assistantContent,
                "data": [
                    "cost_usd": totalCost,
                    "input_tokens": inputTokens,
                    "output_tokens": outputTokens
                ]
            ])

            // Broadcast status change
            broadcastToSession(session.id, message: [
                "type": "statusChange",
                "data": ["status": "idle"]
            ])

            appendToLog("")
            appendToLog("=== Completed ===")

            app.logger.info("[QuickSession] Completed message for \(session.id), cost: $\(String(format: "%.4f", totalCost))")

        } catch {
            appendToLog("")
            appendToLog("=== ERROR ===")
            appendToLog(error.localizedDescription)

            app.logger.error("[QuickSession] Error executing Claude: \(error)")

            // Update session to failed
            mutableSession.status = .failed
            try? await app.persistenceService.saveQuickSession(mutableSession)

            // Broadcast error
            broadcastToSession(session.id, message: [
                "type": "error",
                "content": "Claude CLI failed: \(error.localizedDescription)"
            ])

            broadcastToSession(session.id, message: [
                "type": "statusChange",
                "data": ["status": "failed"]
            ])
        }
    }

    /// Find the claude CLI path
    private func findClaudePath() -> String {
        let paths = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin/claude",
            "/usr/bin/claude"
        ]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "claude"
    }

    // MARK: - WebSocket Management

    /// Add a WebSocket connection for a session
    public func addConnection(_ ws: WebSocket, eventLoop: EventLoop, forSession sessionId: String) {
        var connections = sessionConnections[sessionId] ?? []
        connections.append((ws, eventLoop))
        sessionConnections[sessionId] = connections
    }

    /// Remove a WebSocket connection
    public func removeConnection(_ ws: WebSocket, forSession sessionId: String) {
        guard var connections = sessionConnections[sessionId] else { return }
        connections.removeAll { $0.0 === ws }
        if connections.isEmpty {
            sessionConnections.removeValue(forKey: sessionId)
        } else {
            sessionConnections[sessionId] = connections
        }
    }

    /// Broadcast a message to all connections for a session
    private func broadcastToSession(_ sessionId: String, message: [String: Any]) {
        guard let connections = sessionConnections[sessionId],
              let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        for (ws, eventLoop) in connections {
            eventLoop.execute {
                ws.send(text, promise: nil)
            }
        }
    }

    /// Close all connections for a session
    private func closeConnections(forSession sessionId: String) {
        guard let connections = sessionConnections[sessionId] else { return }

        for (ws, eventLoop) in connections {
            eventLoop.execute {
                _ = ws.close()
            }
        }

        sessionConnections.removeValue(forKey: sessionId)
    }

    // MARK: - Cleanup

    /// Clean up expired sessions (older than 24 hours)
    public func cleanupExpiredSessions() async {
        guard let app = app else { return }

        let expiryDate = Date().addingTimeInterval(-24 * 60 * 60)

        do {
            let expired = try await app.persistenceService.getExpiredQuickSessions(olderThan: expiryDate)

            for session in expired {
                try? await deleteSession(id: session.id)
                app.logger.info("[QuickSession] Cleaned up expired session: \(session.id)")
            }

            // Enforce per-repo limit (keep newest 10)
            let allSessions = try await app.persistenceService.getAllQuickSessions()
            var sessionsByRepo: [String: [QuickSession]] = [:]

            for session in allSessions {
                sessionsByRepo[session.repo, default: []].append(session)
            }

            for (repo, sessions) in sessionsByRepo {
                let sorted = sessions.sorted { $0.lastActivity > $1.lastActivity }
                if sorted.count > 10 {
                    for session in sorted.dropFirst(10) {
                        try? await deleteSession(id: session.id)
                        app.logger.info("[QuickSession] Cleaned up excess session for \(repo): \(session.id)")
                    }
                }
            }

            app.logger.info("[QuickSession] Cleanup complete")

        } catch {
            app.logger.error("[QuickSession] Cleanup failed: \(error)")
        }
    }
}

// MARK: - Errors

public enum QuickSessionError: Error, LocalizedError {
    case serviceUnavailable
    case repoNotFound(String)
    case sessionNotFound(String)
    case sessionBusy
    case noWorktree

    public var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "Quick session service is not available"
        case .repoNotFound(let repo):
            return "Repository '\(repo)' not found in repo_map.json"
        case .sessionNotFound(let id):
            return "Session '\(id)' not found"
        case .sessionBusy:
            return "Session is currently processing a message"
        case .noWorktree:
            return "Session has no worktree configured"
        }
    }
}
