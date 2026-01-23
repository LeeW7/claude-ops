import Foundation

/// Protocol for job and worktree persistence
/// Supports both local (SQLite) and remote (Firestore) backends
public protocol PersistenceService: Actor {
    /// Initialize the service (load data, run migrations, etc.)
    func initialize() async throws

    // MARK: - Jobs

    /// Get all jobs (filtered to recent, max count)
    func getAllJobs() async throws -> [Job]

    /// Get a job by exact ID
    func getJob(id: String) async throws -> Job?

    /// Get a job by ID with fuzzy suffix matching
    func getJobFuzzy(id: String) async throws -> Job?

    /// Get all jobs for a specific issue
    func getJobsForIssue(repo: String, issueNum: Int) async throws -> [Job]

    /// Check if a job exists and is active (pending or running)
    func jobExistsAndActive(id: String) async throws -> Bool

    /// Create or update a job
    func saveJob(_ job: Job) async throws

    /// Update job status
    func updateJobStatus(id: String, status: JobStatus, error: String?) async throws

    /// Update the issue title for a job
    func updateJobIssueTitle(id: String, newTitle: String) async throws

    /// Update job as completed with session ID and cost data
    func updateJobCompleted(id: String, sessionId: String?, cost: JobCost?) async throws

    /// Mark all running jobs as interrupted (on startup)
    func markInterruptedJobs() async throws

    // MARK: - Worktrees

    /// Get all worktrees
    func getAllWorktrees() async throws -> [WorktreeService.WorktreeInfo]

    /// Save a worktree
    func saveWorktree(_ worktree: WorktreeService.WorktreeInfo) async throws

    /// Delete a worktree by issue key
    func deleteWorktree(issueKey: String) async throws
}
