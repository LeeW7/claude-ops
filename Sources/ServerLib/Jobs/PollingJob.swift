import Vapor
import Foundation

/// Background job that polls GitHub for labeled issues
/// Acts as a fallback when webhooks fail
actor PollingJob {
    private weak var app: Application?
    private let pollInterval: TimeInterval = 60 // seconds

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
            try await app.firestoreService.markInterruptedJobs()
        } catch {
            app.logger.error("Failed to mark interrupted jobs: \(error)")
        }

        while !Task.isCancelled {
            await pollAllRepos()

            do {
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            } catch {
                break // Task was cancelled
            }
        }
    }

    /// Poll all repositories for labeled issues
    private func pollAllRepos() async {
        guard let app = app, let repoMap = app.repoMap else { return }

        let repos = repoMap.allRepositories()

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

            for issue in issues {
                guard let number = issue["number"] as? Int,
                      let title = issue["title"] as? String else {
                    continue
                }

                let commandName = cmdLabel.replacingOccurrences(of: "cmd:", with: "")

                // Use shared job trigger service
                await app.jobTriggerService.triggerJob(
                    repo: repo,
                    issueNum: number,
                    issueTitle: title,
                    command: commandName,
                    cmdLabel: cmdLabel
                )
            }
        } catch {
            // Silently fail - polling is best effort
        }
    }
}
