import Vapor
import Foundation

/// Status of a preview deployment
public enum PreviewStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case deploying
    case ready
    case failed
    case expired
}

/// Type of project detected for deployment
public enum ProjectType: String, Codable, Sendable, CaseIterable {
    case flutter
    case reactNative
    case web
    case ios
    case android
    case unknown
}

/// A preview deployment for an issue
public struct PreviewDeployment: Content, Identifiable, Sendable {
    /// Unique identifier
    public let id: String

    /// Composite key: "owner/repo#issueNum"
    public let issueKey: String

    /// Repository (owner/repo format)
    public let repo: String

    /// Issue number
    public let issueNum: Int

    /// Detected project type
    public let projectType: ProjectType

    /// Current deployment status
    public let status: PreviewStatus

    /// Preview URL (available when status is ready)
    public let previewUrl: String?

    /// Logs URL for debugging
    public let logsUrl: String?

    /// Commit SHA that triggered the deployment
    public let commitSha: String?

    /// Error message if failed
    public let errorMessage: String?

    /// When the deployment was created
    public let createdAt: Date

    /// When the deployment was last updated
    public let updatedAt: Date

    /// When the preview expires (optional)
    public let expiresAt: Date?

    public init(
        id: String = UUID().uuidString,
        issueKey: String,
        repo: String,
        issueNum: Int,
        projectType: ProjectType,
        status: PreviewStatus = .pending,
        previewUrl: String? = nil,
        logsUrl: String? = nil,
        commitSha: String? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.issueKey = issueKey
        self.repo = repo
        self.issueNum = issueNum
        self.projectType = projectType
        self.status = status
        self.previewUrl = previewUrl
        self.logsUrl = logsUrl
        self.commitSha = commitSha
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
    }

    /// Create an updated deployment with new values
    public func updated(
        status: PreviewStatus? = nil,
        previewUrl: String? = nil,
        logsUrl: String? = nil,
        errorMessage: String? = nil,
        expiresAt: Date? = nil
    ) -> PreviewDeployment {
        PreviewDeployment(
            id: self.id,
            issueKey: self.issueKey,
            repo: self.repo,
            issueNum: self.issueNum,
            projectType: self.projectType,
            status: status ?? self.status,
            previewUrl: previewUrl ?? self.previewUrl,
            logsUrl: logsUrl ?? self.logsUrl,
            commitSha: self.commitSha,
            errorMessage: errorMessage ?? self.errorMessage,
            createdAt: self.createdAt,
            updatedAt: Date(),
            expiresAt: expiresAt ?? self.expiresAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case issueKey = "issue_key"
        case repo
        case issueNum = "issue_num"
        case projectType = "project_type"
        case status
        case previewUrl = "preview_url"
        case logsUrl = "logs_url"
        case commitSha = "commit_sha"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case expiresAt = "expires_at"
    }
}
