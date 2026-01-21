import Vapor

/// Controller for GitHub webhook handling
struct WebhookController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("webhook", use: handleWebhook)
    }

    /// Handle incoming GitHub webhook
    @Sendable
    func handleWebhook(req: Request) async throws -> Response {
        // Parse webhook payload
        guard let payload = try? req.content.decode(WebhookPayload.self) else {
            return Response(status: .badRequest, body: .init(string: "Invalid payload"))
        }

        // Check if this is an issue event
        guard let issue = payload.issue,
              let repository = payload.repository else {
            return Response(status: .ok, body: .init(string: "Ignored"))
        }

        let action = payload.action ?? ""
        let repoName = repository.full_name
        let labels = issue.labels?.map { $0.name } ?? []

        // Find any cmd: label
        guard let cmdLabel = labels.first(where: { $0.hasPrefix("cmd:") }),
              action == "labeled" || action == "opened" else {
            return Response(status: .ok, body: .init(string: "Ignored"))
        }

        let commandName = cmdLabel.replacingOccurrences(of: "cmd:", with: "")

        // Trigger the job using shared service
        await req.application.jobTriggerService.triggerJob(
            repo: repoName,
            issueNum: issue.number,
            issueTitle: issue.title,
            command: commandName,
            cmdLabel: cmdLabel
        )

        return Response(status: .ok, body: .init(string: "Triggered"))
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
