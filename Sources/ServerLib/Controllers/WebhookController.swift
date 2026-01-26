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

        // Check if this is an issue event
        guard let issue = payload.issue,
              let repository = payload.repository else {
            req.logger.debug("[Webhook] Ignored - not an issue event (action: \(payload.action ?? "nil"))")
            return Response(status: .ok, body: .init(string: "Ignored"))
        }

        let action = payload.action ?? ""
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
}

// MARK: - Webhook Payload Models

struct WebhookPayload: Content {
    let action: String?
    let issue: WebhookIssue?
    let repository: WebhookRepository?
}

struct WebhookIssue: Content {
    let number: Int
    let title: String
    let labels: [WebhookLabel]?
}

struct WebhookLabel: Content {
    let name: String
}

struct WebhookRepository: Content {
    let full_name: String
}
