import Vapor
import Foundation

/// A single test failure with details
public struct TestFailure: Codable, Sendable {
    /// Name of the failing test
    public let testName: String

    /// Test suite/class name
    public let suiteName: String?

    /// Error message
    public let message: String

    /// Stack trace (optional)
    public let stackTrace: String?

    /// File path where the test is located
    public let filePath: String?

    /// Line number of the failure
    public let lineNumber: Int?

    public init(
        testName: String,
        suiteName: String? = nil,
        message: String,
        stackTrace: String? = nil,
        filePath: String? = nil,
        lineNumber: Int? = nil
    ) {
        self.testName = testName
        self.suiteName = suiteName
        self.message = message
        self.stackTrace = stackTrace
        self.filePath = filePath
        self.lineNumber = lineNumber
    }

    enum CodingKeys: String, CodingKey {
        case testName = "test_name"
        case suiteName = "suite_name"
        case message
        case stackTrace = "stack_trace"
        case filePath = "file_path"
        case lineNumber = "line_number"
    }
}

/// Test results for an issue
public struct TestResult: Content, Identifiable, Sendable {
    /// Unique identifier
    public let id: String

    /// Composite key: "owner/repo#issueNum"
    public let issueKey: String

    /// Repository (owner/repo format)
    public let repo: String

    /// Issue number
    public let issueNum: Int

    /// Name of the test suite/run
    public let testSuite: String

    /// Number of passed tests
    public let passedCount: Int

    /// Number of failed tests
    public let failedCount: Int

    /// Number of skipped tests
    public let skippedCount: Int

    /// Total duration in seconds
    public let duration: Double?

    /// Code coverage percentage (0-100)
    public let coverage: Double?

    /// Details of test failures
    public let failures: [TestFailure]

    /// When the test run was recorded
    public let timestamp: Date

    /// Commit SHA for this test run
    public let commitSha: String?

    public init(
        id: String = UUID().uuidString,
        issueKey: String,
        repo: String,
        issueNum: Int,
        testSuite: String,
        passedCount: Int,
        failedCount: Int,
        skippedCount: Int,
        duration: Double? = nil,
        coverage: Double? = nil,
        failures: [TestFailure] = [],
        timestamp: Date = Date(),
        commitSha: String? = nil
    ) {
        self.id = id
        self.issueKey = issueKey
        self.repo = repo
        self.issueNum = issueNum
        self.testSuite = testSuite
        self.passedCount = passedCount
        self.failedCount = failedCount
        self.skippedCount = skippedCount
        self.duration = duration
        self.coverage = coverage
        self.failures = failures
        self.timestamp = timestamp
        self.commitSha = commitSha
    }

    /// Total number of tests
    public var totalCount: Int {
        passedCount + failedCount + skippedCount
    }

    /// Whether all tests passed
    public var allPassed: Bool {
        failedCount == 0
    }

    enum CodingKeys: String, CodingKey {
        case id
        case issueKey = "issue_key"
        case repo
        case issueNum = "issue_num"
        case testSuite = "test_suite"
        case passedCount = "passed_count"
        case failedCount = "failed_count"
        case skippedCount = "skipped_count"
        case duration
        case coverage
        case failures
        case timestamp
        case commitSha = "commit_sha"
    }
}
