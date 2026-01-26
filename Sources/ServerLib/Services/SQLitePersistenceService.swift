import Foundation
import GRDB

/// SQLite-based persistence service for local development
public actor SQLitePersistenceService: PersistenceService {
    private let dbPool: DatabasePool
    private let databasePath: String

    // Local cache for faster reads (same pattern as Firestore)
    private var jobsCache: [String: Job] = [:]
    private var lastCacheRefresh: Date?
    private let cacheValiditySeconds: TimeInterval = 5

    // Configuration
    private let maxJobAgeDays: Int = 30
    private let maxJobsToReturn: Int = 100

    /// Initialize with database path
    public init(databasePath: String) throws {
        self.databasePath = databasePath

        // Create database directory if needed
        let dbDir = (databasePath as NSString).deletingLastPathComponent
        if !dbDir.isEmpty && dbDir != "." {
            try FileManager.default.createDirectory(
                atPath: dbDir,
                withIntermediateDirectories: true
            )
        }

        // Open database pool for concurrent access
        self.dbPool = try DatabasePool(path: databasePath)

        print("[Persistence] SQLite database initialized at: \(databasePath)")
    }

    /// Initialize the service - run migrations and migrate from jobs.json if needed
    public func initialize() async throws {
        // Run migrations
        try SQLiteMigrations.migrator.migrate(dbPool)
        print("[Persistence] SQLite migrations complete")

        // Migrate from jobs.json if it exists
        try await migrateFromJobsJson()

        // Load cache
        let jobs = try await loadAllJobsFromDB()
        for job in jobs {
            jobsCache[job.id] = job
        }
        lastCacheRefresh = Date()
        print("[Persistence] Loaded \(jobs.count) jobs into cache")
    }

    // MARK: - Jobs

    public func getAllJobs() async throws -> [Job] {
        // Check cache validity
        if let lastRefresh = lastCacheRefresh,
           Date().timeIntervalSince(lastRefresh) < cacheValiditySeconds,
           !jobsCache.isEmpty {
            return filterAndLimitJobs(Array(jobsCache.values))
        }

        let jobs = try await loadAllJobsFromDB()

        // Update cache
        jobsCache.removeAll()
        for job in jobs {
            jobsCache[job.id] = job
        }
        lastCacheRefresh = Date()

        return filterAndLimitJobs(jobs)
    }

    public func getJob(id: String) async throws -> Job? {
        // Check cache first
        if let cached = jobsCache[id] {
            return cached
        }

        return try await dbPool.read { db in
            try JobRecord.fetchOne(db, key: id)?.toJob()
        }
    }

    public func getJobFuzzy(id: String) async throws -> Job? {
        // First try exact match
        if let job = try await getJob(id: id) {
            return job
        }

        // Try suffix match
        let allJobs = try await getAllJobs()
        let suffix = "-\(id)"
        return allJobs.first { $0.id.hasSuffix(suffix) }
    }

    public func getJobsForIssue(repo: String, issueNum: Int) async throws -> [Job] {
        let repoSlug = repo.split(separator: "/").last.map(String.init) ?? repo
        let prefix = "\(repoSlug)-\(issueNum)-"

        return try await dbPool.read { db in
            try JobRecord
                .filter(sql: "id LIKE ?", arguments: ["\(prefix)%"])
                .fetchAll(db)
                .map { $0.toJob() }
        }
    }

    public func jobExistsAndActive(id: String) async throws -> Bool {
        guard let job = try await getJob(id: id) else { return false }
        return job.status == .pending || job.status == .running
    }

    public func saveJob(_ job: Job) async throws {
        var mutableJob = job
        mutableJob.updatedAt = Date()

        let record = JobRecord(from: mutableJob)

        try await dbPool.write { db in
            try record.save(db)
        }

        jobsCache[job.id] = mutableJob
    }

    public func updateJobStatus(id: String, status: JobStatus, error: String? = nil) async throws {
        guard var job = try await getJob(id: id) else { return }

        job.status = status
        job.updatedAt = Date()

        if status == .completed || status == .failed {
            job.completedTime = Int(Date().timeIntervalSince1970)
        }

        if let error = error {
            job.error = error
        }

        try await saveJob(job)
    }

    public func updateJobIssueTitle(id: String, newTitle: String) async throws {
        guard var job = try await getJob(id: id) else { return }

        job.issueTitle = newTitle
        job.updatedAt = Date()

        try await saveJob(job)
    }

    public func updateJobCompleted(id: String, sessionId: String?, cost: JobCost?) async throws {
        guard var job = try await getJob(id: id) else { return }

        job.status = .completed
        job.completedTime = Int(Date().timeIntervalSince1970)
        job.updatedAt = Date()
        job.sessionId = sessionId
        job.cost = cost

        try await saveJob(job)
    }

    public func markInterruptedJobs() async throws {
        let allJobs = try await getAllJobs()

        for job in allJobs where job.status == .running {
            try await updateJobStatus(id: job.id, status: .interrupted)
        }
    }

    // MARK: - Worktrees

    public func getAllWorktrees() async throws -> [WorktreeService.WorktreeInfo] {
        try await dbPool.read { db in
            try WorktreeRecord.fetchAll(db).map { $0.toWorktreeInfo() }
        }
    }

    public func saveWorktree(_ worktree: WorktreeService.WorktreeInfo) async throws {
        let record = WorktreeRecord(from: worktree)

        try await dbPool.write { db in
            try record.save(db)
        }
    }

    public func deleteWorktree(issueKey: String) async throws {
        _ = try await dbPool.write { db in
            try WorktreeRecord.deleteOne(db, key: issueKey)
        }
    }

    // MARK: - Private Helpers

    private func loadAllJobsFromDB() async throws -> [Job] {
        try await dbPool.read { db in
            try JobRecord.fetchAll(db).map { $0.toJob() }
        }
    }

    private func filterAndLimitJobs(_ jobs: [Job]) -> [Job] {
        let cutoffTime = Int(Date().timeIntervalSince1970) - (maxJobAgeDays * 24 * 60 * 60)

        let filtered = jobs
            .filter { $0.startTime > cutoffTime }
            .sorted {
                // Primary sort by startTime (newest first)
                // Secondary sort by job ID for stable ordering when times are equal
                if $0.startTime != $1.startTime {
                    return $0.startTime > $1.startTime
                }
                return $0.id > $1.id
            }

        if filtered.count > maxJobsToReturn {
            return Array(filtered.prefix(maxJobsToReturn))
        }
        return filtered
    }

    // MARK: - Quick Sessions

    public func getAllQuickSessions() async throws -> [QuickSession] {
        try await dbPool.read { db in
            try QuickSessionRecord
                .order(QuickSessionRecord.Columns.lastActivity.desc)
                .fetchAll(db)
                .map { $0.toQuickSession() }
        }
    }

    public func getQuickSession(id: String) async throws -> QuickSession? {
        try await dbPool.read { db in
            try QuickSessionRecord.fetchOne(db, key: id)?.toQuickSession()
        }
    }

    public func getQuickSessionsForRepo(repo: String) async throws -> [QuickSession] {
        try await dbPool.read { db in
            try QuickSessionRecord
                .filter(QuickSessionRecord.Columns.repo == repo)
                .order(QuickSessionRecord.Columns.lastActivity.desc)
                .fetchAll(db)
                .map { $0.toQuickSession() }
        }
    }

    public func saveQuickSession(_ session: QuickSession) async throws {
        let record = QuickSessionRecord(from: session)
        try await dbPool.write { db in
            try record.save(db)
        }
    }

    public func deleteQuickSession(id: String) async throws {
        _ = try await dbPool.write { db in
            // Messages will be cascade deleted due to foreign key
            try QuickSessionRecord.deleteOne(db, key: id)
        }
    }

    public func getExpiredQuickSessions(olderThan: Date) async throws -> [QuickSession] {
        try await dbPool.read { db in
            try QuickSessionRecord
                .filter(QuickSessionRecord.Columns.createdAt < olderThan)
                .fetchAll(db)
                .map { $0.toQuickSession() }
        }
    }

    // MARK: - Quick Messages

    public func getQuickMessages(sessionId: String) async throws -> [QuickMessage] {
        try await dbPool.read { db in
            try QuickMessageRecord
                .filter(QuickMessageRecord.Columns.sessionId == sessionId)
                .order(QuickMessageRecord.Columns.timestamp.asc)
                .fetchAll(db)
                .map { $0.toQuickMessage() }
        }
    }

    public func saveQuickMessage(_ message: QuickMessage) async throws {
        let record = QuickMessageRecord(from: message)
        try await dbPool.write { db in
            try record.save(db)
        }
    }

    public func deleteQuickMessages(sessionId: String) async throws {
        _ = try await dbPool.write { db in
            try QuickMessageRecord
                .filter(QuickMessageRecord.Columns.sessionId == sessionId)
                .deleteAll(db)
        }
    }

    // MARK: - Migration from jobs.json

    private func migrateFromJobsJson() async throws {
        let jsonPath = FileManager.default.currentDirectoryPath + "/jobs.json"

        guard FileManager.default.fileExists(atPath: jsonPath) else {
            return
        }

        print("[Persistence] Found jobs.json, migrating to SQLite...")

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
            let jobs = try JSONDecoder().decode([String: Job].self, from: data)

            try await dbPool.write { db in
                for (_, job) in jobs {
                    let record = JobRecord(from: job)
                    try record.save(db)
                }
            }

            // Rename the old file to indicate migration
            let migratedPath = jsonPath + ".migrated"
            try FileManager.default.moveItem(atPath: jsonPath, toPath: migratedPath)

            print("[Persistence] Migrated \(jobs.count) jobs from jobs.json")
            print("[Persistence] Renamed jobs.json to jobs.json.migrated")
        } catch {
            print("[Persistence] Warning: Failed to migrate jobs.json: \(error)")
        }
    }
}
