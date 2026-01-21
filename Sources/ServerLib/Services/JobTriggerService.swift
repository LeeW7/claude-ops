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

        // Get local path for repo
        guard let localPath = repoMap.getPath(for: repo) else {
            app.logger.warning("Received trigger for \(repo), but not found in repo_map.json")
            return false
        }

        app.logger.info("Triggering Job: \(jobId) with /\(command) in \(localPath)")

        // Create job
        let job = Job(
            repo: repo,
            issueNum: issueNum,
            issueTitle: issueTitle,
            command: command,
            localPath: localPath
        )

        do {
            // Save job to store
            try await app.firestoreService.saveJob(job)

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
