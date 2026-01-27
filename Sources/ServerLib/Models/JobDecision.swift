import Vapor
import Foundation

/// Category of a decision
public enum DecisionCategory: String, Codable, Sendable {
    case architecture
    case library
    case pattern
    case storage
    case api
    case testing
    case ui
    case other
}

/// A decision made by Claude during job execution with reasoning
public struct JobDecision: Content, Identifiable, Sendable {
    /// Unique identifier
    public let id: String

    /// Job this decision belongs to
    public let jobId: String

    /// What was done (e.g., "Used Provider pattern")
    public let action: String

    /// Why (e.g., "Matches existing codebase patterns")
    public let reasoning: String

    /// Other options considered (optional)
    public let alternatives: [String]?

    /// Category of decision
    public let category: DecisionCategory?

    /// When the decision was extracted
    public let timestamp: Date

    public init(
        id: String = UUID().uuidString,
        jobId: String,
        action: String,
        reasoning: String,
        alternatives: [String]? = nil,
        category: DecisionCategory? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.jobId = jobId
        self.action = action
        self.reasoning = reasoning
        self.alternatives = alternatives
        self.category = category
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case jobId = "job_id"
        case action
        case reasoning
        case alternatives
        case category
        case timestamp
    }
}
