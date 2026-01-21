import Vapor

/// Controller for job-related endpoints
struct JobController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        // Job listing
        routes.get("jobs", use: listJobs)
        routes.get("api", "status", use: listJobs)  // Alias

        // Job logs
        routes.get("api", "logs", ":id", use: getJobLogs)

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
