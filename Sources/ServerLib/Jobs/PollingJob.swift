import Vapor
import Foundation

/// Background job that polls GitHub for labeled issues
/// Acts as a fallback when webhooks fail
actor PollingJob {
    private weak var app: Application?
    private let pollInterval: TimeInterval = 60 // seconds
    private var pollCount: Int = 0
    private var sessionCleanupCount: Int = 0
    private let worktreeCleanupInterval: Int = 60 // Run worktree cleanup every hour (60 polls * 60 seconds)
    private let sessionCleanupInterval: Int = 360 // Run session cleanup every 6 hours (360 polls * 60 seconds)

    /// Supported command labels to poll for
    private let cmdLabels = [
        "cmd:plan-headless",
        "cmd:implement-headless",
        "cmd:retrospective-headless",
        "cmd:revise-headless"
    ]

    init(app: Application) {
        self.app = app
    }

    /// Start the polling loop
    func start() async {
        guard let app = app else { return }

        app.logger.info("Starting GitHub polling job (interval: \(Int(pollInterval))s)")

        // Mark any interrupted jobs on startup
        do {
            try await app.persistenceService.markInterruptedJobs()
        } catch {
            app.logger.error("Failed to mark interrupted jobs: \(error)")
        }

        // Run initial worktree cleanup on startup
        await app.worktreeService.cleanupOldWorktrees(olderThanDays: 7)

        // Run initial quick session cleanup on startup
        await app.quickSessionService.cleanupExpiredSessions()

        app.logger.info("[Polling] Initialization complete, entering main polling loop")

        while !Task.isCancelled {
            await pollAllRepos()
            pollCount += 1

            // Run worktree cleanup every hour (60 polls * 60 seconds = 1 hour)
            if pollCount >= worktreeCleanupInterval {
                pollCount = 0
                await app.worktreeService.cleanupOldWorktrees(olderThanDays: 7)
            }

            // Run quick session cleanup every 6 hours
            sessionCleanupCount += 1
            if sessionCleanupCount >= sessionCleanupInterval {
                sessionCleanupCount = 0
                await app.quickSessionService.cleanupExpiredSessions()
            }

            do {
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            } catch {
                break // Task was cancelled
            }
        }
    }

    /// Poll all repositories for labeled issues
    private func pollAllRepos() async {
        guard let app = app, let repoMap = app.repoMap else {
            app?.logger.warning("[Polling] No app or repoMap available, skipping poll cycle")
            return
        }

        let repos = repoMap.allRepositories()
        app.logger.debug("[Polling] Checking \(repos.count) repositories for cmd: labels")

        for repo in repos {
            for cmdLabel in cmdLabels {
                await checkRepoForLabel(repo: repo.fullName, cmdLabel: cmdLabel)
            }
        }
    }

    /// Check a specific repo for issues with a given label
    private func checkRepoForLabel(repo: String, cmdLabel: String) async {
        guard let app = app else { return }

        do {
            let issues = try await app.githubService.listIssuesWithLabel(repo: repo, label: cmdLabel)

            if !issues.isEmpty {
                app.logger.info("[Polling] Found \(issues.count) issue(s) with '\(cmdLabel)' in \(repo)")
            }

            for issue in issues {
                guard let number = issue["number"] as? Int,
                      let title = issue["title"] as? String else {
                    app.logger.warning("[Polling] Issue in \(repo) missing number or title, skipping")
                    continue
                }

                let commandName = cmdLabel.replacingOccurrences(of: "cmd:", with: "")
                app.logger.info("[Polling] Triggering \(commandName) for \(repo)#\(number)")

                // Use shared job trigger service
                let result = await app.jobTriggerService.triggerJob(
                    repo: repo,
                    issueNum: number,
                    issueTitle: title,
                    command: commandName,
                    cmdLabel: cmdLabel
                )

                switch result {
                case .triggered(let jobId):
                    app.logger.info("[Polling] Successfully triggered job: \(jobId)")
                case .skipped(let reason):
                    app.logger.debug("[Polling] Job skipped for \(repo)#\(number): \(reason)")
                case .failed(let error):
                    app.logger.error("[Polling] Job trigger failed for \(repo)#\(number): \(error)")
                }
            }
        } catch {
            // Log the error instead of silently swallowing it
            app.logger.error("[Polling] Failed to check \(repo) for '\(cmdLabel)': \(error.localizedDescription)")
        }
    }
}
