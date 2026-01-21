import Vapor
import Foundation

/// Service for managing Claude CLI processes
public actor ClaudeService {
    private var runningProcesses: [String: Process] = [:]
    private weak var app: Application?

    public init(app: Application) {
        self.app = app
    }

    /// Run a Claude CLI command for a job
    func runJob(_ job: Job) async {
        guard let app = app else { return }

        app.logger.info("[\(job.id)] Starting in \(job.repo)")

        // Update job status to running
        do {
            try await app.firestoreService.updateJobStatus(id: job.id, status: .running)
        } catch {
            app.logger.error("Failed to update job status: \(error)")
        }

        // Send push notification
        await app.pushNotificationService.send(
            title: "Agent Started",
            body: "Running in \(job.repo)"
        )

        // Write command to a temp script file
        let scriptFile = "/tmp/claude_job_\(job.id).sh"
        do {
            try "#!/bin/bash\n\(job.fullCommand)\n".write(
                toFile: scriptFile,
                atomically: true,
                encoding: .utf8
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptFile
            )
        } catch {
            app.logger.error("Failed to create script file: \(error)")
            try? await app.firestoreService.updateJobStatus(id: job.id, status: .failed, error: error.localizedDescription)
            return
        }

        // Create process - run directly since --print flag makes Claude non-interactive
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-l", "-c", "\(scriptFile) > \(job.logPath) 2>&1"]  // -l for login shell to get PATH
        process.currentDirectoryURL = URL(fileURLWithPath: job.localPath)

        // Ensure common paths are in PATH (app doesn't inherit user's shell PATH)
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin"
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(extraPaths):\(existingPath)"
        } else {
            env["PATH"] = "\(extraPaths):/usr/bin:/bin"
        }
        process.environment = env

        // Set up process group so we can kill children
        process.qualityOfService = .userInitiated

        // Store process reference
        runningProcesses[job.id] = process

        do {
            try process.run()

            // Wait for completion in background, checking for cancellation
            while process.isRunning {
                // Check if job was rejected
                if let currentJob = try? await app.firestoreService.getJob(id: job.id),
                   currentJob.status == .rejected {
                    terminateProcess(job.id)
                    appendToLog(job.logPath, text: "\nJob cancelled by user\n")
                    runningProcesses.removeValue(forKey: job.id)
                    return
                }

                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }

            // Process completed
            runningProcesses.removeValue(forKey: job.id)

            if process.terminationStatus == 0 {
                try await app.firestoreService.updateJobStatus(id: job.id, status: .completed)
                await app.pushNotificationService.send(
                    title: "Job Complete",
                    body: "\(job.id) finished"
                )
            } else {
                try await app.firestoreService.updateJobStatus(
                    id: job.id,
                    status: .failed,
                    error: "Exit code: \(process.terminationStatus)"
                )
            }
        } catch {
            runningProcesses.removeValue(forKey: job.id)
            app.logger.error("[\(job.id)] Error: \(error)")
            try? await app.firestoreService.updateJobStatus(id: job.id, status: .failed, error: error.localizedDescription)
            appendToLog(job.logPath, text: "\nError: \(error)\n")
        }

        // Clean up script file
        try? FileManager.default.removeItem(atPath: scriptFile)
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
    private func appendToLog(_ path: String, text: String) {
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }

        handle.seekToEndOfFile()
        if let data = text.data(using: .utf8) {
            handle.write(data)
        }
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
