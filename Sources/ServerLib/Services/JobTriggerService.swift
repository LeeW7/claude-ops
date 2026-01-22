import Vapor
import Foundation

/// Centralized service for triggering jobs
/// Used by: IssueController, WebhookController, PollingJob
public struct JobTriggerService {
    private let app: Application

    public init(app: Application) {
        self.app = app
    }

    /// Trigger a job for an issue
    /// Returns true if job was triggered, false if skipped (already exists)
    @discardableResult
    public func triggerJob(
        repo: String,
        issueNum: Int,
        issueTitle: String,
        command: String,
        cmdLabel: String? = nil
    ) async -> Bool {
        guard let repoMap = app.repoMap else {
            app.logger.warning("No repo map configured")
            return false
        }

        let repoSlug = repo.split(separator: "/").last.map(String.init) ?? repo
        let jobId = "\(repoSlug)-\(issueNum)-\(command)"

        // Check if job already exists and is active
        do {
            if try await app.firestoreService.jobExistsAndActive(id: jobId) {
                app.logger.info("Job \(jobId) already exists and is active, skipping")
                return false
            }
        } catch {
            app.logger.error("Error checking job status: \(error)")
            return false
        }

        // Get local path for repo (main repo location)
        guard let mainRepoPath = repoMap.getPath(for: repo) else {
            app.logger.warning("Received trigger for \(repo), but not found in repo_map.json")
            return false
        }

        // Get or create worktree for this issue (enables parallel jobs)
        let workingPath: String
        do {
            workingPath = try await app.worktreeService.getOrCreateWorktree(
                repo: repo,
                issueNum: issueNum,
                mainRepoPath: mainRepoPath
            )
        } catch {
            app.logger.error("Failed to create worktree for \(jobId): \(error)")
            // Fall back to main repo path if worktree fails
            workingPath = mainRepoPath
            app.logger.warning("Falling back to main repo path: \(mainRepoPath)")
        }

        app.logger.info("Triggering Job: \(jobId) with /\(command) in \(workingPath)")

        // Create job with worktree path
        let job = Job(
            repo: repo,
            issueNum: issueNum,
            issueTitle: issueTitle,
            command: command,
            localPath: workingPath
        )

        do {
            // Save job to store
            try await app.firestoreService.saveJob(job)

            // Broadcast job created event to all global WebSocket subscribers
            let jobEvent = JobEvent(
                type: .jobCreated,
                job: JobEventData(
                    id: job.id,
                    repo: job.repo,
                    issueNum: job.issueNum,
                    issueTitle: job.issueTitle,
                    command: job.command,
                    status: job.status.rawValue
                )
            )
            app.webSocketManager.broadcastGlobal(jobEvent)

            // Remove the cmd label from the issue (if provided)
            if let cmdLabel = cmdLabel {
                try? await app.githubService.removeLabel(repo: repo, number: issueNum, label: cmdLabel)
            }

            // Start the job in background
            Task {
                await app.claudeService.runJob(job)
            }

            return true
        } catch {
            app.logger.error("Failed to trigger job \(jobId): \(error)")
            return false
        }
    }
}

// MARK: - Application Extension

extension Application {
    private struct JobTriggerServiceKey: StorageKey {
        typealias Value = JobTriggerService
    }

    public var jobTriggerService: JobTriggerService {
        get {
            if let existing = storage[JobTriggerServiceKey.self] {
                return existing
            }
            let service = JobTriggerService(app: self)
            storage[JobTriggerServiceKey.self] = service
            return service
        }
        set {
            storage[JobTriggerServiceKey.self] = newValue
        }
    }
}
