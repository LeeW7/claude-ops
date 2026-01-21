import SwiftUI
import Vapor
import ServerLib
import UserNotifications

/// Manages the Vapor server lifecycle and provides job data to the UI
@MainActor
class ServerManager: ObservableObject {
    @Published var isRunning = false
    @Published var isStarting = false
    @Published var jobs: [Job] = []
    @Published var repositories: [Repository] = []
    @Published var errorMessage: String?
    @Published var serverUptime: TimeInterval = 0

    var activeJobCount: Int {
        jobs.filter { $0.status.isActive }.count
    }

    var activeJobs: [Job] {
        jobs.filter { $0.status.isActive }
    }

    var recentJobs: [Job] {
        Array(jobs.prefix(10))
    }

    private var app: Application?
    private var refreshTask: Task<Void, Never>?
    private var uptimeTask: Task<Void, Never>?
    private var startTime: Date?

    init() {
        // Auto-start if enabled
        if UserDefaults.standard.bool(forKey: "autoLaunchServer") {
            Task {
                await startServer()
            }
        }

        // Request notification permissions (delayed to avoid crash in non-bundled apps)
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                requestNotificationPermissions()
            }
        }
    }

    deinit {
        refreshTask?.cancel()
        uptimeTask?.cancel()
    }

    // MARK: - Server Control

    func startServer() async {
        guard !isRunning && !isStarting else { return }

        isStarting = true
        errorMessage = nil

        do {
            // Change to the working directory where config files are
            let workingDir = getWorkingDirectory()
            FileManager.default.changeCurrentDirectoryPath(workingDir)

            app = try await startServerInBackground()
            isRunning = true
            startTime = Date()

            // Start refresh loop
            startRefreshLoop()
            startUptimeLoop()

            // Load initial data
            await refreshData()

            sendNotification(title: "Claude Ops", body: "Server started on port 5001")
        } catch {
            errorMessage = error.localizedDescription
            sendNotification(title: "Claude Ops Error", body: "Failed to start server")
        }

        isStarting = false
    }

    func stopServer() async {
        guard isRunning, let app = app else { return }

        refreshTask?.cancel()
        uptimeTask?.cancel()

        do {
            try await app.asyncShutdown()
        } catch {
            print("Error shutting down: \(error)")
        }

        self.app = nil
        isRunning = false
        startTime = nil
        serverUptime = 0

        sendNotification(title: "Claude Ops", body: "Server stopped")
    }

    func restartServer() async {
        await stopServer()
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
        await startServer()
    }

    // MARK: - Data Refresh

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await refreshData()
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            }
        }
    }

    private func startUptimeLoop() {
        uptimeTask?.cancel()
        uptimeTask = Task {
            while !Task.isCancelled {
                if let start = startTime {
                    serverUptime = Date().timeIntervalSince(start)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
    }

    func refreshData() async {
        guard let app = app else { return }

        do {
            let allJobs = try await app.firestoreService.getAllJobs()
            let previousActiveCount = activeJobCount

            await MainActor.run {
                self.jobs = allJobs
            }

            // Notify on job completion
            let newActiveCount = allJobs.filter { $0.status.isActive }.count
            if newActiveCount < previousActiveCount {
                // A job completed
                if let completedJob = allJobs.first(where: { $0.status == .completed }) {
                    sendNotification(
                        title: "Job Complete",
                        body: "\(completedJob.shortCommand) for #\(completedJob.issueNum) finished"
                    )
                }
            }

            // Load repositories
            if let repoMap = app.repoMap {
                await MainActor.run {
                    self.repositories = repoMap.allRepositories()
                }
            }
        } catch {
            print("Error refreshing data: \(error)")
        }
    }

    // MARK: - Job Actions

    func approveJob(_ job: Job) async {
        guard let app = app else { return }

        do {
            try await app.firestoreService.updateJobStatus(id: job.id, status: .approvedResume)
            await refreshData()
        } catch {
            errorMessage = "Failed to approve job: \(error.localizedDescription)"
        }
    }

    func rejectJob(_ job: Job) async {
        guard let app = app else { return }

        do {
            try await app.firestoreService.updateJobStatus(id: job.id, status: .rejected)
            await app.claudeService.terminateProcess(job.id)
            await refreshData()
        } catch {
            errorMessage = "Failed to reject job: \(error.localizedDescription)"
        }
    }

    func getJobLogs(_ job: Job) async -> String {
        guard let app = app else { return "Server not running" }
        return await app.claudeService.readLog(path: job.logPath)
    }

    // MARK: - Utilities

    private func getWorkingDirectory() -> String {
        // Check common locations for the config files
        let candidates = [
            // Application Support directory (preferred for bundled apps)
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("ClaudeOps").path,
            // Current directory (for development)
            FileManager.default.currentDirectoryPath,
            // Bundle parent directory (for development builds)
            Bundle.main.bundlePath + "/../.."
        ].compactMap { $0 }

        for path in candidates {
            let repoMapPath = path + "/repo_map.json"
            if FileManager.default.fileExists(atPath: repoMapPath) {
                return path
            }
        }

        return FileManager.default.currentDirectoryPath
    }

    // MARK: - Notifications

    private var notificationsAvailable = false

    private func requestNotificationPermissions() {
        // Check if we have a proper bundle (required for notifications)
        guard Bundle.main.bundleIdentifier != nil else {
            print("Notifications not available - no bundle identifier")
            return
        }

        notificationsAvailable = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func sendNotification(title: String, body: String) {
        guard notificationsAvailable else { return }
        guard UserDefaults.standard.bool(forKey: "showNotifications") else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Health Checks

    var healthStatus: HealthStatus {
        HealthStatus(
            serverRunning: isRunning,
            ghCliInstalled: checkGhCli(),
            claudeCliInstalled: checkClaudeCli(),
            repoCount: repositories.count,
            activeJobs: activeJobCount
        )
    }

    private func checkGhCli() -> Bool {
        // Check common installation paths directly (app doesn't inherit shell PATH)
        let paths = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh"
        ]
        return paths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func checkClaudeCli() -> Bool {
        // Check common installation paths directly (app doesn't inherit shell PATH)
        let paths = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin/claude",
            "/usr/bin/claude"
        ]
        return paths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

struct HealthStatus {
    let serverRunning: Bool
    let ghCliInstalled: Bool
    let claudeCliInstalled: Bool
    let repoCount: Int
    let activeJobs: Int

    var allGood: Bool {
        serverRunning && ghCliInstalled && claudeCliInstalled && repoCount > 0
    }
}
