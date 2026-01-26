import Vapor
import Foundation

/// Error thrown when a GitHub CLI command fails
public struct GitHubCLIError: Error, LocalizedError {
    public let command: String
    public let exitCode: Int32
    public let stderr: String
    public let stdout: String

    public var errorDescription: String? {
        let detail = stderr.isEmpty ? stdout : stderr
        return "GitHub CLI failed (exit \(exitCode)): \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    /// Check if this is a "not found" type error
    public var isNotFound: Bool {
        stderr.contains("not found") || stderr.contains("Could not resolve")
    }

    /// Check if this is an "already exists" error (not really an error for our purposes)
    public var isAlreadyExists: Bool {
        stderr.contains("already exists")
    }
}

/// Service for interacting with GitHub via the gh CLI
public struct GitHubService {
    public init() {}

    /// Find the gh CLI executable
    private func findGH() -> String {
        let paths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "gh" // Fallback - will fail with clear error if not in PATH
    }

    /// Run a gh CLI command and return the output
    /// - Throws: GitHubCLIError if the command exits with non-zero status
    private func runGH(_ args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: findGH())
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw GitHubCLIError(
                command: "gh \(args.joined(separator: " "))",
                exitCode: process.terminationStatus,
                stderr: stderr,
                stdout: stdout
            )
        }

        return stdout
    }

    /// Run a gh CLI command with input via stdin
    /// - Throws: GitHubCLIError if the command exits with non-zero status
    private func runGHWithInput(_ args: [String], input: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: findGH())
        process.arguments = args

        let inputPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Write input
        inputPipe.fileHandleForWriting.write(input.data(using: .utf8)!)
        inputPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw GitHubCLIError(
                command: "gh \(args.joined(separator: " "))",
                exitCode: process.terminationStatus,
                stderr: stderr,
                stdout: stdout
            )
        }

        return stdout
    }

    // MARK: - Issue Operations

    /// Get issue details as JSON
    func getIssue(repo: String, number: Int) async throws -> [String: Any]? {
        let output = try await runGH([
            "issue", "view", String(number),
            "--repo", repo,
            "--json", "title,body,state,labels,comments"
        ])

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// Check if issue is closed
    func isIssueClosed(repo: String, number: Int) async throws -> Bool {
        let output = try await runGH([
            "issue", "view", String(number),
            "--repo", repo,
            "--json", "state"
        ])

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = json["state"] as? String else {
            return false
        }
        return state == "CLOSED"
    }

    /// Create a new issue
    func createIssue(repo: String, title: String, body: String, labels: [String] = []) async throws -> String {
        var args = ["issue", "create", "--repo", repo, "--title", title, "--body-file", "-"]
        for label in labels {
            args += ["--label", label]
        }

        let output = try await runGHWithInput(args, input: body)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Add label to issue
    func addLabel(repo: String, number: Int, label: String) async throws {
        _ = try await runGH([
            "issue", "edit", String(number),
            "--repo", repo,
            "--add-label", label
        ])
    }

    /// Remove label from issue
    func removeLabel(repo: String, number: Int, label: String) async throws {
        _ = try await runGH([
            "issue", "edit", String(number),
            "--repo", repo,
            "--remove-label", label
        ])
    }

    /// Post a comment on an issue
    func postComment(repo: String, number: Int, body: String) async throws {
        _ = try await runGHWithInput([
            "issue", "comment", String(number),
            "--repo", repo,
            "--body-file", "-"
        ], input: body)
    }

    /// Close an issue with a comment
    func closeIssue(repo: String, number: Int, comment: String? = nil) async throws {
        var args = ["issue", "close", String(number), "--repo", repo]
        if let comment = comment {
            args += ["--comment", comment]
        }
        _ = try await runGH(args)
    }

    /// List issues with a specific label
    func listIssuesWithLabel(repo: String, label: String) async throws -> [[String: Any]] {
        let output = try await runGH([
            "issue", "list",
            "--repo", repo,
            "--label", label,
            "--json", "number,title"
        ])

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json
    }

    // MARK: - PR Operations

    /// List open PRs
    func listPRs(repo: String, search: String? = nil) async throws -> [[String: Any]] {
        var args = ["pr", "list", "--repo", repo, "--json",
                    "number,url,headRefName,body,title,state,mergeable,mergeStateStatus,statusCheckRollup"]
        if let search = search {
            args += ["--search", search]
        }

        let output = try await runGH(args)

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json
    }

    /// Find PR for an issue
    func findPRForIssue(repo: String, issueNum: Int) async throws -> [String: Any]? {
        // First try to find by "closes:#N" search
        let closesPRs = try await listPRs(repo: repo, search: "closes:#\(issueNum)")
        if let pr = closesPRs.first {
            return pr
        }

        // Fallback: search all PRs
        let allPRs = try await listPRs(repo: repo)
        for pr in allPRs {
            // Check branch name pattern
            if let branch = pr["headRefName"] as? String,
               branch.contains("issue-\(issueNum)") {
                return pr
            }
            // Check body for issue reference
            if let body = pr["body"] as? String,
               body.contains("#\(issueNum)") {
                return pr
            }
        }

        return nil
    }

    /// Mark PR as ready for review
    func markPRReady(repo: String, prNumber: Int) async throws {
        _ = try await runGH([
            "pr", "ready", String(prNumber),
            "--repo", repo
        ])
    }

    /// Merge a PR
    func mergePR(repo: String, prNumber: Int, method: String = "squash", deleteBranch: Bool = true) async throws {
        var args = ["pr", "merge", String(prNumber), "--repo", repo]

        switch method {
        case "squash": args.append("--squash")
        case "rebase": args.append("--rebase")
        default: args.append("--merge")
        }

        if deleteBranch {
            args.append("--delete-branch")
        }

        _ = try await runGH(args)
    }

    // MARK: - Gist Operations

    /// Create a public gist and return the URL
    func createGist(content: String, filename: String, description: String) async throws -> String {
        // Write content to temp file
        let tempPath = "/tmp/gist_\(UUID().uuidString).md"
        try content.write(toFile: tempPath, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
        }

        let output = try await runGH([
            "gist", "create", tempPath,
            "--public",
            "--desc", description
        ])

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Get gist details including raw URL
    func getGistRawURL(gistID: String) async throws -> String? {
        let output = try await runGH([
            "gist", "view", gistID,
            "--json", "files"
        ])

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]],
              let firstFile = files.first,
              let rawURL = firstFile["raw_url"] as? String else {
            return nil
        }

        return rawURL
    }

    // MARK: - Label Management

    /// Required labels for Claude Ops functionality
    public static let requiredLabels: [(name: String, description: String, color: String)] = [
        // Command labels - trigger Claude workflows
        ("cmd:plan-headless", "Trigger Claude to plan this issue", "0E8A16"),
        ("cmd:implement-headless", "Trigger Claude to implement this issue", "1D76DB"),
        ("cmd:revise-headless", "Trigger Claude to revise based on feedback", "5319E7"),
        ("cmd:retrospective-headless", "Trigger Claude to analyze completed work", "FBCA04"),
        // Status labels
        ("ready-for-review", "Ready for code review", "0E8A16"),
        ("blocked", "Issue is blocked and needs attention", "D93F0B"),
    ]

    /// Ensure required labels exist on a repository
    /// Returns list of labels that were created (excludes already existing ones)
    func ensureRequiredLabels(repo: String) async -> [String] {
        var created: [String] = []

        for label in Self.requiredLabels {
            do {
                _ = try await runGH([
                    "label", "create", label.name,
                    "--repo", repo,
                    "--description", label.description,
                    "--color", label.color
                ])
                // If we get here, label was created successfully
                created.append(label.name)
            } catch let error as GitHubCLIError where error.isAlreadyExists {
                // Label already exists - this is fine, not an error
                continue
            } catch {
                // Other errors (permission denied, repo not found, etc.) - log but continue
                // We don't want one label failure to stop the others
                continue
            }
        }

        return created
    }

    /// Validate all repos in the repo map have required labels
    func validateRepos(repos: [String]) async -> [String: [String]] {
        var results: [String: [String]] = [:]

        for repo in repos {
            let created = await ensureRequiredLabels(repo: repo)
            if !created.isEmpty {
                results[repo] = created
            }
        }

        return results
    }

    /// Get all labels on a repository
    func getRepoLabels(repo: String) async throws -> [String] {
        let output = try await runGH([
            "label", "list",
            "--repo", repo,
            "--json", "name"
        ])

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return json.compactMap { $0["name"] as? String }
    }

    /// Check which required labels are missing from a repository
    /// Returns empty array if all required labels exist
    func getMissingLabels(repo: String) async throws -> [String] {
        let existingLabels = try await getRepoLabels(repo: repo)
        let requiredNames = Self.requiredLabels.map { $0.name }
        return requiredNames.filter { !existingLabels.contains($0) }
    }

    /// Check which command labels (cmd:*) are missing from a repository
    /// These are the labels that trigger workflows
    func getMissingCommandLabels(repo: String) async throws -> [String] {
        let existingLabels = try await getRepoLabels(repo: repo)
        let commandLabels = Self.requiredLabels.filter { $0.name.hasPrefix("cmd:") }.map { $0.name }
        return commandLabels.filter { !existingLabels.contains($0) }
    }
}
