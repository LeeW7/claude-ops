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

    // MARK: - Quick Sessions

    /// Get all quick sessions
    func getAllQuickSessions() async throws -> [QuickSession]

    /// Get a quick session by ID
    func getQuickSession(id: String) async throws -> QuickSession?

    /// Get quick sessions for a repo
    func getQuickSessionsForRepo(repo: String) async throws -> [QuickSession]

    /// Save a quick session
    func saveQuickSession(_ session: QuickSession) async throws

    /// Delete a quick session
    func deleteQuickSession(id: String) async throws

    /// Get expired sessions (older than specified date)
    func getExpiredQuickSessions(olderThan: Date) async throws -> [QuickSession]

    // MARK: - Quick Messages

    /// Get all messages for a session
    func getQuickMessages(sessionId: String) async throws -> [QuickMessage]

    /// Save a quick message
    func saveQuickMessage(_ message: QuickMessage) async throws

    /// Delete all messages for a session
    func deleteQuickMessages(sessionId: String) async throws

    // MARK: - Hidden Issues

    /// Get all hidden issues
    func getAllHiddenIssues() async throws -> [HiddenIssue]

    /// Save/upsert a hidden issue
    func saveHiddenIssue(_ issue: HiddenIssue) async throws

    /// Delete a hidden issue by key
    func deleteHiddenIssue(issueKey: String) async throws

    // MARK: - Job Decisions

    /// Get all decisions for a job
    func getDecisionsForJob(jobId: String) async throws -> [JobDecision]

    /// Save a single decision
    func saveDecision(_ decision: JobDecision) async throws

    /// Save multiple decisions
    func saveDecisions(_ decisions: [JobDecision]) async throws

    /// Delete all decisions for a job
    func deleteDecisionsForJob(jobId: String) async throws
}
