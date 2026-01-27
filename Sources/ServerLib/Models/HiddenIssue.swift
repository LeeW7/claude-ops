import Vapor
import Foundation

/// Reason why an issue was hidden
public enum HiddenIssueReason: String, Codable, Sendable {
    case user = "user"
    case closed = "closed"
}

/// A hidden issue that should not appear on the Kanban board
public struct HiddenIssue: Content, Sendable {
    /// Unique key: "owner/repo#123"
    public let issueKey: String

    /// Repository: "owner/repo"
    public let repo: String

    /// Issue number
    public let issueNum: Int

    /// Issue title
    public let issueTitle: String

    /// When the issue was hidden (Unix timestamp in milliseconds)
    public let hiddenAt: Int64

    /// Reason for hiding
    public let reason: HiddenIssueReason

    public init(
        issueKey: String,
        repo: String,
        issueNum: Int,
        issueTitle: String,
        hiddenAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        reason: HiddenIssueReason = .user
    ) {
        self.issueKey = issueKey
        self.repo = repo
        self.issueNum = issueNum
        self.issueTitle = issueTitle
        self.hiddenAt = hiddenAt
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case issueKey = "issue_key"
        case repo
        case issueNum = "issue_num"
        case issueTitle = "issue_title"
        case hiddenAt = "hidden_at"
        case reason
    }
}

/// Request body for hiding an issue
public struct HideIssueRequest: Content {
    public let issueKey: String
    public let repo: String
    public let issueNum: Int
    public let issueTitle: String
    public let reason: HiddenIssueReason?

    enum CodingKeys: String, CodingKey {
        case issueKey = "issue_key"
        case repo
        case issueNum = "issue_num"
        case issueTitle = "issue_title"
        case reason
    }
}
