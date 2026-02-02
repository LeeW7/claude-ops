import Vapor
import Foundation

/// Service for triggering preview deployments via GitHub Actions
public struct PreviewService: Sendable {
    private let callbackUrl: String?
    private let callbackSecret: String?

    public init() {
        self.callbackUrl = Environment.get("CALLBACK_URL")
        self.callbackSecret = Environment.get("PREVIEW_CALLBACK_SECRET")
    }

    /// Trigger a preview deployment via GitHub repository dispatch
    public func triggerDeployment(
        repo: String,
        issueNum: Int,
        projectType: ProjectType,
        commitSha: String?,
        logger: Logger
    ) async throws {
        guard let token = Environment.get("GITHUB_TOKEN") else {
            throw PreviewServiceError.missingGitHubToken
        }

        let url = "https://api.github.com/repos/\(repo)/dispatches"

        var clientPayload: [String: String] = [
            "issue_num": String(issueNum),
            "project_type": projectType.rawValue
        ]

        if let sha = commitSha {
            clientPayload["commit_sha"] = sha
        }

        if let callbackUrl = callbackUrl {
            clientPayload["callback_url"] = callbackUrl
        }

        let payload: [String: Any] = [
            "event_type": "preview-deployment",
            "client_payload": clientPayload
        ]

        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        logger.info("[PreviewService] Triggering deployment for \(repo)#\(issueNum)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PreviewServiceError.invalidResponse
        }

        // 204 No Content is success for dispatches
        guard httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("[PreviewService] Dispatch failed: \(httpResponse.statusCode) - \(errorBody)")
            throw PreviewServiceError.dispatchFailed(httpResponse.statusCode, errorBody)
        }

        logger.info("[PreviewService] Deployment triggered successfully for \(repo)#\(issueNum)")
    }

    /// Create a pending preview deployment record
    public func createPendingDeployment(
        repo: String,
        issueNum: Int,
        projectType: ProjectType,
        commitSha: String?
    ) -> PreviewDeployment {
        let issueKey = "\(repo)#\(issueNum)"
        return PreviewDeployment(
            issueKey: issueKey,
            repo: repo,
            issueNum: issueNum,
            projectType: projectType,
            status: .pending,
            commitSha: commitSha
        )
    }

    /// Validate callback secret from request header
    public func validateCallbackSecret(_ providedSecret: String?) -> Bool {
        guard let expectedSecret = callbackSecret, !expectedSecret.isEmpty else {
            // No secret configured - allow all callbacks (development mode)
            return true
        }
        return providedSecret == expectedSecret
    }
}

/// Errors from preview service operations
public enum PreviewServiceError: Error, LocalizedError {
    case missingGitHubToken
    case invalidResponse
    case dispatchFailed(Int, String)

    public var errorDescription: String? {
        switch self {
        case .missingGitHubToken:
            return "GITHUB_TOKEN environment variable not set"
        case .invalidResponse:
            return "Invalid response from GitHub API"
        case .dispatchFailed(let code, let message):
            return "GitHub dispatch failed with status \(code): \(message)"
        }
    }
}
