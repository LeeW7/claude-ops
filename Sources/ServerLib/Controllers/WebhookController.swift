import Vapor

/// Controller for GitHub webhook handling
struct WebhookController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("webhook", use: handleWebhook)
    }

    /// Handle incoming GitHub webhook
    @Sendable
    func handleWebhook(req: Request) async throws -> Response {
        req.logger.info("[Webhook] Received POST /webhook")

        // Parse webhook payload
        guard let payload = try? req.content.decode(WebhookPayload.self) else {
            req.logger.warning("[Webhook] Failed to decode payload - invalid JSON structure")
            return Response(status: .badRequest, body: .init(string: "Invalid payload"))
        }

        let action = payload.action ?? ""

        // Check if this is a PR merge event
        if let pullRequest = payload.pull_request,
           let repository = payload.repository {
            return await handlePullRequestEvent(req: req, pullRequest: pullRequest, repository: repository, action: action)
        }

        // Check if this is an issue event
        guard let issue = payload.issue,
              let repository = payload.repository else {
            req.logger.debug("[Webhook] Ignored - not an issue or PR event (action: \(action))")
            return Response(status: .ok, body: .init(string: "Ignored"))
        }

        return await handleIssueEvent(req: req, issue: issue, repository: repository, action: action)
    }

    /// Handle issue events (labeled, opened) - triggers jobs
    private func handleIssueEvent(req: Request, issue: WebhookIssue, repository: WebhookRepository, action: String) async -> Response {
        let repoName = repository.full_name
        let labels = issue.labels?.map { $0.name } ?? []

        req.logger.info("[Webhook] Issue event: \(repoName)#\(issue.number) action=\(action) labels=\(labels)")

        // Find any cmd: label
        guard let cmdLabel = labels.first(where: { $0.hasPrefix("cmd:") }) else {
            req.logger.debug("[Webhook] Ignored - no cmd: label found on \(repoName)#\(issue.number)")
            return Response(status: .ok, body: .init(string: "Ignored"))
        }

        guard action == "labeled" || action == "opened" else {
            req.logger.debug("[Webhook] Ignored - action '\(action)' not triggerable (need 'labeled' or 'opened')")
            return Response(status: .ok, body: .init(string: "Ignored"))
        }

        let commandName = cmdLabel.replacingOccurrences(of: "cmd:", with: "")
        req.logger.info("[Webhook] Triggering job: \(repoName)#\(issue.number) command=\(commandName)")

        // Trigger the job using shared service
        let result = await req.application.jobTriggerService.triggerJob(
            repo: repoName,
            issueNum: issue.number,
            issueTitle: issue.title,
            command: commandName,
            cmdLabel: cmdLabel
        )

        switch result {
        case .triggered(let jobId):
            req.logger.info("[Webhook] Job triggered successfully: \(jobId)")
            return Response(status: .ok, body: .init(string: "Triggered: \(jobId)"))

        case .skipped(let reason):
            req.logger.info("[Webhook] Job skipped for \(repoName)#\(issue.number): \(reason)")
            return Response(status: .ok, body: .init(string: "Skipped: \(reason)"))

        case .failed(let error):
            req.logger.error("[Webhook] Job trigger failed for \(repoName)#\(issue.number): \(error)")
            // Return 200 to GitHub (so it doesn't retry) but include error in body
            return Response(status: .ok, body: .init(string: "Failed: \(error)"))
        }
    }

    /// Handle pull request events (closed + merged) - cleans up worktrees
    private func handlePullRequestEvent(req: Request, pullRequest: WebhookPullRequest, repository: WebhookRepository, action: String) async -> Response {
        let repoName = repository.full_name

        // Only handle merged PRs (action=closed + merged=true)
        guard action == "closed", pullRequest.merged == true else {
            req.logger.debug("[Webhook] PR event ignored - not a merge (action=\(action), merged=\(pullRequest.merged ?? false))")
            return Response(status: .ok, body: .init(string: "Ignored"))
        }

        req.logger.info("[Webhook] PR merged: \(repoName)#\(pullRequest.number) - \(pullRequest.title)")

        // Extract linked issue numbers from PR body
        let linkedIssues = extractLinkedIssues(from: pullRequest.body)

        if linkedIssues.isEmpty {
            req.logger.debug("[Webhook] No linked issues found in PR body")
            return Response(status: .ok, body: .init(string: "Merged - no linked issues"))
        }

        req.logger.info("[Webhook] Found linked issues: \(linkedIssues)")

        // Get the main repo path from repoMap
        guard let repoMap = req.application.repoMap,
              let repoInfo = repoMap.allRepositories().first(where: { $0.fullName == repoName }) else {
            req.logger.warning("[Webhook] Repo \(repoName) not found in repo_map, cannot cleanup worktrees")
            return Response(status: .ok, body: .init(string: "Merged - repo not in map"))
        }

        // Clean up worktrees for each linked issue
        let worktreeService = req.application.worktreeService
        for issueNum in linkedIssues {
            await worktreeService.removeWorktree(repo: repoName, issueNum: issueNum, mainRepoPath: repoInfo.path)
            req.logger.info("[Webhook] Cleaned up worktree for \(repoName)#\(issueNum)")
        }

        return Response(status: .ok, body: .init(string: "Merged - cleaned up \(linkedIssues.count) worktree(s)"))
    }

    /// Extract issue numbers from PR body text
    /// Looks for patterns like: Fixes #123, Closes #456, Resolves #789, etc.
    private func extractLinkedIssues(from body: String?) -> [Int] {
        guard let body = body else { return [] }

        // Pattern matches: Fixes #123, Closes #456, Resolves #789, fixes #123, etc.
        // Also matches: Fix #123, Close #456, Resolve #789
        let pattern = #"(?i)(?:fix(?:es)?|close[sd]?|resolve[sd]?)\s+#(\d+)"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(body.startIndex..., in: body)
        let matches = regex.matches(in: body, range: range)

        return matches.compactMap { match -> Int? in
            guard let issueRange = Range(match.range(at: 1), in: body) else { return nil }
            return Int(body[issueRange])
        }
    }
}

// MARK: - Webhook Payload Models

struct WebhookPayload: Content {
    let action: String?
    let issue: WebhookIssue?
    let pull_request: WebhookPullRequest?
    let repository: WebhookRepository?
}

struct WebhookIssue: Content {
    let number: Int
    let title: String
    let labels: [WebhookLabel]?
}

struct WebhookPullRequest: Content {
    let number: Int
    let title: String
    let body: String?
    let merged: Bool?
    let head: WebhookPullRequestHead?
}

struct WebhookPullRequestHead: Content {
    let ref: String  // branch name
}

struct WebhookLabel: Content {
    let name: String
}

struct WebhookRepository: Content {
    let full_name: String
}
