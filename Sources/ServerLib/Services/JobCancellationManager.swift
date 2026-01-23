import Vapor
import Foundation

/// In-memory manager for job cancellation flags
/// Eliminates the need to poll Firestore to check if a job was cancelled
public actor JobCancellationManager {
    /// Set of job IDs that have been requested for cancellation
    private var cancelledJobs: Set<String> = []

    /// Request cancellation of a job
    public func cancel(_ jobId: String) {
        cancelledJobs.insert(jobId)
    }

    /// Check if a job has been cancelled
    public func isCancelled(_ jobId: String) -> Bool {
        cancelledJobs.contains(jobId)
    }

    /// Clear cancellation flag (call when job is fully terminated)
    public func clearCancellation(_ jobId: String) {
        cancelledJobs.remove(jobId)
    }

    /// Get all cancelled job IDs (for debugging)
    public func allCancelledJobs() -> Set<String> {
        cancelledJobs
    }
}

// MARK: - Application Extension

extension Application {
    private struct JobCancellationManagerKey: StorageKey {
        typealias Value = JobCancellationManager
    }

    public var jobCancellationManager: JobCancellationManager {
        get {
            if let existing = storage[JobCancellationManagerKey.self] {
                return existing
            }
            let manager = JobCancellationManager()
            storage[JobCancellationManagerKey.self] = manager
            return manager
        }
        set {
            storage[JobCancellationManagerKey.self] = newValue
        }
    }
}
