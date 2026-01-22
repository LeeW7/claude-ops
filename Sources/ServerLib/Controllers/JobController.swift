import Vapor

/// Controller for job-related endpoints
struct JobController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        // Job listing
        routes.get("jobs", use: listJobs)
        routes.get("api", "status", use: listJobs)  // Alias

        // Delta sync - get jobs modified since timestamp
        routes.get("jobs", "sync", use: syncJobs)

        // Job logs
        routes.get("api", "logs", ":id", use: getJobLogs)

        // Job trigger (simple endpoint for Flutter direct calls)
        routes.post("jobs", "trigger", use: triggerJob)

        // Job actions
        routes.post("jobs", ":id", "approve", use: approveJob)
        routes.post("jobs", ":id", "reject", use: rejectJob)

        // Legacy endpoints (for backward compatibility)
        routes.post("approve", use: approveLegacy)
        routes.post("reject", use: rejectLegacy)
    }

    /// List all jobs with last 50 log lines
    @Sendable
    func listJobs(req: Request) async throws -> [JobResponse] {
        let jobs = try await req.application.firestoreService.getAllJobs()

        var responses: [JobResponse] = []
        for job in jobs {
            let logs = await req.application.claudeService.readLogTail(path: job.logPath, lines: 50)
            responses.append(JobResponse(from: job, logs: logs))
        }
        return responses
    }

    /// Delta sync - returns only jobs modified since a given timestamp
    /// Usage: GET /jobs/sync?since=1234567890 (Unix timestamp in seconds)
    @Sendable
    func syncJobs(req: Request) async throws -> SyncResponse {
        let since: Int? = req.query["since"]
        let allJobs = try await req.application.firestoreService.getAllJobs()

        // Filter to jobs updated since the given timestamp
        var modifiedJobs: [JobResponse] = []

        if let sinceTimestamp = since {
            let sinceDate = Date(timeIntervalSince1970: Double(sinceTimestamp))

            for job in allJobs where job.updatedAt > sinceDate {
                // Don't include logs for sync - just job metadata
                modifiedJobs.append(JobResponse(from: job, logs: nil))
            }
        } else {
            // No timestamp provided - return all jobs (no logs)
            modifiedJobs = allJobs.map { JobResponse(from: $0, logs: nil) }
        }

        return SyncResponse(
            jobs: modifiedJobs,
            syncTimestamp: Int(Date().timeIntervalSince1970),
            totalJobs: allJobs.count
        )
    }

    /// Trigger a new job - simple endpoint for Flutter to call directly
    /// Returns immediately, job runs in background
    @Sendable
    func triggerJob(req: Request) async throws -> Response {
        let body = try req.content.decode(TriggerJobRequest.self)

        req.logger.info("POST /jobs/trigger: repo=\(body.repo) issueNum=\(body.issueNum) command=\(body.command)")

        guard let repoMap = req.application.repoMap else {
            throw Abort(.internalServerError, reason: "Repo map not configured")
        }

        guard repoMap.getPath(for: body.repo) != nil else {
            throw Abort(.badRequest, reason: "Repository \(body.repo) not found in repo_map.json")
        }

        // Build job ID to check if already exists
        let repoSlug = body.repo.split(separator: "/").last.map(String.init) ?? body.repo
        let jobId = "\(repoSlug)-\(body.issueNum)-\(body.command)"

        // Check if job already exists and is active BEFORE returning success
        do {
            if try await req.application.firestoreService.jobExistsAndActive(id: jobId) {
                req.logger.info("Job \(jobId) already exists and is active, rejecting trigger")
                throw Abort(.conflict, reason: "Job \(jobId) is already running or pending")
            }
        } catch let error as Abort {
            throw error
        } catch {
            req.logger.error("Error checking job status: \(error)")
            throw Abort(.internalServerError, reason: "Failed to check job status: \(error.localizedDescription)")
        }

        // Now trigger job in background - we know it doesn't already exist
        let app = req.application
        Task {
            await app.jobTriggerService.triggerJob(
                repo: body.repo,
                issueNum: body.issueNum,
                issueTitle: body.issueTitle,
                command: body.command,
                cmdLabel: body.cmdLabel
            )
        }

        let response: [String: Any] = [
            "status": "triggered",
            "message": "Starting \(body.command) job for \(body.repo)#\(body.issueNum)"
        ]

        let data = try JSONSerialization.data(withJSONObject: response)
        return Response(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: .init(data: data)
        )
    }

    /// Get logs for a specific job
    @Sendable
    func getJobLogs(req: Request) async throws -> LogResponse {
        guard let requestId = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Job ID required")
        }

        // Try exact match first, then fuzzy match
        guard let job = try await req.application.firestoreService.getJobFuzzy(id: requestId) else {
            throw Abort(.notFound, reason: "Job not found")
        }

        let logs = await req.application.claudeService.readLog(path: job.logPath)
        return LogResponse(from: job, logs: logs)
    }

    /// Approve a waiting job
    @Sendable
    func approveJob(req: Request) async throws -> Response {
        guard let jobId = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Job ID required")
        }

        return try await processApproval(req: req, jobId: jobId)
    }

    /// Reject/cancel a job
    @Sendable
    func rejectJob(req: Request) async throws -> Response {
        guard let jobId = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Job ID required")
        }

        return try await processRejection(req: req, jobId: jobId)
    }

    /// Legacy approve endpoint
    @Sendable
    func approveLegacy(req: Request) async throws -> Response {
        let body = try req.content.decode(JobActionRequest.self)
        let jobId = body.job_id ?? body.issueId ?? body.id ?? ""

        guard !jobId.isEmpty else {
            throw Abort(.badRequest, reason: "Job ID required")
        }

        return try await processApproval(req: req, jobId: jobId)
    }

    /// Legacy reject endpoint
    @Sendable
    func rejectLegacy(req: Request) async throws -> Response {
        let body = try req.content.decode(JobActionRequest.self)
        let jobId = body.job_id ?? body.issueId ?? body.id ?? ""

        guard !jobId.isEmpty else {
            throw Abort(.badRequest, reason: "Job ID required")
        }

        return try await processRejection(req: req, jobId: jobId)
    }

    /// Process job approval
    private func processApproval(req: Request, jobId: String) async throws -> Response {
        guard let job = try await req.application.firestoreService.getJobFuzzy(id: jobId) else {
            throw Abort(.notFound, reason: "Job not found")
        }

        guard job.status == .waitingApproval else {
            throw Abort(.badRequest, reason: "Job not waiting for approval")
        }

        try await req.application.firestoreService.updateJobStatus(id: job.id, status: .approvedResume)

        return Response(
            status: .ok,
            body: .init(string: #"{"status":"approved"}"#)
        )
    }

    /// Process job rejection
    private func processRejection(req: Request, jobId: String) async throws -> Response {
        guard let job = try await req.application.firestoreService.getJobFuzzy(id: jobId) else {
            throw Abort(.notFound, reason: "Job not found")
        }

        guard job.status == .waitingApproval || job.status == .running || job.status == .pending else {
            throw Abort(.badRequest, reason: "Job not in a state that can be rejected")
        }

        // Update status to rejected
        try await req.application.firestoreService.updateJobStatus(id: job.id, status: .rejected)

        // Set in-memory cancellation flag (checked by running job loop)
        await req.application.jobCancellationManager.cancel(job.id)

        // Terminate process if running
        await req.application.claudeService.terminateProcess(job.id)

        // Close the GitHub issue with a comment
        let comment = "Job cancelled via Agent Command Center."
        try? await req.application.githubService.closeIssue(
            repo: job.repo,
            number: job.issueNum,
            comment: comment
        )

        // Send notification
        await req.application.pushNotificationService.send(
            title: "Job Rejected",
            body: "\(job.id) was cancelled"
        )

        return Response(
            status: .ok,
            body: .init(string: #"{"status":"rejected"}"#)
        )
    }
}

/// Request body for job actions (legacy support)
struct JobActionRequest: Content {
    let job_id: String?
    let issueId: String?
    let id: String?
}

/// Request body for triggering a job
struct TriggerJobRequest: Content {
    let repo: String
    let issueNum: Int
    let issueTitle: String
    let command: String
    let cmdLabel: String?
}
