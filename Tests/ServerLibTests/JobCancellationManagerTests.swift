import XCTest
@testable import ServerLib

final class JobCancellationManagerTests: XCTestCase {
    var manager: JobCancellationManager!

    override func setUp() async throws {
        manager = JobCancellationManager()
    }

    // MARK: - Basic Cancellation Tests

    func testCancelJob() async {
        let jobId = "test-repo-123-plan-headless"

        // Initially not cancelled
        let initialState = await manager.isCancelled(jobId)
        XCTAssertFalse(initialState)

        // Cancel the job
        await manager.cancel(jobId)

        // Should now be cancelled
        let cancelledState = await manager.isCancelled(jobId)
        XCTAssertTrue(cancelledState)
    }

    func testClearCancellation() async {
        let jobId = "test-repo-456-implement-headless"

        // Cancel then clear
        await manager.cancel(jobId)
        let afterCancel = await manager.isCancelled(jobId)
        XCTAssertTrue(afterCancel)

        await manager.clearCancellation(jobId)
        let afterClear = await manager.isCancelled(jobId)
        XCTAssertFalse(afterClear)
    }

    func testMultipleJobs() async {
        let job1 = "repo-1-plan"
        let job2 = "repo-2-implement"
        let job3 = "repo-3-review"

        // Cancel some jobs
        await manager.cancel(job1)
        await manager.cancel(job2)

        // Verify states
        let state1 = await manager.isCancelled(job1)
        let state2 = await manager.isCancelled(job2)
        let state3 = await manager.isCancelled(job3)

        XCTAssertTrue(state1)
        XCTAssertTrue(state2)
        XCTAssertFalse(state3)
    }

    func testAllCancelledJobs() async {
        let jobs = ["job-a", "job-b", "job-c"]

        for job in jobs {
            await manager.cancel(job)
        }

        let allCancelled = await manager.allCancelledJobs()
        XCTAssertEqual(allCancelled.count, 3)
        XCTAssertTrue(allCancelled.contains("job-a"))
        XCTAssertTrue(allCancelled.contains("job-b"))
        XCTAssertTrue(allCancelled.contains("job-c"))
    }

    func testCancelIdempotent() async {
        let jobId = "duplicate-cancel-job"

        // Cancel multiple times
        await manager.cancel(jobId)
        await manager.cancel(jobId)
        await manager.cancel(jobId)

        // Should still only appear once (Set behavior)
        let allCancelled = await manager.allCancelledJobs()
        XCTAssertEqual(allCancelled.filter { $0 == jobId }.count, 1)
    }

    func testClearNonExistentJob() async {
        // Clearing a job that was never cancelled should be safe
        await manager.clearCancellation("never-existed")

        // Should not crash and manager should still work
        let result = await manager.isCancelled("never-existed")
        XCTAssertFalse(result)
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentCancellations() async {
        let jobCount = 100

        // Cancel many jobs concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<jobCount {
                group.addTask {
                    await self.manager.cancel("job-\(i)")
                }
            }
        }

        // All should be cancelled
        let allCancelled = await manager.allCancelledJobs()
        XCTAssertEqual(allCancelled.count, jobCount)
    }

    func testConcurrentCancelAndCheck() async {
        let jobId = "concurrent-test-job"

        // Repeatedly cancel and check concurrently
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    await self.manager.cancel(jobId)
                }
                group.addTask {
                    _ = await self.manager.isCancelled(jobId)
                }
            }
        }

        // Job should definitely be cancelled after all that
        let finalState = await manager.isCancelled(jobId)
        XCTAssertTrue(finalState)
    }
}
