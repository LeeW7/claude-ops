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

        // Job decisions
        routes.get("jobs", ":id", "decisions", use: getJobDecisions)

        // Legacy endpoints (for backward compatibility)
        routes.post("approve", use: approveLegacy)
        routes.post("reject", use: rejectLegacy)
    }

    /// List all jobs with last 50 log lines, decisions, and confidence
    @Sendable
    func listJobs(req: Request) async throws -> [JobResponse] {
        let jobs = try await req.application.persistenceService.getAllJobs()

        var responses: [JobResponse] = []
        for job in jobs {
            let logs = await req.application.claudeService.readLogTail(path: job.logPath, lines: 50)
            var decisions = try? await req.application.persistenceService.getDecisionsForJob(jobId: job.id)
            var confidence = try? await req.application.persistenceService.getConfidenceForJob(jobId: job.id)

            // Extract on-demand for completed jobs without decisions or confidence
            if ((decisions == nil || decisions?.isEmpty == true) || confidence == nil) && job.status == .completed {
                let fullLogs = await req.application.claudeService.readLog(path: job.logPath)

                // Extract decisions if needed
                if decisions == nil || decisions?.isEmpty == true {
                    let extracted = DecisionExtractor.extractDecisions(from: fullLogs, jobId: job.id)
                    if !extracted.isEmpty {
                        try? await req.application.persistenceService.saveDecisions(extracted)
                        decisions = extracted
                    }
                }

                // Extract confidence if needed
                if confidence == nil {
                    req.logger.debug("[\(job.id)] Attempting confidence extraction from \(fullLogs.count) chars")
                    if let extracted = DecisionExtractor.extractConfidence(from: fullLogs, jobId: job.id) {
                        try? await req.application.persistenceService.saveConfidence(extracted)
                        confidence = extracted
                        req.logger.info("[\(job.id)] Extracted confidence score: \(extracted.score)")
                    } else {
                        req.logger.debug("[\(job.id)] No confidence block found in logs")
                    }
                }
            }

            responses.append(JobResponse(from: job, logs: logs, decisions: decisions, confidence: confidence))
        }
        return responses
    }

    /// Delta sync - returns only jobs modified since a given timestamp
    /// Usage: GET /jobs/sync?since=1234567890 (Unix timestamp in seconds)
    @Sendable
    func syncJobs(req: Request) async throws -> SyncResponse {
        let since: Int? = req.query["since"]
        let allJobs = try await req.application.persistenceService.getAllJobs()

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

        // Trigger the job - JobTriggerService handles all validation
        let result = await req.application.jobTriggerService.triggerJob(
            repo: body.repo,
            issueNum: body.issueNum,
            issueTitle: body.issueTitle,
            command: body.command,
            cmdLabel: body.cmdLabel
        )

        switch result {
        case .triggered(let jobId):
            let response: [String: Any] = [
                "status": "triggered",
                "jobId": jobId,
                "message": "Starting \(body.command) job for \(body.repo)#\(body.issueNum)"
            ]
            let data = try JSONSerialization.data(withJSONObject: response)
            return Response(
                status: .ok,
                headers: ["Content-Type": "application/json"],
                body: .init(data: data)
            )

        case .skipped(let reason):
            throw Abort(.conflict, reason: reason)

        case .failed(let error):
            throw Abort(.internalServerError, reason: error)
        }
    }

    /// Get logs for a specific job
    @Sendable
    func getJobLogs(req: Request) async throws -> LogResponse {
        guard let requestId = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Job ID required")
        }

        // Try exact match first, then fuzzy match
        guard let job = try await req.application.persistenceService.getJobFuzzy(id: requestId) else {
            throw Abort(.notFound, reason: "Job not found")
        }

        let logs = await req.application.claudeService.readLog(path: job.logPath)

        // Get existing decisions and confidence, or extract them on-the-fly for completed jobs
        var decisions = try? await req.application.persistenceService.getDecisionsForJob(jobId: job.id)
        var confidence = try? await req.application.persistenceService.getConfidenceForJob(jobId: job.id)

        // If no decisions or confidence exist and job is completed, extract them now
        if ((decisions == nil || decisions?.isEmpty == true) || confidence == nil) && job.status == .completed {
            // Extract decisions if needed
            if decisions == nil || decisions?.isEmpty == true {
                let extracted = DecisionExtractor.extractDecisions(from: logs, jobId: job.id)
                if !extracted.isEmpty {
                    try? await req.application.persistenceService.saveDecisions(extracted)
                    decisions = extracted
                    req.logger.info("[\(job.id)] Extracted \(extracted.count) decisions on-demand")
                }
            }

            // Extract confidence if needed
            if confidence == nil {
                if let extracted = DecisionExtractor.extractConfidence(from: logs, jobId: job.id) {
                    try? await req.application.persistenceService.saveConfidence(extracted)
                    confidence = extracted
                    req.logger.info("[\(job.id)] Extracted confidence score: \(extracted.score)")
                }
            }
        }

        return LogResponse(from: job, logs: logs, decisions: decisions, confidence: confidence)
    }

    /// Get decisions extracted from a job's output
    @Sendable
    func getJobDecisions(req: Request) async throws -> [JobDecision] {
        guard let requestId = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "Job ID required")
        }

        // Try exact match first, then fuzzy match
        guard let job = try await req.application.persistenceService.getJobFuzzy(id: requestId) else {
            throw Abort(.notFound, reason: "Job not found")
        }

        return try await req.application.persistenceService.getDecisionsForJob(jobId: job.id)
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
        guard let job = try await req.application.persistenceService.getJobFuzzy(id: jobId) else {
            throw Abort(.notFound, reason: "Job not found")
        }

        guard job.status == .waitingApproval else {
            throw Abort(.badRequest, reason: "Job not waiting for approval")
        }

        try await req.application.persistenceService.updateJobStatus(id: job.id, status: JobStatus.approvedResume, error: nil as String?)

        return Response(
            status: .ok,
            body: .init(string: #"{"status":"approved"}"#)
        )
    }

    /// Process job rejection
    private func processRejection(req: Request, jobId: String) async throws -> Response {
        guard let job = try await req.application.persistenceService.getJobFuzzy(id: jobId) else {
            throw Abort(.notFound, reason: "Job not found")
        }

        guard job.status == .waitingApproval || job.status == .running || job.status == .pending else {
            throw Abort(.badRequest, reason: "Job not in a state that can be rejected")
        }

        // Update status to rejected
        try await req.application.persistenceService.updateJobStatus(id: job.id, status: JobStatus.rejected, error: nil as String?)

        // Set in-memory cancellation flag (checked by running job loop)
        await req.application.jobCancellationManager.cancel(job.id)

        // Terminate process if running
        await req.application.claudeService.terminateProcess(job.id)

        // Close the GitHub issue with a comment
        let comment = "Job cancelled via Agent Command Center."
        do {
            try await req.application.githubService.closeIssue(
                repo: job.repo,
                number: job.issueNum,
                comment: comment
            )
        } catch {
            req.logger.warning("Failed to close issue \(job.repo)#\(job.issueNum): \(error.localizedDescription)")
        }

        // Send notification
        let commandName = job.command.replacingOccurrences(of: "-headless", with: "").capitalized
        await req.application.pushNotificationService.send(
            title: "\(commandName) Cancelled - #\(job.issueNum)",
            body: String(job.issueTitle.prefix(50))
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
