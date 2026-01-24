import Vapor
import Foundation

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
        return "gh" // Fallback
    }

    /// Run a gh CLI command and return the output
    private func runGH(_ args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: findGH())
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Run a gh CLI command with input via stdin
    private func runGHWithInput(_ args: [String], input: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: findGH())
        process.arguments = args

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()

        // Write input
        inputPipe.fileHandleForWriting.write(input.data(using: .utf8)!)
        inputPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
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
        ("cmd:plan-headless", "Trigger Claude to plan this issue", "0E8A16"),
        ("cmd:implement-headless", "Trigger Claude to implement this issue", "1D76DB"),
        ("ready-for-review", "Ready for code review", "0E8A16"),
    ]

    /// Ensure required labels exist on a repository
    func ensureRequiredLabels(repo: String) async -> [String] {
        var created: [String] = []

        for label in Self.requiredLabels {
            // Try to create the label - will fail silently if it exists
            let output = try? await runGH([
                "label", "create", label.name,
                "--repo", repo,
                "--description", label.description,
                "--color", label.color
            ])

            // Check if we created it (no error about already exists)
            if let output = output, !output.contains("already exists") {
                created.append(label.name)
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
}
