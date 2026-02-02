import Vapor
import Foundation

/// Current phase of validation for an issue
public enum ValidationPhase: String, Codable, Sendable, CaseIterable {
    /// No validation activity
    case idle
    /// Building/deploying preview
    case building
    /// Running tests
    case testing
    /// Preview ready and tests complete
    case ready
    /// Validation failed (build or tests)
    case failed
}

/// Composite validation state for an issue
public struct ValidationState: Content, Sendable {
    /// Repository (owner/repo format)
    public let repo: String

    /// Issue number
    public let issueNum: Int

    /// Current validation phase
    public let phase: ValidationPhase

    /// Preview deployment (if any)
    public let preview: PreviewDeployment?

    /// Test results (most recent first)
    public let testResults: [TestResult]

    /// Latest test result summary
    public let latestTestSummary: TestSummary?

    public init(
        repo: String,
        issueNum: Int,
        preview: PreviewDeployment?,
        testResults: [TestResult]
    ) {
        self.repo = repo
        self.issueNum = issueNum
        self.preview = preview
        self.testResults = testResults
        self.latestTestSummary = testResults.first.map { TestSummary(from: $0) }
        self.phase = Self.computePhase(preview: preview, testResults: testResults)
    }

    /// Compute the current validation phase based on preview and test state
    private static func computePhase(preview: PreviewDeployment?, testResults: [TestResult]) -> ValidationPhase {
        // Check preview status first
        if let preview = preview {
            switch preview.status {
            case .pending, .deploying:
                return .building
            case .failed:
                return .failed
            case .expired:
                return .idle
            case .ready:
                // Preview is ready, check tests
                break
            }
        }

        // Check test results
        if let latestTest = testResults.first {
            if latestTest.failedCount > 0 {
                return .failed
            }
            // Tests passed and preview is ready (or no preview)
            if preview?.status == .ready || preview == nil {
                return .ready
            }
        }

        // No preview and no tests
        if preview == nil && testResults.isEmpty {
            return .idle
        }

        // Preview ready but no tests yet
        if preview?.status == .ready && testResults.isEmpty {
            return .ready
        }

        return .idle
    }

    enum CodingKeys: String, CodingKey {
        case repo
        case issueNum = "issue_num"
        case phase
        case preview
        case testResults = "test_results"
        case latestTestSummary = "latest_test_summary"
    }
}

/// Summary of test results for quick display
public struct TestSummary: Codable, Sendable {
    public let passed: Int
    public let failed: Int
    public let skipped: Int
    public let total: Int
    public let coverage: Double?
    public let allPassed: Bool

    public init(from testResult: TestResult) {
        self.passed = testResult.passedCount
        self.failed = testResult.failedCount
        self.skipped = testResult.skippedCount
        self.total = testResult.totalCount
        self.coverage = testResult.coverage
        self.allPassed = testResult.allPassed
    }

    enum CodingKeys: String, CodingKey {
        case passed
        case failed
        case skipped
        case total
        case coverage
        case allPassed = "all_passed"
    }
}
