import Vapor
import Foundation

/// Result of attempting to trigger a job
public enum JobTriggerResult {
    case triggered(jobId: String)
    case skipped(reason: String)
    case failed(error: String)

    /// Whether the job was successfully triggered
    public var wasTriggered: Bool {
        if case .triggered = self { return true }
        return false
    }

    /// Human-readable description of the result
    public var description: String {
        switch self {
        case .triggered(let jobId):
            return "Job \(jobId) triggered successfully"
        case .skipped(let reason):
            return "Job skipped: \(reason)"
        case .failed(let error):
            return "Job failed: \(error)"
        }
    }
}

/// Centralized service for triggering jobs
/// Used by: IssueController, WebhookController, PollingJob
public struct JobTriggerService {
    private let app: Application

    public init(app: Application) {
        self.app = app
    }

    /// Trigger a job for an issue
    /// Returns a result indicating success, skipped, or failure with details
    @discardableResult
    public func triggerJob(
        repo: String,
        issueNum: Int,
        issueTitle: String,
        command: String,
        cmdLabel: String? = nil
    ) async -> JobTriggerResult {
        guard let repoMap = app.repoMap else {
            app.logger.warning("No repo map configured")
            return .failed(error: "Server not configured: repo_map.json is missing or invalid")
        }

        let repoSlug = repo.split(separator: "/").last.map(String.init) ?? repo
        let jobId = "\(repoSlug)-\(issueNum)-\(command)"

        // Check if job already exists and is active
        do {
            if try await app.persistenceService.jobExistsAndActive(id: jobId) {
                app.logger.info("Job \(jobId) already exists and is active, skipping")
                return .skipped(reason: "Job \(jobId) is already running or pending")
            }
        } catch {
            app.logger.error("Error checking job status: \(error)")
            return .failed(error: "Failed to check job status: \(error.localizedDescription)")
        }

        // Get local path for repo (main repo location)
        guard let mainRepoPath = repoMap.getPath(for: repo) else {
            app.logger.warning("Received trigger for \(repo), but not found in repo_map.json")
            return .failed(error: "Repository '\(repo)' is not configured. Add it to repo_map.json and restart the server.")
        }

        // Validate repository has required labels for command workflows
        do {
            let missingLabels = try await app.githubService.getMissingCommandLabels(repo: repo)
            if !missingLabels.isEmpty {
                let labelsStr = missingLabels.joined(separator: ", ")
                app.logger.warning("Repository \(repo) missing required labels: \(labelsStr)")
                // Auto-create missing labels instead of failing
                app.logger.info("Auto-creating missing labels on \(repo)...")
                let created = await app.githubService.ensureRequiredLabels(repo: repo)
                if !created.isEmpty {
                    app.logger.info("Created labels on \(repo): \(created.joined(separator: ", "))")
                }
            }
        } catch {
            app.logger.warning("Could not validate labels on \(repo): \(error.localizedDescription)")
            // Continue anyway - label check is advisory, not blocking
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
            return .failed(error: "Failed to create worktree: \(error.localizedDescription). Check disk space and git repository status.")
        }

        app.logger.info("Triggering Job: \(jobId) with /\(command) in \(workingPath)")

        // Ensure logs directory exists
        Job.ensureLogsDirectory()

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
            try await app.persistenceService.saveJob(job)

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
                do {
                    try await app.githubService.removeLabel(repo: repo, number: issueNum, label: cmdLabel)
                } catch {
                    // Log but don't fail - label removal is not critical
                    app.logger.warning("Failed to remove label \(cmdLabel) from \(repo)#\(issueNum): \(error.localizedDescription)")
                }
            }

            // Start the job in background
            Task {
                await app.claudeService.runJob(job)
            }

            return .triggered(jobId: jobId)
        } catch {
            app.logger.error("Failed to trigger job \(jobId): \(error)")
            return .failed(error: "Failed to save job: \(error.localizedDescription)")
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
