import Vapor
import Foundation

/// Job status values
public enum JobStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case running
    case completed
    case failed
    case rejected
    case interrupted
    case waitingApproval = "waiting_approval"
    case approvedResume = "approved_resume"

    public var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .rejected: return "Rejected"
        case .interrupted: return "Interrupted"
        case .waitingApproval: return "Waiting Approval"
        case .approvedResume: return "Approved"
        }
    }

    public var isActive: Bool {
        self == .pending || self == .running || self == .waitingApproval
    }
}

/// Job model stored in Firestore
public struct Job: Content, Identifiable, Hashable, Equatable {
    public static func == (lhs: Job, rhs: Job) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.updatedAt == rhs.updatedAt
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    /// Unique job identifier: {repo_slug}-{issue_num}-{command}
    public let id: String

    /// Full repo name: "owner/repo-name"
    public let repo: String

    /// Repo slug: "repo-name"
    public let repoSlug: String

    /// GitHub issue number
    public let issueNum: Int

    /// Issue title
    public let issueTitle: String

    /// Command name: "plan-headless", "implement-headless", etc.
    public let command: String

    /// Current job status
    public var status: JobStatus

    /// Unix timestamp when job started
    public let startTime: Int

    /// Unix timestamp when job completed (if applicable)
    public var completedTime: Int?

    /// Path to log file
    public let logPath: String

    /// Local filesystem path for the repo
    public let localPath: String

    /// Full CLI command that was executed
    public let fullCommand: String

    /// Error message if job failed
    public var error: String?

    /// Cost information for this job
    public var cost: JobCost?

    /// Timestamp when created
    public let createdAt: Date

    /// Timestamp when last updated
    public var updatedAt: Date

    /// Create a new job
    public init(
        repo: String,
        issueNum: Int,
        issueTitle: String,
        command: String,
        localPath: String
    ) {
        let repoSlug = repo.split(separator: "/").last.map(String.init) ?? repo
        self.id = "\(repoSlug)-\(issueNum)-\(command)"
        self.repo = repo
        self.repoSlug = repoSlug
        self.issueNum = issueNum
        self.issueTitle = issueTitle
        self.command = command
        self.status = .pending
        self.startTime = Int(Date().timeIntervalSince1970)
        self.completedTime = nil
        self.logPath = "/tmp/claude_job_\(self.id).log"
        self.localPath = localPath
        self.fullCommand = "cd \(localPath) && claude '/\(command) \(issueNum)' --print --dangerously-skip-permissions"
        self.error = nil
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Coding keys for JSON/Firestore
    enum CodingKeys: String, CodingKey {
        case id
        case repo
        case repoSlug = "repo_slug"
        case issueNum = "issue_num"
        case issueTitle = "issue_title"
        case command
        case status
        case startTime = "start_time"
        case completedTime = "completed_time"
        case logPath = "log_path"
        case localPath = "local_path"
        case fullCommand = "full_command"
        case error
        case cost
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Formatted start time
    public var formattedStartTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(startTime))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Short command name for display
    public var shortCommand: String {
        command.replacingOccurrences(of: "-headless", with: "")
    }
}

/// Response format for job list (matches Python server)
public struct JobResponse: Content {
    public let issueId: String
    public let issue_id: String
    public let status: String
    public let repo: String
    public let cmd: String
    public let command: String
    public let start_time: Int
    public let issue_title: String
    public let issue_num: Int
    public let logs: [String]

    public init(from job: Job, logs: [String] = []) {
        self.issueId = job.id
        self.issue_id = job.id
        self.status = job.status.rawValue
        self.repo = job.repo
        self.cmd = job.fullCommand
        self.command = job.command
        self.start_time = job.startTime
        self.issue_title = job.issueTitle
        self.issue_num = job.issueNum
        self.logs = logs
    }
}

/// Response format for log fetch
public struct LogResponse: Content {
    public let issueId: String
    public let issue_id: String
    public let logs: String
    public let status: String

    public init(from job: Job, logs: String) {
        self.issueId = job.id
        self.issue_id = job.id
        self.logs = logs
        self.status = job.status.rawValue
    }
}
