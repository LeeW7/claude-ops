import Vapor

/// Controller for hidden issues sync endpoints
struct HiddenIssueController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let api = routes.grouped("api", "hidden-issues")

        api.get(use: getAllHiddenIssues)
        api.post(use: hideIssue)
        api.delete(":issueKey", use: unhideIssue)
    }

    /// GET /api/hidden-issues - Return all hidden issues
    @Sendable
    func getAllHiddenIssues(req: Request) async throws -> [HiddenIssue] {
        try await req.application.persistenceService.getAllHiddenIssues()
    }

    /// POST /api/hidden-issues - Add/update a hidden issue (upsert)
    @Sendable
    func hideIssue(req: Request) async throws -> HiddenIssue {
        let body = try req.content.decode(HideIssueRequest.self)

        let issue = HiddenIssue(
            issueKey: body.issueKey,
            repo: body.repo,
            issueNum: body.issueNum,
            issueTitle: body.issueTitle,
            hiddenAt: Int64(Date().timeIntervalSince1970 * 1000),
            reason: body.reason ?? .user
        )

        try await req.application.persistenceService.saveHiddenIssue(issue)

        req.logger.info("[HiddenIssues] Hidden issue: \(issue.issueKey)")

        return issue
    }

    /// DELETE /api/hidden-issues/:issueKey - Remove a hidden issue
    @Sendable
    func unhideIssue(req: Request) async throws -> HTTPStatus {
        // issueKey is URL-encoded since it contains / and #
        guard let issueKey = req.parameters.get("issueKey")?.removingPercentEncoding else {
            throw Abort(.badRequest, reason: "Missing or invalid issueKey parameter")
        }

        try await req.application.persistenceService.deleteHiddenIssue(issueKey: issueKey)

        req.logger.info("[HiddenIssues] Unhidden issue: \(issueKey)")

        // Return 204 for idempotent delete (even if not found)
        return .noContent
    }
}
