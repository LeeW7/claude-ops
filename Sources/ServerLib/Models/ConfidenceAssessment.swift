import Vapor
import Foundation

/// Confidence assessment extracted from Claude's job output
public struct ConfidenceAssessment: Content, Identifiable, Sendable {
    /// Unique identifier
    public let id: String

    /// Job this assessment belongs to
    public let jobId: String

    /// Confidence score (0-100)
    public let score: Int

    /// Brief assessment (e.g., "High confidence - straightforward implementation")
    public let assessment: String

    /// Why this confidence level
    public let reasoning: String

    /// Potential risks or concerns (optional)
    public let risks: [String]?

    /// When the assessment was extracted
    public let timestamp: Date

    public init(
        id: String = UUID().uuidString,
        jobId: String,
        score: Int,
        assessment: String,
        reasoning: String,
        risks: [String]? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.jobId = jobId
        self.score = min(100, max(0, score)) // Clamp to 0-100
        self.assessment = assessment
        self.reasoning = reasoning
        self.risks = risks
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case jobId = "job_id"
        case score
        case assessment
        case reasoning
        case risks
        case timestamp
    }
}
