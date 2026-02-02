import Vapor

// MARK: - Trigger Preview Request/Response

/// Request to trigger a preview deployment
public struct TriggerPreviewRequest: Content {
    /// Commit SHA to deploy (optional, uses latest if not provided)
    public let commitSha: String?

    enum CodingKeys: String, CodingKey {
        case commitSha = "commit_sha"
    }
}

/// Response after triggering a preview deployment
public struct TriggerPreviewResponse: Content {
    public let status: String
    public let deploymentId: String
    public let message: String

    public init(status: String, deploymentId: String, message: String) {
        self.status = status
        self.deploymentId = deploymentId
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case status
        case deploymentId = "deployment_id"
        case message
    }
}

// MARK: - Callback Payloads

/// Payload from CI/CD callback for preview status update
public struct PreviewCallbackPayload: Content {
    /// Composite key: "owner/repo#issueNum"
    public let issueKey: String

    /// New status
    public let status: String

    /// Preview URL (if ready)
    public let previewUrl: String?

    /// Logs URL
    public let logsUrl: String?

    /// Error message (if failed)
    public let errorMessage: String?

    /// When the preview expires
    public let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case issueKey = "issue_key"
        case status
        case previewUrl = "preview_url"
        case logsUrl = "logs_url"
        case errorMessage = "error_message"
        case expiresAt = "expires_at"
    }
}

/// Payload from CI/CD callback for test results
public struct TestResultCallbackPayload: Content {
    /// Composite key: "owner/repo#issueNum"
    public let issueKey: String

    /// Name of the test suite
    public let testSuite: String

    /// Number of passed tests
    public let passedCount: Int

    /// Number of failed tests
    public let failedCount: Int

    /// Number of skipped tests
    public let skippedCount: Int

    /// Duration in seconds
    public let duration: Double?

    /// Code coverage percentage
    public let coverage: Double?

    /// Test failures details
    public let failures: [TestFailurePayload]?

    /// Commit SHA for this test run
    public let commitSha: String?

    enum CodingKeys: String, CodingKey {
        case issueKey = "issue_key"
        case testSuite = "test_suite"
        case passedCount = "passed_count"
        case failedCount = "failed_count"
        case skippedCount = "skipped_count"
        case duration
        case coverage
        case failures
        case commitSha = "commit_sha"
    }
}

/// Test failure detail from callback
public struct TestFailurePayload: Content {
    public let testName: String
    public let suiteName: String?
    public let message: String
    public let stackTrace: String?
    public let filePath: String?
    public let lineNumber: Int?

    enum CodingKeys: String, CodingKey {
        case testName = "test_name"
        case suiteName = "suite_name"
        case message
        case stackTrace = "stack_trace"
        case filePath = "file_path"
        case lineNumber = "line_number"
    }

    /// Convert to TestFailure model
    public func toTestFailure() -> TestFailure {
        TestFailure(
            testName: testName,
            suiteName: suiteName,
            message: message,
            stackTrace: stackTrace,
            filePath: filePath,
            lineNumber: lineNumber
        )
    }
}

// MARK: - Callback Response

/// Response to callback requests
public struct CallbackResponse: Content {
    public let status: String
    public let message: String

    public init(status: String, message: String) {
        self.status = status
        self.message = message
    }
}
