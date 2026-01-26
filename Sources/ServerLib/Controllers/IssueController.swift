import Vapor

/// Controller for issue-related endpoints
struct IssueController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let issues = routes.grouped("issues")

        // Issue creation and enhancement
        issues.post(use: createIssue)
        issues.post("create", use: createIssue)  // Alias
        issues.post("enhance", use: enhanceIssue)

        // Issue details and workflow (use :owner/:repo/:num for repos like owner/repo-name)
        issues.get(":owner", ":repo", ":num", use: getIssueDetails)
        issues.get(":owner", ":repo", ":num", "workflow", use: getWorkflowState)
        issues.post(":owner", ":repo", ":num", "proceed", use: proceedWithIssue)
        issues.post(":owner", ":repo", ":num", "feedback", use: postFeedback)
        issues.post(":owner", ":repo", ":num", "merge", use: mergePR)
        issues.get(":owner", ":repo", ":num", "pr", use: getPRDetails)
        issues.get(":owner", ":repo", ":num", "costs", use: getIssueCosts)
    }

    /// Create a new GitHub issue
    @Sendable
    func createIssue(req: Request) async throws -> Response {
        let body = try req.content.decode(CreateIssueRequest.self)

        guard let repoMap = req.application.repoMap else {
            throw Abort(.internalServerError, reason: "Repo map not configured")
        }

        // Verify repo is in our map
        guard let localPath = repoMap.getPath(for: body.repo) else {
            throw Abort(.badRequest, reason: "Repository \(body.repo) not found in repo_map.json")
        }

        // Create issue with cmd:plan-headless label
        let issueUrl = try await req.application.githubService.createIssue(
            repo: body.repo,
            title: body.title,
            body: body.body ?? "",
            labels: ["cmd:plan-headless"]
        )

        // Extract issue number from URL (e.g., "https://github.com/owner/repo/issues/123")
        // and trigger the job in background (don't block the response)
        if let lastComponent = issueUrl.split(separator: "/").last,
           let issueNum = Int(lastComponent) {
            let app = req.application
            Task {
                let result = await app.jobTriggerService.triggerJob(
                    repo: body.repo,
                    issueNum: issueNum,
                    issueTitle: body.title,
                    command: "plan-headless",
                    cmdLabel: "cmd:plan-headless"
                )
                if case .failed(let error) = result {
                    app.logger.error("Failed to trigger plan-headless job for new issue: \(error)")
                }
            }
        }

        let response = CreateIssueResponse(
            status: "created",
            issue_url: issueUrl,
            message: "Issue created and job started"
        )

        return try await response.encodeResponse(status: .created, for: req)
    }

    /// Enhance an issue description using AI
    @Sendable
    func enhanceIssue(req: Request) async throws -> EnhanceIssueResponse {
        let body = try req.content.decode(EnhanceIssueRequest.self)

        guard !body.idea.isEmpty else {
            throw Abort(.badRequest, reason: "idea is required")
        }

        let (enhancedTitle, enhancedBody) = try await req.application.geminiService.enhanceIssue(
            title: body.title,
            description: body.idea,
            repo: body.repo
        )

        return EnhanceIssueResponse(
            enhanced_title: enhancedTitle,
            enhanced_body: enhancedBody,
            original_idea: body.idea
        )
    }

    /// Get issue details from GitHub
    @Sendable
    func getIssueDetails(req: Request) async throws -> Response {
        let (repo, issueNum) = try parseRepoAndIssue(req)

        guard let issueData = try await req.application.githubService.getIssue(repo: repo, number: issueNum) else {
            throw Abort(.notFound, reason: "Issue not found")
        }

        let data = try JSONSerialization.data(withJSONObject: issueData)
        return Response(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: .init(data: data)
        )
    }

    /// Get workflow state for an issue
    @Sendable
    func getWorkflowState(req: Request) async throws -> WorkflowState {
        let (repo, issueNum) = try parseRepoAndIssue(req)

        // Get all jobs for this issue
        let jobs = try await req.application.persistenceService.getJobsForIssue(repo: repo, issueNum: issueNum)

        // Check if issue is closed
        let issueClosed = try await req.application.githubService.isIssueClosed(repo: repo, number: issueNum)

        // Try to extract PR URL from implement job
        let repoSlug = repo.split(separator: "/").last.map(String.init) ?? repo
        let implementJob = jobs.first { $0.id == "\(repoSlug)-\(issueNum)-implement-headless" }
        var prUrl: String? = nil
        if let logPath = implementJob?.logPath {
            prUrl = await req.application.claudeService.extractPRUrl(from: logPath)
        }

        return WorkflowState.forIssue(
            repo: repo,
            issueNum: issueNum,
            jobs: jobs,
            issueClosed: issueClosed,
            prUrl: prUrl
        )
    }

    /// Proceed to next workflow phase
    @Sendable
    func proceedWithIssue(req: Request) async throws -> Response {
        let (repo, issueNum) = try parseRepoAndIssue(req)

        // Get current workflow state (these are needed to validate the request)
        let jobs = try await req.application.persistenceService.getJobsForIssue(repo: repo, issueNum: issueNum)
        let issueClosed = try await req.application.githubService.isIssueClosed(repo: repo, number: issueNum)
        let state = WorkflowState.forIssue(repo: repo, issueNum: issueNum, jobs: jobs, issueClosed: issueClosed, prUrl: nil)

        guard let nextLabel = state.nextActionLabel,
              let nextAction = state.nextAction else {
            throw Abort(.badRequest, reason: "No next action available. Current phase: \(state.currentPhase)")
        }

        let command = nextLabel.replacingOccurrences(of: "cmd:", with: "")

        // Return immediately - do the heavy lifting in background
        let app = req.application
        Task {
            // Get issue title for the job
            let issueTitle: String
            do {
                let issueData = try await app.githubService.getIssue(repo: repo, number: issueNum)
                issueTitle = issueData?["title"] as? String ?? "Issue #\(issueNum)"
            } catch {
                app.logger.warning("Could not fetch issue title for \(repo)#\(issueNum): \(error.localizedDescription)")
                issueTitle = "Issue #\(issueNum)"
            }

            // Trigger the job (creates worktree, saves to Firebase, removes label)
            let result = await app.jobTriggerService.triggerJob(
                repo: repo,
                issueNum: issueNum,
                issueTitle: issueTitle,
                command: command,
                cmdLabel: nextLabel
            )
            if case .failed(let error) = result {
                app.logger.error("Failed to trigger \(command) job: \(error)")
            }
        }

        let response: [String: Any] = [
            "status": "proceeded",
            "action": nextAction,
            "message": "Starting \(command) job for issue #\(issueNum)"
        ]

        let data = try JSONSerialization.data(withJSONObject: response)
        return Response(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: .init(data: data)
        )
    }

    /// Post feedback and trigger revision or plan update
    @Sendable
    func postFeedback(req: Request) async throws -> FeedbackResponse {
        let (repo, issueNum) = try parseRepoAndIssue(req)
        let body = try req.content.decode(FeedbackRequest.self)

        guard req.application.repoMap != nil else {
            throw Abort(.internalServerError, reason: "Repo map not configured")
        }

        guard req.application.repoMap!.getPath(for: repo) != nil else {
            throw Abort(.badRequest, reason: "Repository \(repo) not found in repo_map.json")
        }

        guard !body.feedback.isEmpty else {
            throw Abort(.badRequest, reason: "feedback text is required")
        }

        // Get current workflow state to determine which job to trigger
        let jobs = try await req.application.persistenceService.getJobsForIssue(repo: repo, issueNum: issueNum)
        let issueClosed = try await req.application.githubService.isIssueClosed(repo: repo, number: issueNum)
        let state = WorkflowState.forIssue(repo: repo, issueNum: issueNum, jobs: jobs, issueClosed: issueClosed, prUrl: nil)

        // Determine if this is plan feedback or implementation feedback
        let isPlanFeedback = state.currentPhase == "plan_complete"
        let commentHeader = isPlanFeedback ? "## Plan Feedback" : "## Revision Requested"
        let command = isPlanFeedback ? "plan-headless" : "revise-headless"
        let cmdLabel = isPlanFeedback ? "cmd:plan-headless" : "cmd:revise-headless"

        // Build comment body
        var commentBody = "\(commentHeader)\n\n\(body.feedback)"
        if let imageUrl = body.image_url {
            commentBody += "\n\n### Screenshot\n![Screenshot](\(imageUrl))"
        }

        // Post comment
        try await req.application.githubService.postComment(repo: repo, number: issueNum, body: commentBody)

        // Get issue title for the job
        let issueTitle: String
        do {
            let issueData = try await req.application.githubService.getIssue(repo: repo, number: issueNum)
            issueTitle = issueData?["title"] as? String ?? "Issue #\(issueNum)"
        } catch {
            req.logger.warning("Could not fetch issue title: \(error.localizedDescription)")
            issueTitle = "Issue #\(issueNum)"
        }

        // Trigger the appropriate job
        let result = await req.application.jobTriggerService.triggerJob(
            repo: repo,
            issueNum: issueNum,
            issueTitle: issueTitle,
            command: command,
            cmdLabel: cmdLabel
        )

        switch result {
        case .triggered:
            let message = isPlanFeedback
                ? "Feedback posted and plan update started for issue #\(issueNum)"
                : "Feedback posted and revision job started for issue #\(issueNum)"
            return FeedbackResponse(
                status: "feedback_submitted",
                message: message
            )

        case .skipped(let reason):
            return FeedbackResponse(
                status: "feedback_posted",
                message: "Feedback posted but job skipped: \(reason)"
            )

        case .failed(let error):
            throw Abort(.internalServerError, reason: "Feedback posted but job failed to start: \(error)")
        }
    }

    /// Merge the PR for an issue
    @Sendable
    func mergePR(req: Request) async throws -> MergeResponse {
        let (repo, issueNum) = try parseRepoAndIssue(req)
        let body = try? req.content.decode(MergeRequest.self)
        let mergeMethod = body?.mergeMethod ?? "squash"

        guard let repoMap = req.application.repoMap else {
            throw Abort(.internalServerError, reason: "Repo map not configured")
        }

        guard repoMap.getPath(for: repo) != nil else {
            throw Abort(.badRequest, reason: "Repository \(repo) not found in repo_map.json")
        }

        // Find PR for this issue
        guard let prData = try await req.application.githubService.findPRForIssue(repo: repo, issueNum: issueNum),
              let prNumber = prData["number"] as? Int else {
            throw Abort(.notFound, reason: "No open PR found for issue #\(issueNum)")
        }

        // Mark PR as ready (in case it's a draft)
        do {
            try await req.application.githubService.markPRReady(repo: repo, prNumber: prNumber)
        } catch {
            // Not critical - PR might not be a draft, or might already be ready
            req.logger.debug("Could not mark PR #\(prNumber) as ready: \(error.localizedDescription)")
        }

        // Merge the PR
        try await req.application.githubService.mergePR(repo: repo, prNumber: prNumber, method: mergeMethod)

        // Close the issue with a comment
        let comment = "PR #\(prNumber) has been merged. Closing this issue."
        try await req.application.githubService.closeIssue(repo: repo, number: issueNum, comment: comment)

        // Send notification
        await req.application.pushNotificationService.send(
            title: "PR Merged",
            body: "Issue #\(issueNum) merged successfully"
        )

        // Cleanup worktree for this issue (no longer needed after merge)
        if let mainRepoPath = repoMap.getPath(for: repo) {
            await req.application.worktreeService.removeWorktree(
                repo: repo,
                issueNum: issueNum,
                mainRepoPath: mainRepoPath
            )
            req.logger.info("[Worktree] Cleaned up worktree for \(repo)#\(issueNum) after merge")
        }

        return MergeResponse(
            status: "merged",
            pr_number: prNumber,
            message: "PR #\(prNumber) merged and issue #\(issueNum) closed"
        )
    }

    /// Get PR details for an issue
    @Sendable
    func getPRDetails(req: Request) async throws -> Response {
        let (repo, issueNum) = try parseRepoAndIssue(req)

        guard let repoMap = req.application.repoMap else {
            throw Abort(.internalServerError, reason: "Repo map not configured")
        }

        guard repoMap.getPath(for: repo) != nil else {
            throw Abort(.badRequest, reason: "Repository \(repo) not found in repo_map.json")
        }

        // Find PR for this issue
        guard let prData = try await req.application.githubService.findPRForIssue(repo: repo, issueNum: issueNum) else {
            let response = PRDetailsResponse(hasPr: false)
            return try await response.encodeResponse(for: req)
        }

        // Extract check status
        var checkStatus = "pending"
        if let checks = prData["statusCheckRollup"] as? [[String: Any]], !checks.isEmpty {
            let states = checks.compactMap { check -> String? in
                return check["state"] as? String ?? check["conclusion"] as? String ?? "PENDING"
            }

            if states.allSatisfy({ ["SUCCESS", "NEUTRAL", "SKIPPED"].contains($0) }) {
                checkStatus = "success"
            } else if states.contains(where: { ["FAILURE", "ERROR", "CANCELLED"].contains($0) }) {
                checkStatus = "failure"
            }
        }

        let response = PRDetailsResponse(
            hasPr: true,
            prNumber: prData["number"] as? Int,
            prUrl: prData["url"] as? String,
            title: prData["title"] as? String,
            branch: prData["headRefName"] as? String,
            mergeable: prData["mergeable"] as? String ?? "UNKNOWN",
            mergeStateStatus: prData["mergeStateStatus"] as? String ?? "UNKNOWN",
            checkStatus: checkStatus
        )

        return try await response.encodeResponse(for: req)
    }

    /// Get cost breakdown for an issue (all jobs)
    @Sendable
    func getIssueCosts(req: Request) async throws -> IssueCostsResponse {
        let (repo, issueNum) = try parseRepoAndIssue(req)

        // Get all jobs for this issue
        let jobs = try await req.application.persistenceService.getJobsForIssue(repo: repo, issueNum: issueNum)

        // Build cost breakdown by phase
        var phaseCosts: [PhaseCost] = []
        var totalCost: Double = 0
        var totalInputTokens: Int = 0
        var totalOutputTokens: Int = 0
        var totalCacheReadTokens: Int = 0
        var totalCacheWriteTokens: Int = 0

        // Map command names to phases
        let phaseOrder = ["plan-headless", "implement-headless", "revise-headless", "review-headless", "retrospective-headless"]

        for command in phaseOrder {
            let phaseJobs = jobs.filter { $0.command == command }
            if phaseJobs.isEmpty { continue }

            // Sum costs for all runs of this phase (could have revisions)
            var phaseTotalCost: Double = 0
            var phaseInputTokens: Int = 0
            var phaseOutputTokens: Int = 0
            var phaseCacheRead: Int = 0
            var phaseCacheWrite: Int = 0
            var model: String = "unknown"

            for job in phaseJobs {
                if let cost = job.cost {
                    phaseTotalCost += cost.totalUsd
                    phaseInputTokens += cost.inputTokens
                    phaseOutputTokens += cost.outputTokens
                    phaseCacheRead += cost.cacheReadTokens
                    phaseCacheWrite += cost.cacheCreationTokens
                    model = cost.model
                }
            }

            if phaseTotalCost > 0 {
                let phaseName = command.replacingOccurrences(of: "-headless", with: "")
                    .capitalized
                    .replacingOccurrences(of: "-", with: " ")

                phaseCosts.append(PhaseCost(
                    phase: phaseName,
                    command: command,
                    cost: phaseTotalCost,
                    inputTokens: phaseInputTokens,
                    outputTokens: phaseOutputTokens,
                    cacheReadTokens: phaseCacheRead,
                    cacheWriteTokens: phaseCacheWrite,
                    model: model,
                    runCount: phaseJobs.count
                ))

                totalCost += phaseTotalCost
                totalInputTokens += phaseInputTokens
                totalOutputTokens += phaseOutputTokens
                totalCacheReadTokens += phaseCacheRead
                totalCacheWriteTokens += phaseCacheWrite
            }
        }

        return IssueCostsResponse(
            repo: repo,
            issueNum: issueNum,
            phases: phaseCosts,
            totalCost: totalCost,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            totalCacheReadTokens: totalCacheReadTokens,
            totalCacheWriteTokens: totalCacheWriteTokens
        )
    }

    /// Parse repo and issue number from path parameters
    private func parseRepoAndIssue(_ req: Request) throws -> (String, Int) {
        // Extract owner, repo, and issue number from separate path parameters
        guard let owner = req.parameters.get("owner"),
              let repoName = req.parameters.get("repo"),
              let numStr = req.parameters.get("num"),
              let issueNum = Int(numStr) else {
            throw Abort(.badRequest, reason: "Invalid owner, repo, or issue number")
        }

        // Combine owner and repo into full name (e.g., "owner/repo-name")
        let repo = "\(owner)/\(repoName)"

        return (repo, issueNum)
    }
}
