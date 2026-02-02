import Vapor

/// Handler for CI/CD callbacks to update preview and test status
struct PreviewCallbackHandler: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api")

        // Callback endpoints for CI/CD
        api.post("preview-callback", use: handlePreviewCallback)
        api.post("test-callback", use: handleTestCallback)
    }

    /// Handle preview deployment status update from CI
    @Sendable
    func handlePreviewCallback(req: Request) async throws -> CallbackResponse {
        // Validate callback secret
        let providedSecret = req.headers.first(name: "X-Callback-Secret")
        guard req.application.previewService.validateCallbackSecret(providedSecret) else {
            throw Abort(.unauthorized, reason: "Invalid callback secret")
        }

        let payload = try req.content.decode(PreviewCallbackPayload.self)

        req.logger.info("[PreviewCallback] Received status update for \(payload.issueKey): \(payload.status)")

        // Parse issue key to get repo and issue number
        let (repo, issueNum) = try parseIssueKey(payload.issueKey)

        // Get existing deployment or create new one
        var deployment: PreviewDeployment
        if let existing = try await req.application.persistenceService.getPreviewDeployment(repo: repo, issueNum: issueNum) {
            // Update existing deployment
            let status = PreviewStatus(rawValue: payload.status) ?? .pending
            deployment = existing.updated(
                status: status,
                previewUrl: payload.previewUrl,
                logsUrl: payload.logsUrl,
                errorMessage: payload.errorMessage,
                expiresAt: payload.expiresAt
            )
        } else {
            // Create new deployment from callback (shouldn't normally happen)
            let status = PreviewStatus(rawValue: payload.status) ?? .pending
            deployment = PreviewDeployment(
                issueKey: payload.issueKey,
                repo: repo,
                issueNum: issueNum,
                projectType: .unknown,
                status: status,
                previewUrl: payload.previewUrl,
                logsUrl: payload.logsUrl,
                errorMessage: payload.errorMessage
            )
        }

        // Save updated deployment
        try await req.application.persistenceService.savePreviewDeployment(deployment)

        // Broadcast WebSocket update
        req.application.webSocketManager.broadcastPreviewUpdate(deployment)

        req.logger.info("[PreviewCallback] Updated deployment for \(payload.issueKey) to status: \(payload.status)")

        return CallbackResponse(
            status: "accepted",
            message: "Preview status updated"
        )
    }

    /// Handle test results callback from CI
    @Sendable
    func handleTestCallback(req: Request) async throws -> CallbackResponse {
        // Validate callback secret
        let providedSecret = req.headers.first(name: "X-Callback-Secret")
        guard req.application.previewService.validateCallbackSecret(providedSecret) else {
            throw Abort(.unauthorized, reason: "Invalid callback secret")
        }

        let payload = try req.content.decode(TestResultCallbackPayload.self)

        req.logger.info("[TestCallback] Received test results for \(payload.issueKey): \(payload.passedCount) passed, \(payload.failedCount) failed")

        // Parse issue key to get repo and issue number
        let (repo, issueNum) = try parseIssueKey(payload.issueKey)

        // Convert failures from payload
        let failures = payload.failures?.map { $0.toTestFailure() } ?? []

        // Create test result
        let testResult = TestResult(
            issueKey: payload.issueKey,
            repo: repo,
            issueNum: issueNum,
            testSuite: payload.testSuite,
            passedCount: payload.passedCount,
            failedCount: payload.failedCount,
            skippedCount: payload.skippedCount,
            duration: payload.duration,
            coverage: payload.coverage,
            failures: failures,
            commitSha: payload.commitSha
        )

        // Save test result
        try await req.application.persistenceService.saveTestResult(testResult)

        // Broadcast WebSocket update
        req.application.webSocketManager.broadcastTestResultsUpdate(testResult)

        req.logger.info("[TestCallback] Saved test results for \(payload.issueKey)")

        return CallbackResponse(
            status: "accepted",
            message: "Test results saved"
        )
    }

    /// Parse issue key (format: "owner/repo#123") into repo and issue number
    private func parseIssueKey(_ issueKey: String) throws -> (String, Int) {
        let parts = issueKey.split(separator: "#")
        guard parts.count == 2,
              let issueNum = Int(parts[1]) else {
            throw Abort(.badRequest, reason: "Invalid issue key format. Expected 'owner/repo#123'")
        }
        return (String(parts[0]), issueNum)
    }
}
