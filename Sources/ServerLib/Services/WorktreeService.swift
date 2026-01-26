import Vapor
import Foundation

/// Service for managing git worktrees for parallel job execution
public actor WorktreeService {
    private weak var app: Application?
    private let persistenceService: any PersistenceService

    /// Base directory for all worktrees
    private let worktreeBaseDir: String

    /// Track active worktrees by issue key (repo-issueNum)
    private var activeWorktrees: [String: WorktreeInfo] = [:]

    public struct WorktreeInfo: Codable, Sendable {
        public let issueKey: String
        public let path: String
        public let repo: String
        public let issueNum: Int
        public let branch: String
        public let createdAt: Date

        public init(issueKey: String, path: String, repo: String, issueNum: Int, branch: String, createdAt: Date) {
            self.issueKey = issueKey
            self.path = path
            self.repo = repo
            self.issueNum = issueNum
            self.branch = branch
            self.createdAt = createdAt
        }
    }

    public init(app: Application, persistenceService: any PersistenceService) {
        self.app = app
        self.persistenceService = persistenceService
        self.worktreeBaseDir = "/tmp/claude-ops-worktrees"

        // Ensure base directory exists
        try? FileManager.default.createDirectory(
            atPath: worktreeBaseDir,
            withIntermediateDirectories: true
        )
    }

    /// Load worktrees from persistence on startup
    public func loadFromPersistence() async {
        do {
            let worktrees = try await persistenceService.getAllWorktrees()
            for worktree in worktrees {
                // Only load if the path still exists on disk
                if FileManager.default.fileExists(atPath: worktree.path) {
                    activeWorktrees[worktree.issueKey] = worktree
                    app?.logger.info("[Worktree] Loaded from Firebase: \(worktree.issueKey)")
                } else {
                    // Path doesn't exist anymore, clean up persistence
                    try? await persistenceService.deleteWorktree(issueKey: worktree.issueKey)
                    app?.logger.info("[Worktree] Cleaned stale persistence entry: \(worktree.issueKey)")
                }
            }
            app?.logger.info("[Worktree] Loaded \(activeWorktrees.count) worktrees from persistence")
        } catch {
            app?.logger.error("[Worktree] Failed to load from persistence: \(error)")
        }
    }

    /// Get or create a worktree for an issue
    /// Returns the worktree path to use for running Claude
    public func getOrCreateWorktree(
        repo: String,
        issueNum: Int,
        mainRepoPath: String
    ) async throws -> String {
        let issueKey = makeIssueKey(repo: repo, issueNum: issueNum)
        let repoSlug = repo.split(separator: "/").last.map(String.init) ?? repo
        let expectedPath = "\(worktreeBaseDir)/\(repoSlug)-issue-\(issueNum)"

        // Check if we already have a worktree for this issue in memory
        if let existing = activeWorktrees[issueKey] {
            // Verify it still exists on disk
            if FileManager.default.fileExists(atPath: existing.path) {
                app?.logger.info("[Worktree] Reusing existing worktree for \(issueKey)")
                return existing.path
            } else {
                // Worktree was deleted externally, remove from tracking
                activeWorktrees.removeValue(forKey: issueKey)
            }
        }

        // Check if a valid worktree already exists on disk (e.g., from before server restart)
        if FileManager.default.fileExists(atPath: expectedPath) {
            if await isValidGitWorktree(path: expectedPath) {
                app?.logger.info("[Worktree] Recovering existing worktree for \(issueKey) at \(expectedPath)")

                // Re-register it in our tracking
                let branchName = "claude-ops/issue-\(issueNum)"
                let info = WorktreeInfo(
                    issueKey: issueKey,
                    path: expectedPath,
                    repo: repo,
                    issueNum: issueNum,
                    branch: branchName,
                    createdAt: Date() // We don't know original date, use now
                )
                activeWorktrees[issueKey] = info

                // Save to Firebase
                try? await persistenceService.saveWorktree(info)

                return expectedPath
            } else {
                // Directory exists but is not a valid worktree, clean it up
                app?.logger.info("[Worktree] Cleaning up invalid worktree directory at \(expectedPath)")
                try? FileManager.default.removeItem(atPath: expectedPath)
            }
        }

        // Create new worktree
        let worktreePath = try await createWorktree(
            repo: repo,
            issueNum: issueNum,
            mainRepoPath: mainRepoPath
        )

        return worktreePath
    }

    /// Check if a path is a valid git worktree
    private func isValidGitWorktree(path: String) async -> Bool {
        // A git worktree has a .git file (not directory) that points to the main repo
        let gitPath = "\(path)/.git"

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDir) else {
            return false
        }

        // In a worktree, .git is a file, not a directory
        // It contains "gitdir: /path/to/main/.git/worktrees/name"
        if isDir.boolValue {
            return false // This is a regular repo, not a worktree
        }

        // Verify git recognizes this as a valid worktree by running a simple git command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--is-inside-work-tree"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Create a new worktree for an issue
    private func createWorktree(
        repo: String,
        issueNum: Int,
        mainRepoPath: String
    ) async throws -> String {
        let issueKey = makeIssueKey(repo: repo, issueNum: issueNum)
        let repoSlug = repo.split(separator: "/").last.map(String.init) ?? repo
        let worktreePath = "\(worktreeBaseDir)/\(repoSlug)-issue-\(issueNum)"
        let branchName = "claude-ops/issue-\(issueNum)"

        app?.logger.info("[Worktree] Creating worktree at \(worktreePath)")

        // Remove existing directory if it exists (already validated as non-worktree in getOrCreateWorktree)
        if FileManager.default.fileExists(atPath: worktreePath) {
            app?.logger.info("[Worktree] Removing invalid directory at \(worktreePath) before creating new worktree")
            try? await removeWorktreeFromGit(mainRepoPath: mainRepoPath, worktreePath: worktreePath)
            try? FileManager.default.removeItem(atPath: worktreePath)
        }

        // First, fetch latest from origin in main repo
        let fetchProcess = Process()
        fetchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        fetchProcess.arguments = ["fetch", "origin"]
        fetchProcess.currentDirectoryURL = URL(fileURLWithPath: mainRepoPath)
        fetchProcess.standardOutput = FileHandle.nullDevice
        fetchProcess.standardError = FileHandle.nullDevice
        try? fetchProcess.run()
        fetchProcess.waitUntilExit()

        // Prune stale worktree references (cleans up entries where directory was deleted)
        let pruneProcess = Process()
        pruneProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        pruneProcess.arguments = ["worktree", "prune"]
        pruneProcess.currentDirectoryURL = URL(fileURLWithPath: mainRepoPath)
        pruneProcess.standardOutput = FileHandle.nullDevice
        pruneProcess.standardError = FileHandle.nullDevice
        try? pruneProcess.run()
        pruneProcess.waitUntilExit()
        app?.logger.debug("[Worktree] Pruned stale worktree references")

        // Get the default branch name
        let defaultBranch = try await getDefaultBranch(mainRepoPath: mainRepoPath)

        // Create worktree with a new branch based on the default branch
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "worktree", "add",
            "-B", branchName,  // Create or reset branch
            worktreePath,
            "origin/\(defaultBranch)"  // Base on latest default branch
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: mainRepoPath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw WorktreeError.creationFailed("Failed to create worktree: \(output)")
        }

        // Track the worktree
        let info = WorktreeInfo(
            issueKey: issueKey,
            path: worktreePath,
            repo: repo,
            issueNum: issueNum,
            branch: branchName,
            createdAt: Date()
        )
        activeWorktrees[issueKey] = info

        // Save to Firebase
        try? await persistenceService.saveWorktree(info)

        app?.logger.info("[Worktree] Created worktree for \(issueKey) at \(worktreePath)")

        return worktreePath
    }

    /// Get the default branch name (main or master)
    private func getDefaultBranch(mainRepoPath: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["symbolic-ref", "refs/remotes/origin/HEAD", "--short"]
        process.currentDirectoryURL = URL(fileURLWithPath: mainRepoPath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "origin/", with: "") ?? "main"
            return output
        }

        // Fallback: try to detect main vs master
        let checkMain = Process()
        checkMain.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        checkMain.arguments = ["rev-parse", "--verify", "origin/main"]
        checkMain.currentDirectoryURL = URL(fileURLWithPath: mainRepoPath)
        checkMain.standardOutput = FileHandle.nullDevice
        checkMain.standardError = FileHandle.nullDevice
        try? checkMain.run()
        checkMain.waitUntilExit()

        return checkMain.terminationStatus == 0 ? "main" : "master"
    }

    /// Remove a worktree for an issue (call after PR merge)
    public func removeWorktree(repo: String, issueNum: Int, mainRepoPath: String) async {
        let issueKey = makeIssueKey(repo: repo, issueNum: issueNum)

        guard let info = activeWorktrees[issueKey] else {
            // Try to find and clean up by path pattern anyway
            let repoSlug = repo.split(separator: "/").last.map(String.init) ?? repo
            let expectedPath = "\(worktreeBaseDir)/\(repoSlug)-issue-\(issueNum)"
            if FileManager.default.fileExists(atPath: expectedPath) {
                try? await removeWorktreeFromGit(mainRepoPath: mainRepoPath, worktreePath: expectedPath)
                try? FileManager.default.removeItem(atPath: expectedPath)
                app?.logger.info("[Worktree] Cleaned up orphan worktree at \(expectedPath)")
            }
            return
        }

        // Remove from git
        try? await removeWorktreeFromGit(mainRepoPath: mainRepoPath, worktreePath: info.path)

        // Remove directory
        try? FileManager.default.removeItem(atPath: info.path)

        // Remove from tracking
        activeWorktrees.removeValue(forKey: issueKey)

        // Delete from Firebase
        try? await persistenceService.deleteWorktree(issueKey: issueKey)

        // Optionally delete the branch
        let deleteBranch = Process()
        deleteBranch.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        deleteBranch.arguments = ["branch", "-D", info.branch]
        deleteBranch.currentDirectoryURL = URL(fileURLWithPath: mainRepoPath)
        deleteBranch.standardOutput = FileHandle.nullDevice
        deleteBranch.standardError = FileHandle.nullDevice
        try? deleteBranch.run()
        deleteBranch.waitUntilExit()

        app?.logger.info("[Worktree] Removed worktree for \(issueKey)")
    }

    /// Remove worktree from git's tracking
    private func removeWorktreeFromGit(mainRepoPath: String, worktreePath: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["worktree", "remove", worktreePath, "--force"]
        process.currentDirectoryURL = URL(fileURLWithPath: mainRepoPath)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()
    }

    /// Cleanup old worktrees (older than specified days)
    public func cleanupOldWorktrees(olderThanDays: Int = 7) async {
        let cutoffDate = Date().addingTimeInterval(-Double(olderThanDays * 24 * 60 * 60))

        app?.logger.info("[Worktree] Running cleanup for worktrees older than \(olderThanDays) days")

        var removedCount = 0

        for (issueKey, info) in activeWorktrees {
            if info.createdAt < cutoffDate {
                // Get main repo path from RepoMap
                let repoMapPath = FileManager.default.currentDirectoryPath + "/repo_map.json"
                if let repoMap = try? RepoMap.load(from: repoMapPath),
                   let mainRepoPath = repoMap.getPath(for: info.repo) {
                    await removeWorktree(repo: info.repo, issueNum: info.issueNum, mainRepoPath: mainRepoPath)
                    removedCount += 1
                }
            }
        }

        // Also scan the directory for any orphaned worktrees
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: worktreeBaseDir) {
            for item in contents {
                let path = "\(worktreeBaseDir)/\(item)"
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }

                // Check if it's tracked
                let isTracked = activeWorktrees.values.contains { $0.path == path }
                if !isTracked {
                    // Check modification date
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                       let modDate = attrs[.modificationDate] as? Date,
                       modDate < cutoffDate {
                        try? FileManager.default.removeItem(atPath: path)
                        removedCount += 1
                        app?.logger.info("[Worktree] Removed orphan worktree: \(path)")
                    }
                }
            }
        }

        app?.logger.info("[Worktree] Cleanup complete, removed \(removedCount) worktrees")
    }

    /// Get info about a worktree for an issue
    public func getWorktreeInfo(repo: String, issueNum: Int) -> WorktreeInfo? {
        let issueKey = makeIssueKey(repo: repo, issueNum: issueNum)
        return activeWorktrees[issueKey]
    }

    /// List all active worktrees
    public func listWorktrees() -> [WorktreeInfo] {
        return Array(activeWorktrees.values)
    }

    /// Create a consistent issue key
    private func makeIssueKey(repo: String, issueNum: Int) -> String {
        let repoSlug = repo.split(separator: "/").last.map(String.init) ?? repo
        return "\(repoSlug)-\(issueNum)"
    }
}

/// Worktree-related errors
public enum WorktreeError: Error, LocalizedError {
    case creationFailed(String)
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .creationFailed(let msg): return "Worktree creation failed: \(msg)"
        case .notFound(let msg): return "Worktree not found: \(msg)"
        }
    }
}
