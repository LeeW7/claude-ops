import Vapor
import Foundation

/// Service for job persistence using local JSON file
/// (Firestore can be added later with proper server SDK)
public actor FirestoreService {
    private let jobsFile: String
    private var jobs: [String: Job] = [:]

    public init() {
        self.jobsFile = "jobs.json"
        loadJobs()
    }

    /// Load jobs from JSON file
    private func loadJobs() {
        let path = FileManager.default.currentDirectoryPath + "/" + jobsFile
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let loaded = try? JSONDecoder().decode([String: Job].self, from: data) else {
            jobs = [:]
            return
        }
        jobs = loaded
    }

    /// Save jobs to JSON file
    private func saveJobs() {
        let path = FileManager.default.currentDirectoryPath + "/" + jobsFile
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Jobs

    /// Get all jobs
    public func getAllJobs() async throws -> [Job] {
        return Array(jobs.values).sorted { $0.startTime > $1.startTime }
    }

    /// Get active jobs only
    public func getActiveJobs() async throws -> [Job] {
        return Array(jobs.values)
            .filter { $0.status.isActive }
            .sorted { $0.startTime > $1.startTime }
    }

    /// Get job by ID
    public func getJob(id: String) async throws -> Job? {
        return jobs[id]
    }

    /// Get job by ID with fuzzy matching (suffix match)
    public func getJobFuzzy(id: String) async throws -> Job? {
        // First try exact match
        if let job = jobs[id] {
            return job
        }

        // Try suffix match
        let suffix = "-\(id)"
        return jobs.values.first { $0.id.hasSuffix(suffix) }
    }

    /// Create or update a job
    public func saveJob(_ job: Job) async throws {
        var mutableJob = job
        mutableJob.updatedAt = Date()
        jobs[job.id] = mutableJob
        saveJobs()
    }

    /// Update job status
    public func updateJobStatus(id: String, status: JobStatus, error: String? = nil) async throws {
        guard var job = jobs[id] else { return }

        job.status = status
        job.updatedAt = Date()

        if status == .completed || status == .failed {
            job.completedTime = Int(Date().timeIntervalSince1970)
        }

        if let error = error {
            job.error = error
        }

        jobs[id] = job
        saveJobs()
    }

    /// Get jobs for a specific issue
    public func getJobsForIssue(repo: String, issueNum: Int) async throws -> [Job] {
        let repoSlug = repo.split(separator: "/").last.map(String.init) ?? repo
        let prefix = "\(repoSlug)-\(issueNum)-"

        return jobs.values.filter { $0.id.hasPrefix(prefix) }
    }

    /// Check if job already exists and is pending/running
    public func jobExistsAndActive(id: String) async throws -> Bool {
        guard let job = jobs[id] else { return false }
        return job.status == .pending || job.status == .running
    }

    /// Mark interrupted jobs on startup
    public func markInterruptedJobs() async throws {
        for (id, job) in jobs {
            if job.status == .running {
                var mutableJob = job
                mutableJob.status = .interrupted
                mutableJob.updatedAt = Date()
                jobs[id] = mutableJob
            }
        }
        saveJobs()
    }

    // MARK: - Repositories

    /// Get all repositories (not used with file-based storage)
    public func getAllRepositories() async throws -> [Repository] {
        return []
    }

    /// Get job count by status
    public func getJobCounts() async -> [JobStatus: Int] {
        var counts: [JobStatus: Int] = [:]
        for job in jobs.values {
            counts[job.status, default: 0] += 1
        }
        return counts
    }
}
