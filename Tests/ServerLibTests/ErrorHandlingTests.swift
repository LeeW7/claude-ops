import XCTest
@testable import ServerLib

final class ErrorHandlingTests: XCTestCase {

    // MARK: - GitHubCLIError Tests

    func testGitHubCLIErrorDescription() {
        let error = GitHubCLIError(
            command: "gh repo view",
            exitCode: 1,
            stderr: "Could not resolve to a Repository with the name 'fake/repo'",
            stdout: ""
        )

        XCTAssertTrue(error.errorDescription?.contains("exit 1") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("Could not resolve") ?? false)
    }

    func testGitHubCLIErrorIsNotFound() {
        let notFoundError = GitHubCLIError(
            command: "gh issue view",
            exitCode: 1,
            stderr: "Could not resolve to a Repository",
            stdout: ""
        )
        XCTAssertTrue(notFoundError.isNotFound)

        let otherError = GitHubCLIError(
            command: "gh issue view",
            exitCode: 1,
            stderr: "Permission denied",
            stdout: ""
        )
        XCTAssertFalse(otherError.isNotFound)
    }

    func testGitHubCLIErrorIsAlreadyExists() {
        let existsError = GitHubCLIError(
            command: "gh label create",
            exitCode: 1,
            stderr: "Label 'bug' already exists",
            stdout: ""
        )
        XCTAssertTrue(existsError.isAlreadyExists)

        let otherError = GitHubCLIError(
            command: "gh label create",
            exitCode: 1,
            stderr: "Permission denied",
            stdout: ""
        )
        XCTAssertFalse(otherError.isAlreadyExists)
    }

    // MARK: - JobTriggerResult Tests

    func testJobTriggerResultTriggered() {
        let result = JobTriggerResult.triggered(jobId: "test-123-plan")
        XCTAssertTrue(result.wasTriggered)
        XCTAssertTrue(result.description.contains("test-123-plan"))
    }

    func testJobTriggerResultSkipped() {
        let result = JobTriggerResult.skipped(reason: "Already running")
        XCTAssertFalse(result.wasTriggered)
        XCTAssertTrue(result.description.contains("Already running"))
    }

    func testJobTriggerResultFailed() {
        let result = JobTriggerResult.failed(error: "Repo not in map")
        XCTAssertFalse(result.wasTriggered)
        XCTAssertTrue(result.description.contains("Repo not in map"))
    }

    // MARK: - Required Labels Tests

    func testRequiredLabelsContainsAllCommandLabels() {
        let labelNames = GitHubService.requiredLabels.map { $0.name }

        // All command labels should be present
        XCTAssertTrue(labelNames.contains("cmd:plan-headless"))
        XCTAssertTrue(labelNames.contains("cmd:implement-headless"))
        XCTAssertTrue(labelNames.contains("cmd:revise-headless"))
        XCTAssertTrue(labelNames.contains("cmd:retrospective-headless"))

        // Status labels should be present
        XCTAssertTrue(labelNames.contains("ready-for-review"))
        XCTAssertTrue(labelNames.contains("blocked"))
    }

    func testRequiredLabelsHaveColors() {
        for label in GitHubService.requiredLabels {
            XCTAssertFalse(label.color.isEmpty, "Label \(label.name) should have a color")
            XCTAssertEqual(label.color.count, 6, "Color for \(label.name) should be 6 hex chars")
        }
    }

    func testRequiredLabelsHaveDescriptions() {
        for label in GitHubService.requiredLabels {
            XCTAssertFalse(label.description.isEmpty, "Label \(label.name) should have a description")
        }
    }
}
