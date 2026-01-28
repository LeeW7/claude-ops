import Vapor
import Foundation

/// Service for job persistence using Firestore REST API
public actor FirestoreService: PersistenceService {
    private let authService: GoogleAuthService?
    private let projectId: String
    private let baseURL: String

    // Local cache for faster reads
    private var jobsCache: [String: Job] = [:]
    private var lastCacheRefresh: Date?
    private let cacheValiditySeconds: TimeInterval = 5

    // Fallback to local storage if Firestore unavailable
    private let localJobsFile = "jobs.json"
    private var useLocalFallback: Bool

    public init() {
        // Try to load service account credentials
        let serviceAccountPath = FileManager.default.currentDirectoryPath + "/service-account.json"

        do {
            let auth = try GoogleAuthService(serviceAccountPath: serviceAccountPath)
            self.authService = auth
            self.projectId = auth.projectId
            self.baseURL = "https://firestore.googleapis.com/v1/projects/\(auth.projectId)/databases/(default)/documents"
            self.useLocalFallback = false
            print("[Firestore] Initialized with project: \(auth.projectId)")
        } catch {
            // Fallback: use local storage if service account not found
            print("[Firestore] Service account not found, using local storage fallback: \(error)")
            self.authService = nil
            self.projectId = ""
            self.baseURL = ""
            self.useLocalFallback = true
        }
    }

    /// Load local jobs after initialization (must be called separately due to actor isolation)
    public func initialize() async {
        if useLocalFallback {
            loadLocalJobs()
        }
    }

    /// Initialize with explicit service account path
    public init(serviceAccountPath: String) throws {
        let auth = try GoogleAuthService(serviceAccountPath: serviceAccountPath)
        self.authService = auth
        self.projectId = auth.projectId
        self.baseURL = "https://firestore.googleapis.com/v1/projects/\(auth.projectId)/databases/(default)/documents"
        self.useLocalFallback = false
    }

    // MARK: - Jobs Collection

    /// Configuration for job queries
    private let maxJobAgeDays: Int = 30
    private let maxJobsToReturn: Int = 100

    /// Get all jobs (filtered to last 30 days, max 100 results)
    public func getAllJobs() async throws -> [Job] {
        if useLocalFallback {
            return filterAndLimitJobs(Array(jobsCache.values))
        }

        // Check cache validity
        if let lastRefresh = lastCacheRefresh,
           Date().timeIntervalSince(lastRefresh) < cacheValiditySeconds,
           !jobsCache.isEmpty {
            return filterAndLimitJobs(Array(jobsCache.values))
        }

        let url = "\(baseURL)/jobs"
        let documents = try await listDocuments(at: url)

        var jobs: [Job] = []
        for doc in documents {
            if let job = try? parseJob(from: doc) {
                jobs.append(job)
                jobsCache[job.id] = job
            }
        }

        lastCacheRefresh = Date()
        return filterAndLimitJobs(jobs)
    }

    /// Filter jobs to recent ones and limit count
    private func filterAndLimitJobs(_ jobs: [Job]) -> [Job] {
        let cutoffTime = Int(Date().timeIntervalSince1970) - (maxJobAgeDays * 24 * 60 * 60)

        // Filter to jobs within maxJobAgeDays and sort by start time descending
        // Secondary sort by job ID ensures stable ordering when times are equal
        let filtered = jobs
            .filter { $0.startTime > cutoffTime }
            .sorted {
                if $0.startTime != $1.startTime {
                    return $0.startTime > $1.startTime
                }
                return $0.id > $1.id
            }

        // Limit results
        if filtered.count > maxJobsToReturn {
            return Array(filtered.prefix(maxJobsToReturn))
        }
        return filtered
    }

    /// Get active jobs only
    public func getActiveJobs() async throws -> [Job] {
        let allJobs = try await getAllJobs()
        return allJobs.filter { $0.status.isActive }
    }

    /// Get job by ID
    public func getJob(id: String) async throws -> Job? {
        // Check cache first
        if let cached = jobsCache[id] {
            return cached
        }

        if useLocalFallback {
            return nil
        }

        let url = "\(baseURL)/jobs/\(id)"
        guard let doc = try await getDocument(at: url) else {
            return nil
        }

        let job = try parseJob(from: doc)
        jobsCache[job.id] = job
        return job
    }

    /// Get job by ID with fuzzy matching (suffix match)
    public func getJobFuzzy(id: String) async throws -> Job? {
        // First try exact match
        if let job = try await getJob(id: id) {
            return job
        }

        // Try suffix match from cache/all jobs
        let allJobs = try await getAllJobs()
        let suffix = "-\(id)"
        return allJobs.first { $0.id.hasSuffix(suffix) }
    }

    /// Create or update a job
    public func saveJob(_ job: Job) async throws {
        var mutableJob = job
        mutableJob.updatedAt = Date()

        jobsCache[job.id] = mutableJob

        if useLocalFallback {
            saveLocalJobs()
            return
        }

        let url = "\(baseURL)/jobs/\(job.id)"
        let firestoreDoc = jobToFirestoreDocument(mutableJob)
        try await setDocument(at: url, data: firestoreDoc)
    }

    /// Update job status
    public func updateJobStatus(id: String, status: JobStatus, error: String? = nil) async throws {
        // Get job from cache or fetch it
        var job: Job?
        if let cached = jobsCache[id] {
            job = cached
        } else {
            job = try await getJob(id: id)
        }

        guard var mutableJob = job else { return }

        mutableJob.status = status
        mutableJob.updatedAt = Date()

        if status == .completed || status == .failed {
            mutableJob.completedTime = Int(Date().timeIntervalSince1970)
        }

        if let error = error {
            mutableJob.error = error
        }

        try await saveJob(mutableJob)
    }

    /// Update the issue title for a job (used when Claude updates the issue)
    public func updateJobIssueTitle(id: String, newTitle: String) async throws {
        var job: Job?

        // Try cache first
        if let cached = jobsCache[id] {
            job = cached
        } else {
            job = try await getJob(id: id)
        }

        guard var mutableJob = job else { return }

        mutableJob.issueTitle = newTitle
        mutableJob.updatedAt = Date()

        try await saveJob(mutableJob)
    }

    /// Update job as completed with session ID and cost data
    public func updateJobCompleted(id: String, sessionId: String?, cost: JobCost?) async throws {
        var job: Job?

        // Try cache first
        if let cached = jobsCache[id] {
            job = cached
        } else {
            job = try await getJob(id: id)
        }

        guard var mutableJob = job else { return }

        mutableJob.status = .completed
        mutableJob.completedTime = Int(Date().timeIntervalSince1970)
        mutableJob.updatedAt = Date()
        mutableJob.sessionId = sessionId
        mutableJob.cost = cost

        try await saveJob(mutableJob)

        // Update daily analytics if we have cost data
        if let cost = cost {
            let today = formatDate(Date())
            try await updateDailyAnalytics(date: today, cost: cost)
        }
    }

    /// Get jobs for a specific issue
    public func getJobsForIssue(repo: String, issueNum: Int) async throws -> [Job] {
        let allJobs = try await getAllJobs()
        let repoSlug = repo.split(separator: "/").last.map(String.init) ?? repo
        let prefix = "\(repoSlug)-\(issueNum)-"

        return allJobs.filter { $0.id.hasPrefix(prefix) }
    }

    /// Check if job already exists and is pending/running
    public func jobExistsAndActive(id: String) async throws -> Bool {
        guard let job = try await getJob(id: id) else { return false }
        return job.status == .pending || job.status == .running
    }

    /// Mark interrupted jobs on startup
    public func markInterruptedJobs() async throws {
        let allJobs = try await getAllJobs()

        for job in allJobs where job.status == .running {
            try await updateJobStatus(id: job.id, status: .interrupted)
        }
    }

    // MARK: - Repositories

    /// Get all repositories (delegated to RepoMap)
    public func getAllRepositories() async throws -> [Repository] {
        return []
    }

    /// Get job count by status
    public func getJobCounts() async -> [JobStatus: Int] {
        let allJobs = (try? await getAllJobs()) ?? []
        var counts: [JobStatus: Int] = [:]
        for job in allJobs {
            counts[job.status, default: 0] += 1
        }
        return counts
    }

    // MARK: - Worktrees Collection

    /// Get all worktrees
    public func getAllWorktrees() async throws -> [WorktreeService.WorktreeInfo] {
        if useLocalFallback {
            return []
        }

        let url = "\(baseURL)/worktrees"
        let documents = try await listDocuments(at: url)

        var worktrees: [WorktreeService.WorktreeInfo] = []
        for doc in documents {
            if let worktree = try? parseWorktree(from: doc) {
                worktrees.append(worktree)
            }
        }

        return worktrees
    }

    /// Get worktree by issue key
    public func getWorktree(issueKey: String) async throws -> WorktreeService.WorktreeInfo? {
        if useLocalFallback {
            return nil
        }

        let url = "\(baseURL)/worktrees/\(issueKey)"
        guard let doc = try await getDocument(at: url) else {
            return nil
        }

        return try parseWorktree(from: doc)
    }

    /// Save a worktree
    public func saveWorktree(_ worktree: WorktreeService.WorktreeInfo) async throws {
        if useLocalFallback {
            return
        }

        let url = "\(baseURL)/worktrees/\(worktree.issueKey)"
        let firestoreDoc = worktreeToFirestoreDocument(worktree)
        try await setDocument(at: url, data: firestoreDoc)
    }

    /// Delete a worktree
    public func deleteWorktree(issueKey: String) async throws {
        if useLocalFallback {
            return
        }

        guard let auth = authService else {
            throw FirestoreError.notConfigured
        }

        let token = try await auth.getAccessToken()
        let url = "\(baseURL)/worktrees/\(issueKey)"

        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        // 404 is OK - worktree may not exist
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 && httpResponse.statusCode != 404 {
            throw FirestoreError.requestFailed(httpResponse.statusCode, "Failed to delete worktree")
        }
    }

    private func worktreeToFirestoreDocument(_ worktree: WorktreeService.WorktreeInfo) -> [String: Any] {
        return ["fields": [
            "issue_key": ["stringValue": worktree.issueKey],
            "path": ["stringValue": worktree.path],
            "repo": ["stringValue": worktree.repo],
            "issue_num": ["integerValue": String(worktree.issueNum)],
            "branch": ["stringValue": worktree.branch],
            "created_at": ["timestampValue": iso8601String(worktree.createdAt)]
        ]]
    }

    private func parseWorktree(from document: [String: Any]) throws -> WorktreeService.WorktreeInfo {
        guard let fields = document["fields"] as? [String: Any] else {
            throw FirestoreError.invalidDocument
        }

        func getString(_ key: String) -> String {
            (fields[key] as? [String: Any])?["stringValue"] as? String ?? ""
        }

        func getInt(_ key: String) -> Int {
            if let intStr = (fields[key] as? [String: Any])?["integerValue"] as? String {
                return Int(intStr) ?? 0
            }
            return 0
        }

        func getDate(_ key: String) -> Date {
            if let timestamp = (fields[key] as? [String: Any])?["timestampValue"] as? String {
                return parseISO8601(timestamp) ?? Date()
            }
            return Date()
        }

        return WorktreeService.WorktreeInfo(
            issueKey: getString("issue_key"),
            path: getString("path"),
            repo: getString("repo"),
            issueNum: getInt("issue_num"),
            branch: getString("branch"),
            createdAt: getDate("created_at")
        )
    }

    // MARK: - Quick Sessions (Local only - not synced to Firestore)

    /// Quick sessions are only stored locally, not in Firestore
    /// These stub implementations return empty/nil values

    public func getAllQuickSessions() async throws -> [QuickSession] {
        // Quick sessions not supported in Firestore backend
        return []
    }

    public func getQuickSession(id: String) async throws -> QuickSession? {
        return nil
    }

    public func getQuickSessionsForRepo(repo: String) async throws -> [QuickSession] {
        return []
    }

    public func saveQuickSession(_ session: QuickSession) async throws {
        // No-op for Firestore backend
    }

    public func deleteQuickSession(id: String) async throws {
        // No-op for Firestore backend
    }

    public func getExpiredQuickSessions(olderThan: Date) async throws -> [QuickSession] {
        return []
    }

    public func getQuickMessages(sessionId: String) async throws -> [QuickMessage] {
        return []
    }

    public func saveQuickMessage(_ message: QuickMessage) async throws {
        // No-op for Firestore backend
    }

    public func deleteQuickMessages(sessionId: String) async throws {
        // No-op for Firestore backend
    }

    // MARK: - Hidden Issues (Local only - not synced to Firestore)

    public func getAllHiddenIssues() async throws -> [HiddenIssue] {
        // Hidden issues not supported in Firestore backend
        return []
    }

    public func saveHiddenIssue(_ issue: HiddenIssue) async throws {
        // No-op for Firestore backend
    }

    public func deleteHiddenIssue(issueKey: String) async throws {
        // No-op for Firestore backend
    }

    // MARK: - Job Decisions (Local only - not synced to Firestore)

    public func getDecisionsForJob(jobId: String) async throws -> [JobDecision] {
        // Job decisions not supported in Firestore backend
        return []
    }

    public func saveDecision(_ decision: JobDecision) async throws {
        // No-op for Firestore backend
    }

    public func saveDecisions(_ decisions: [JobDecision]) async throws {
        // No-op for Firestore backend
    }

    public func deleteDecisionsForJob(jobId: String) async throws {
        // No-op for Firestore backend
    }

    // MARK: - Confidence Assessments (Local only - not synced to Firestore)

    public func getConfidenceForJob(jobId: String) async throws -> ConfidenceAssessment? {
        // Confidence assessments not supported in Firestore backend
        return nil
    }

    public func saveConfidence(_ confidence: ConfidenceAssessment) async throws {
        // No-op for Firestore backend
    }

    public func deleteConfidenceForJob(jobId: String) async throws {
        // No-op for Firestore backend
    }

    // MARK: - Analytics (Phase 5)

    /// Record job cost for analytics
    public func recordJobCost(jobId: String, cost: JobCost) async throws {
        if useLocalFallback { return }

        // Update job with cost info
        if var job = try await getJob(id: jobId) {
            job.cost = cost
            try await saveJob(job)
        }

        // Update daily analytics
        let today = formatDate(Date())
        try await updateDailyAnalytics(date: today, cost: cost)
    }

    /// Update daily analytics aggregate
    private func updateDailyAnalytics(date: String, cost: JobCost) async throws {
        let url = "\(baseURL)/analytics/default/daily/\(date)"

        // Get existing or create new
        var analytics: DailyAnalytics
        if let doc = try await getDocument(at: url),
           let existing = try? parseDailyAnalytics(from: doc) {
            analytics = existing
        } else {
            analytics = DailyAnalytics(date: date)
        }

        // Update aggregates
        analytics.totalCost += cost.totalUsd
        analytics.jobCount += 1
        analytics.inputTokens += cost.inputTokens
        analytics.outputTokens += cost.outputTokens
        analytics.cacheReadTokens += cost.cacheReadTokens
        analytics.cacheCreationTokens += cost.cacheCreationTokens

        // Save back
        let firestoreDoc = analyticsToFirestoreDocument(analytics)
        try await setDocument(at: url, data: firestoreDoc)
    }

    // MARK: - Firestore REST API Helpers

    private func getDocument(at url: String) async throws -> [String: Any]? {
        guard let auth = authService else {
            throw FirestoreError.notConfigured
        }

        let token = try await auth.getAccessToken()

        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return nil
        }

        if httpResponse.statusCode == 404 {
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw FirestoreError.requestFailed(httpResponse.statusCode, errorBody)
        }

        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func listDocuments(at url: String) async throws -> [[String: Any]] {
        guard let auth = authService else {
            return []
        }

        let token = try await auth.getAccessToken()

        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return []
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let documents = json["documents"] as? [[String: Any]] else {
            return []
        }

        return documents
    }

    private func setDocument(at url: String, data: [String: Any]) async throws {
        guard let auth = authService else {
            throw FirestoreError.notConfigured
        }

        let token = try await auth.getAccessToken()

        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: data)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorBody = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw FirestoreError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? 0, errorBody)
        }
    }

    // MARK: - Firestore Document Conversion

    private func jobToFirestoreDocument(_ job: Job) -> [String: Any] {
        var fields: [String: Any] = [
            "id": ["stringValue": job.id],
            "repo": ["stringValue": job.repo],
            "repo_slug": ["stringValue": job.repoSlug],
            "issue_num": ["integerValue": String(job.issueNum)],
            "issue_title": ["stringValue": job.issueTitle],
            "command": ["stringValue": job.command],
            "status": ["stringValue": job.status.rawValue],
            "start_time": ["integerValue": String(job.startTime)],
            "log_path": ["stringValue": job.logPath],
            "local_path": ["stringValue": job.localPath],
            "full_command": ["stringValue": job.fullCommand],
            "created_at": ["timestampValue": iso8601String(job.createdAt)],
            "updated_at": ["timestampValue": iso8601String(job.updatedAt)]
        ]

        if let completedTime = job.completedTime {
            fields["completed_time"] = ["integerValue": String(completedTime)]
        }

        if let error = job.error {
            fields["error"] = ["stringValue": error]
        }

        if let cost = job.cost {
            fields["cost"] = ["mapValue": ["fields": [
                "total_usd": ["doubleValue": cost.totalUsd],
                "input_tokens": ["integerValue": String(cost.inputTokens)],
                "output_tokens": ["integerValue": String(cost.outputTokens)],
                "cache_read_tokens": ["integerValue": String(cost.cacheReadTokens)],
                "cache_creation_tokens": ["integerValue": String(cost.cacheCreationTokens)],
                "model": ["stringValue": cost.model]
            ]]]
        }

        return ["fields": fields]
    }

    private func parseJob(from document: [String: Any]) throws -> Job {
        guard let fields = document["fields"] as? [String: Any] else {
            throw FirestoreError.invalidDocument
        }

        func getString(_ key: String) -> String {
            (fields[key] as? [String: Any])?["stringValue"] as? String ?? ""
        }

        func getInt(_ key: String) -> Int {
            if let intStr = (fields[key] as? [String: Any])?["integerValue"] as? String {
                return Int(intStr) ?? 0
            }
            return 0
        }

        func getDate(_ key: String) -> Date {
            if let timestamp = (fields[key] as? [String: Any])?["timestampValue"] as? String {
                return parseISO8601(timestamp) ?? Date()
            }
            return Date()
        }

        var job = Job(
            repo: getString("repo"),
            issueNum: getInt("issue_num"),
            issueTitle: getString("issue_title"),
            command: getString("command"),
            localPath: getString("local_path")
        )

        job.status = JobStatus(rawValue: getString("status")) ?? .pending
        job.completedTime = getInt("completed_time") != 0 ? getInt("completed_time") : nil
        job.error = getString("error").isEmpty ? nil : getString("error")
        job.updatedAt = getDate("updated_at")

        // Parse cost if present
        if let costMap = (fields["cost"] as? [String: Any])?["mapValue"] as? [String: Any],
           let costFields = costMap["fields"] as? [String: Any] {
            job.cost = JobCost(
                totalUsd: (costFields["total_usd"] as? [String: Any])?["doubleValue"] as? Double ?? 0,
                inputTokens: Int((costFields["input_tokens"] as? [String: Any])?["integerValue"] as? String ?? "0") ?? 0,
                outputTokens: Int((costFields["output_tokens"] as? [String: Any])?["integerValue"] as? String ?? "0") ?? 0,
                cacheReadTokens: Int((costFields["cache_read_tokens"] as? [String: Any])?["integerValue"] as? String ?? "0") ?? 0,
                cacheCreationTokens: Int((costFields["cache_creation_tokens"] as? [String: Any])?["integerValue"] as? String ?? "0") ?? 0,
                model: (costFields["model"] as? [String: Any])?["stringValue"] as? String ?? "unknown"
            )
        }

        return job
    }

    private func analyticsToFirestoreDocument(_ analytics: DailyAnalytics) -> [String: Any] {
        return ["fields": [
            "date": ["stringValue": analytics.date],
            "total_cost": ["doubleValue": analytics.totalCost],
            "job_count": ["integerValue": String(analytics.jobCount)],
            "input_tokens": ["integerValue": String(analytics.inputTokens)],
            "output_tokens": ["integerValue": String(analytics.outputTokens)],
            "cache_read_tokens": ["integerValue": String(analytics.cacheReadTokens)],
            "cache_creation_tokens": ["integerValue": String(analytics.cacheCreationTokens)]
        ]]
    }

    private func parseDailyAnalytics(from document: [String: Any]) throws -> DailyAnalytics {
        guard let fields = document["fields"] as? [String: Any] else {
            throw FirestoreError.invalidDocument
        }

        func getString(_ key: String) -> String {
            (fields[key] as? [String: Any])?["stringValue"] as? String ?? ""
        }

        func getDouble(_ key: String) -> Double {
            (fields[key] as? [String: Any])?["doubleValue"] as? Double ?? 0
        }

        func getInt(_ key: String) -> Int {
            if let intStr = (fields[key] as? [String: Any])?["integerValue"] as? String {
                return Int(intStr) ?? 0
            }
            return 0
        }

        return DailyAnalytics(
            date: getString("date"),
            totalCost: getDouble("total_cost"),
            jobCount: getInt("job_count"),
            inputTokens: getInt("input_tokens"),
            outputTokens: getInt("output_tokens"),
            cacheReadTokens: getInt("cache_read_tokens"),
            cacheCreationTokens: getInt("cache_creation_tokens")
        )
    }

    // MARK: - Utility Functions

    private func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Local Fallback

    private func loadLocalJobs() {
        let path = FileManager.default.currentDirectoryPath + "/" + localJobsFile
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let loaded = try? JSONDecoder().decode([String: Job].self, from: data) else {
            jobsCache = [:]
            return
        }
        jobsCache = loaded
    }

    private func saveLocalJobs() {
        let path = FileManager.default.currentDirectoryPath + "/" + localJobsFile
        guard let data = try? JSONEncoder().encode(jobsCache) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - Supporting Types

public struct JobCost: Codable, Sendable {
    public var totalUsd: Double
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheCreationTokens: Int
    public var model: String

    public init(
        totalUsd: Double = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        model: String = "unknown"
    ) {
        self.totalUsd = totalUsd
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.model = model
    }
}

struct DailyAnalytics {
    var date: String
    var totalCost: Double
    var jobCount: Int
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheCreationTokens: Int

    init(
        date: String,
        totalCost: Double = 0,
        jobCount: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheCreationTokens: Int = 0
    ) {
        self.date = date
        self.totalCost = totalCost
        self.jobCount = jobCount
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
    }
}

enum FirestoreError: Error {
    case requestFailed(Int, String)
    case invalidDocument
    case notConfigured
}
