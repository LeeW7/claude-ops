import Vapor
import Foundation

/// Service for managing Claude CLI processes
public actor ClaudeService {
    private var runningProcesses: [String: Process] = [:]
    private weak var app: Application?

    public init(app: Application) {
        self.app = app
    }

    /// Run a Claude CLI command for a job with streaming output
    func runJob(_ job: Job) async {
        guard let app = app else { return }

        app.logger.info("[\(job.id)] Starting in \(job.repo)")

        // Update job status to running
        do {
            try await app.firestoreService.updateJobStatus(id: job.id, status: .running)
        } catch {
            app.logger.error("Failed to update job status: \(error)")
        }

        // Broadcast status change via WebSocket (per-job)
        let statusMessage = StreamMessage(
            type: .statusChange,
            jobId: job.id,
            data: .status("running")
        )
        app.webSocketManager.broadcast(to: job.id, message: statusMessage)

        // Broadcast to global subscribers
        let runningEvent = JobEvent(
            type: .jobStatusChanged,
            job: JobEventData(
                id: job.id,
                repo: job.repo,
                issueNum: job.issueNum,
                issueTitle: job.issueTitle,
                command: job.command,
                status: "running"
            )
        )
        app.webSocketManager.broadcastGlobal(runningEvent)

        // Send push notification
        await app.pushNotificationService.send(
            title: "Agent Started",
            body: "Running in \(job.repo)"
        )

        // Build the streaming command
        // Use --output-format stream-json for real-time streaming
        // --print -p for non-interactive mode
        // --include-partial-messages to get text chunks as they arrive
        let streamingCommand = "cd \(job.localPath) && claude '/\(job.command) \(job.issueNum)' --print --output-format stream-json --include-partial-messages --verbose --dangerously-skip-permissions"

        // Create process with pipes for real-time output
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-l", "-c", streamingCommand]
        process.currentDirectoryURL = URL(fileURLWithPath: job.localPath)

        // Ensure common paths are in PATH
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin"
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(extraPaths):\(existingPath)"
        } else {
            env["PATH"] = "\(extraPaths):/usr/bin:/bin"
        }
        process.environment = env

        // Set up pipes for streaming output
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.qualityOfService = .userInitiated

        // Store process reference
        runningProcesses[job.id] = process

        // Create/clear log file
        FileManager.default.createFile(atPath: job.logPath, contents: nil)

        // Track result data
        var sessionId: String?
        var costData: JobCost?

        do {
            try process.run()

            // Process stdout in real-time
            let outputHandle = stdoutPipe.fileHandleForReading

            // Read output line by line
            await withTaskGroup(of: Void.self) { group in
                // Task to read and process stdout
                group.addTask {
                    await self.processStreamOutput(
                        handle: outputHandle,
                        jobId: job.id,
                        logPath: job.logPath,
                        app: app
                    ) { extractedSessionId, extractedCost in
                        sessionId = extractedSessionId
                        costData = extractedCost
                    }
                }

                // Task to monitor for cancellation - check in-memory flag (no I/O)
                group.addTask {
                    while process.isRunning {
                        // Check in-memory cancellation flag - no Firestore reads!
                        if await app.jobCancellationManager.isCancelled(job.id) {
                            await self.terminateProcess(job.id)
                            self.appendToLog(job.logPath, text: "\nJob cancelled by user\n")
                            // Clear the flag now that we've handled it
                            await app.jobCancellationManager.clearCancellation(job.id)
                            return
                        }
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second - safe since no I/O
                    }
                }
            }

            process.waitUntilExit()
            runningProcesses.removeValue(forKey: job.id)

            if process.terminationStatus == 0 {
                // Check if the issue now has a "blocked" label (agent detected a blocker)
                let isBlocked = await checkIssueHasBlockedLabel(repo: job.repo, issueNum: job.issueNum)

                if isBlocked {
                    // Job exited successfully but detected a blocker - mark as blocked
                    try await app.firestoreService.updateJobStatus(id: job.id, status: .blocked)
                    app.logger.info("[\(job.id)] Job completed but issue has 'blocked' label - marking as blocked")

                    // Broadcast blocked status via WebSocket (per-job)
                    let blockedMessage = StreamMessage(
                        type: .result,
                        jobId: job.id,
                        data: .result(ResultData(
                            sessionId: sessionId,
                            totalCostUsd: costData?.totalUsd,
                            inputTokens: costData?.inputTokens,
                            outputTokens: costData?.outputTokens,
                            cacheReadTokens: costData?.cacheReadTokens,
                            cacheCreationTokens: costData?.cacheCreationTokens
                        ))
                    )
                    app.webSocketManager.broadcast(to: job.id, message: blockedMessage)

                    // Broadcast to global subscribers
                    let blockedEvent = JobEvent(
                        type: .jobStatusChanged,
                        job: JobEventData(
                            id: job.id,
                            repo: job.repo,
                            issueNum: job.issueNum,
                            issueTitle: job.issueTitle,
                            command: job.command,
                            status: "blocked"
                        )
                    )
                    app.webSocketManager.broadcastGlobal(blockedEvent)

                    await app.pushNotificationService.send(
                        title: "Job Blocked",
                        body: "\(job.id) needs attention"
                    )
                    return
                }

                // Update job with session ID and cost data
                try await app.firestoreService.updateJobCompleted(
                    id: job.id,
                    sessionId: sessionId,
                    cost: costData
                )

                // Broadcast result via WebSocket (per-job)
                let resultMessage = StreamMessage(
                    type: .result,
                    jobId: job.id,
                    data: .result(ResultData(
                        sessionId: sessionId,
                        totalCostUsd: costData?.totalUsd,
                        inputTokens: costData?.inputTokens,
                        outputTokens: costData?.outputTokens,
                        cacheReadTokens: costData?.cacheReadTokens,
                        cacheCreationTokens: costData?.cacheCreationTokens
                    ))
                )
                app.webSocketManager.broadcast(to: job.id, message: resultMessage)

                // Broadcast to global subscribers
                let completedEvent = JobEvent(
                    type: .jobCompleted,
                    job: JobEventData(
                        id: job.id,
                        repo: job.repo,
                        issueNum: job.issueNum,
                        issueTitle: job.issueTitle,
                        command: job.command,
                        status: "completed",
                        cost: costData.map { JobCostData(
                            totalUsd: $0.totalUsd,
                            inputTokens: $0.inputTokens,
                            outputTokens: $0.outputTokens
                        )}
                    )
                )
                app.webSocketManager.broadcastGlobal(completedEvent)

                // Sync the issue title from GitHub
                if let updatedTitle = await fetchIssueTitle(repo: job.repo, issueNum: job.issueNum) {
                    if updatedTitle != job.issueTitle {
                        try? await app.firestoreService.updateJobIssueTitle(id: job.id, newTitle: updatedTitle)
                        app.logger.info("[\(job.id)] Updated issue title: \(updatedTitle)")
                    }
                }

                await app.pushNotificationService.send(
                    title: "Job Complete",
                    body: "\(job.id) finished - $\(String(format: "%.4f", costData?.totalUsd ?? 0))"
                )
            } else {
                let errorMsg = "Exit code: \(process.terminationStatus)"
                try await app.firestoreService.updateJobStatus(
                    id: job.id,
                    status: .failed,
                    error: errorMsg
                )

                // Broadcast error via WebSocket (per-job)
                let errorMessage = StreamMessage(
                    type: .error,
                    jobId: job.id,
                    data: .error(errorMsg)
                )
                app.webSocketManager.broadcast(to: job.id, message: errorMessage)

                // Broadcast to global subscribers
                let failedEvent = JobEvent(
                    type: .jobFailed,
                    job: JobEventData(
                        id: job.id,
                        repo: job.repo,
                        issueNum: job.issueNum,
                        issueTitle: job.issueTitle,
                        command: job.command,
                        status: "failed"
                    )
                )
                app.webSocketManager.broadcastGlobal(failedEvent)
            }
        } catch {
            runningProcesses.removeValue(forKey: job.id)
            app.logger.error("[\(job.id)] Error: \(error)")
            try? await app.firestoreService.updateJobStatus(id: job.id, status: .failed, error: error.localizedDescription)
            appendToLog(job.logPath, text: "\nError: \(error)\n")

            // Broadcast error (per-job)
            let errorMessage = StreamMessage(
                type: .error,
                jobId: job.id,
                data: .error(error.localizedDescription)
            )
            app.webSocketManager.broadcast(to: job.id, message: errorMessage)

            // Broadcast to global subscribers
            let failedEvent = JobEvent(
                type: .jobFailed,
                job: JobEventData(
                    id: job.id,
                    repo: job.repo,
                    issueNum: job.issueNum,
                    issueTitle: job.issueTitle,
                    command: job.command,
                    status: "failed"
                )
            )
            app.webSocketManager.broadcastGlobal(failedEvent)
        }
    }

    /// Process streaming JSON output from Claude CLI
    private func processStreamOutput(
        handle: FileHandle,
        jobId: String,
        logPath: String,
        app: Application,
        onResult: @escaping (String?, JobCost?) -> Void
    ) async {
        var buffer = Data()
        var sessionId: String?
        var costData: JobCost?

        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }

            buffer.append(chunk)

            // Process complete lines
            while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[..<newlineIndex]
                buffer = Data(buffer[(newlineIndex + 1)...])

                guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespaces),
                      !line.isEmpty else { continue }

                // Append to log file
                appendToLog(logPath, text: line + "\n")

                // Parse JSON event
                guard let jsonData = line.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    continue
                }

                // Log event type for debugging
                if let type = event["type"] as? String {
                    app.logger.info("[Stream] Event: \(type)")
                }

                // Handle different event types
                await processStreamEvent(event, jobId: jobId, app: app)

                // Extract result data if this is the final result
                if let type = event["type"] as? String, type == "result" {
                    sessionId = event["session_id"] as? String

                    // Extract model from result
                    let model = event["model"] as? String ?? "unknown"

                    if let usage = event["usage"] as? [String: Any] {
                        let inputTokens = usage["input_tokens"] as? Int ?? 0
                        let outputTokens = usage["output_tokens"] as? Int ?? 0
                        let cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0
                        let cacheCreationTokens = usage["cache_creation_input_tokens"] as? Int ?? 0

                        // Calculate cost based on actual model (pricing fetched from Anthropic)
                        let pricing = await app.pricingService.getPricing(for: model)
                        let inputCost = Double(inputTokens) * pricing.inputPerMillion / 1_000_000
                        let outputCost = Double(outputTokens) * pricing.outputPerMillion / 1_000_000
                        let cacheReadCost = Double(cacheReadTokens) * pricing.cacheReadPerMillion / 1_000_000
                        let cacheCreationCost = Double(cacheCreationTokens) * pricing.cacheWritePerMillion / 1_000_000
                        let totalCost = inputCost + outputCost + cacheReadCost + cacheCreationCost

                        costData = JobCost(
                            totalUsd: totalCost,
                            inputTokens: inputTokens,
                            outputTokens: outputTokens,
                            cacheReadTokens: cacheReadTokens,
                            cacheCreationTokens: cacheCreationTokens,
                            model: model
                        )
                    }
                }
            }
        }

        onResult(sessionId, costData)
    }

    /// Process a single stream event and broadcast via WebSocket
    private func processStreamEvent(_ event: [String: Any], jobId: String, app: Application) async {
        guard let type = event["type"] as? String else { return }

        var message: StreamMessage?

        switch type {
        case "assistant":
            // Debug: log assistant event structure
            app.logger.info("[Stream] Assistant event keys: \(event.keys.joined(separator: ", "))")

            // Debug: log message structure
            if let messageData = event["message"] {
                if let jsonData = try? JSONSerialization.data(withJSONObject: messageData, options: [.fragmentsAllowed]),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    app.logger.info("[Stream] Message content: \(jsonStr.prefix(500))")
                }
            }

            // Assistant text output
            if let content = event["message"] as? [String: Any],
               let contentArray = content["content"] as? [[String: Any]] {
                for item in contentArray {
                    if let itemType = item["type"] as? String {
                        if itemType == "text", let text = item["text"] as? String {
                            message = StreamMessage(
                                type: .assistantText,
                                jobId: jobId,
                                data: .text(text)
                            )
                        } else if itemType == "tool_use" {
                            let toolName = item["name"] as? String ?? "unknown"
                            let toolId = item["id"] as? String
                            let input = item["input"] as? [String: Any]
                            let inputStr = input.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                                .flatMap { String(data: $0, encoding: .utf8) }

                            message = StreamMessage(
                                type: .toolUse,
                                jobId: jobId,
                                data: .tool(ToolUseData(
                                    toolName: toolName,
                                    toolId: toolId,
                                    input: inputStr
                                ))
                            )
                        }
                    }
                }
            }

        case "content_block_start", "content_block_delta":
            // Streaming text deltas
            if let delta = event["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                message = StreamMessage(
                    type: .assistantText,
                    jobId: jobId,
                    data: .text(text)
                )
            }

        case "tool_use":
            let toolName = event["name"] as? String ?? "unknown"
            let toolId = event["id"] as? String
            message = StreamMessage(
                type: .toolUse,
                jobId: jobId,
                data: .tool(ToolUseData(toolName: toolName, toolId: toolId))
            )

        case "tool_result":
            let toolId = event["tool_use_id"] as? String
            message = StreamMessage(
                type: .toolResult,
                jobId: jobId,
                data: .tool(ToolUseData(toolName: "result", toolId: toolId))
            )

        case "stream_event":
            // Parse the inner event from --include-partial-messages
            if let innerEvent = event["event"] as? [String: Any],
               let innerType = innerEvent["type"] as? String {

                // Debug: log inner event type
                if innerType == "content_block_delta" || innerType == "content_block_start" {
                    app.logger.info("[Stream] Processing stream_event inner type: \(innerType)")
                }

                switch innerType {
                case "content_block_delta":
                    // Check for text_delta
                    if let delta = innerEvent["delta"] as? [String: Any],
                       let deltaType = delta["type"] as? String,
                       deltaType == "text_delta",
                       let text = delta["text"] as? String {
                        app.logger.info("[Stream] Text delta: \(text.prefix(50))")
                        message = StreamMessage(
                            type: .assistantText,
                            jobId: jobId,
                            data: .text(text)
                        )
                    }
                    // Check for tool input streaming
                    else if let delta = innerEvent["delta"] as? [String: Any],
                            let deltaType = delta["type"] as? String,
                            deltaType == "input_json_delta" {
                        // Tool input is being streamed - we already handle complete tool_use elsewhere
                    }

                case "content_block_start":
                    // Tool use blocks are detected here but we don't send them yet
                    // because they don't have input. We wait for the full 'assistant'
                    // message which includes complete tool data with input.
                    break

                default:
                    break
                }
            }

        default:
            // Log unhandled event types for debugging
            app.logger.info("[Stream] Unhandled event type: \(type) - keys: \(event.keys.joined(separator: ", "))")
        }

        if let msg = message {
            app.webSocketManager.broadcast(to: jobId, message: msg)
        }
    }

    /// Terminate a running process
    public func terminateProcess(_ jobId: String) {
        guard let process = runningProcesses[jobId] else { return }

        // Try to kill the process group
        let pid = process.processIdentifier
        if pid > 0 {
            kill(-pid, SIGTERM) // Negative PID kills process group
        }

        process.terminate()
        runningProcesses.removeValue(forKey: jobId)
    }

    /// Check if a job process is running
    public func isRunning(_ jobId: String) -> Bool {
        return runningProcesses[jobId]?.isRunning ?? false
    }

    /// Read log file contents
    public func readLog(path: String, stripANSI: Bool = true) -> String {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return "Waiting for output..."
        }

        if stripANSI {
            return stripANSICodes(content)
        }
        return content
    }

    /// Read last N lines of log file
    public func readLogTail(path: String, lines: Int = 50, stripANSI: Bool = true) -> [String] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }

        let allLines = content.components(separatedBy: .newlines)
        let tailLines = Array(allLines.suffix(lines))

        if stripANSI {
            return tailLines
                .map { stripANSICodes($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return tailLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Strip ANSI escape codes from text
    private func stripANSICodes(_ text: String) -> String {
        // Match common ANSI escape sequences
        let pattern = #"\x1b\[[^a-zA-Z]*[a-zA-Z]|\x1b\][^\x07]*\x07|\x1b[<>=()].|\r"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    /// Append text to log file
    /// Append text to log file (nonisolated since it only does file I/O)
    private nonisolated func appendToLog(_ path: String, text: String) {
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }

        handle.seekToEndOfFile()
        if let data = text.data(using: .utf8) {
            handle.write(data)
        }
    }

    /// Fetch the current issue title from GitHub
    private func fetchIssueTitle(repo: String, issueNum: Int) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/gh")
        process.arguments = ["issue", "view", String(issueNum), "--repo", repo, "--json", "title", "--jq", ".title"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let title = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !title.isEmpty {
                    return title
                }
            }
        } catch {
            // Silently fail - title sync is best-effort
        }

        return nil
    }

    /// Check if an issue has the "blocked" label
    private func checkIssueHasBlockedLabel(repo: String, issueNum: Int) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/gh")
        process.arguments = ["issue", "view", String(issueNum), "--repo", repo, "--json", "labels", "--jq", ".labels[].name"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let labels = String(data: data, encoding: .utf8) {
                    // Labels are newline-separated
                    return labels.lowercased().contains("blocked")
                }
            }
        } catch {
            // Silently fail - label check is best-effort
        }

        return false
    }

    /// Extract PR URL from log content
    public func extractPRUrl(from logPath: String) -> String? {
        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            return nil
        }

        let pattern = #"https://github\.com/[^/]+/[^/]+/pull/\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range, in: content) else {
            return nil
        }

        return String(content[range])
    }
}

// MARK: - Model Pricing

/// Pricing per million tokens for Claude models
/// Used by PricingService which fetches latest prices from Anthropic
public struct ModelPricing: Sendable {
    public let inputPerMillion: Double
    public let outputPerMillion: Double
    public let cacheReadPerMillion: Double
    public let cacheWritePerMillion: Double

    public init(inputPerMillion: Double, outputPerMillion: Double, cacheReadPerMillion: Double, cacheWritePerMillion: Double) {
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
        self.cacheReadPerMillion = cacheReadPerMillion
        self.cacheWritePerMillion = cacheWritePerMillion
    }
}
