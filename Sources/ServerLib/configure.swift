import Vapor

/// Called before your application initializes.
public func configure(_ app: Application) async throws {
    // Bind to all interfaces so Tailscale can reach it
    // Default port 5001 (different from Python server's 5000 for parallel testing)
    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = 5001

    // CORS middleware
    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith]
    )
    let cors = CORSMiddleware(configuration: corsConfiguration)
    app.middleware.use(cors)

    // Initialize persistence service based on STORAGE_BACKEND environment variable
    // Default to SQLite ("local") for easier local development
    let storageBackend = Environment.get("STORAGE_BACKEND") ?? "local"
    let persistenceService: any PersistenceService

    switch storageBackend {
    case "firestore":
        print("[Persistence] Using Firestore backend")
        persistenceService = FirestoreService()
    default:
        print("[Persistence] Using SQLite backend")
        let dbPath = app.directory.workingDirectory + "claude-ops.db"
        persistenceService = try SQLitePersistenceService(databasePath: dbPath)
    }

    try await persistenceService.initialize()
    app.persistenceService = persistenceService

    app.githubService = GitHubService()
    app.claudeService = ClaudeService(app: app)
    app.pushNotificationService = PushNotificationService()
    app.geminiService = GeminiService()
    let worktreeService = WorktreeService(app: app, persistenceService: persistenceService)
    await worktreeService.loadFromPersistence()
    app.worktreeService = worktreeService
    app.webSocketManager = WebSocketManager()

    // Initialize pricing service (fetches latest pricing from Anthropic)
    let pricingService = PricingService()
    await pricingService.initialize()
    app.pricingService = pricingService

    // Load repo map
    let repoMapPath = app.directory.workingDirectory + "repo_map.json"
    do {
        app.repoMap = try RepoMap.load(from: repoMapPath)
        app.logger.info("[Setup] Loaded repo_map.json with \(app.repoMap?.allRepositories().count ?? 0) repositories")
    } catch {
        app.logger.error("[Setup] CRITICAL: Failed to load repo_map.json: \(error.localizedDescription)")
        app.logger.error("[Setup] The server cannot function without repo_map.json - webhook processing and job execution will not work.")
        app.logger.error("[Setup] Create repo_map.json in the working directory and restart the server.")
        app.repoMap = nil
    }

    // Validate repos have required labels and local commands (run in background)
    if let repoMap = app.repoMap {
        let repositories = repoMap.allRepositories()
        let githubService = app.githubService
        Task {
            // Validate GitHub labels
            app.logger.info("[Setup] Validating \(repositories.count) repositories have required labels...")
            let labelResults = await githubService.validateRepos(repos: repositories.map { $0.fullName })
            if labelResults.isEmpty {
                app.logger.info("[Setup] All repositories have required GitHub labels")
            } else {
                for (repo, labels) in labelResults {
                    app.logger.info("[Setup] Created labels on \(repo): \(labels.joined(separator: ", "))")
                }
            }

            // Validate local slash commands exist
            app.logger.info("[Setup] Validating local repositories have required slash commands...")
            let commandResults = validateLocalCommands(repositories: repositories)
            if commandResults.isEmpty {
                app.logger.info("[Setup] All repositories have required slash commands")
            } else {
                for (repo, missing) in commandResults {
                    app.logger.warning("[Setup] \(repo) missing commands: \(missing.joined(separator: ", "))")
                }
            }
        }
    }

    // Start polling job
    let pollingJob = PollingJob(app: app)
    Task {
        await pollingJob.start()
    }

    // Register routes
    try routes(app)
}

// MARK: - Local Command Validation

/// Required slash commands for Claude Ops workflow
private let requiredCommands = [
    "plan-headless.md",
    "implement-headless.md",
    "retrospective-headless.md",
    "revise-headless.md"
]

/// Validate that local repositories have the required slash commands
/// Returns a dictionary of repo name -> missing commands
private func validateLocalCommands(repositories: [Repository]) -> [String: [String]] {
    var results: [String: [String]] = [:]
    let fileManager = FileManager.default

    for repo in repositories {
        let commandsDir = repo.path + "/.claude/commands"
        var missing: [String] = []

        for command in requiredCommands {
            let commandPath = commandsDir + "/" + command
            if !fileManager.fileExists(atPath: commandPath) {
                missing.append(command)
            }
        }

        if !missing.isEmpty {
            results[repo.fullName] = missing
        }
    }

    return results
}

// MARK: - Application Storage Keys

struct PersistenceServiceKey: StorageKey {
    typealias Value = any PersistenceService
}

struct GitHubServiceKey: StorageKey {
    typealias Value = GitHubService
}

struct ClaudeServiceKey: StorageKey {
    typealias Value = ClaudeService
}

struct PushNotificationServiceKey: StorageKey {
    typealias Value = PushNotificationService
}

struct GeminiServiceKey: StorageKey {
    typealias Value = GeminiService
}

struct RepoMapKey: StorageKey {
    typealias Value = RepoMap
}

struct WorktreeServiceKey: StorageKey {
    typealias Value = WorktreeService
}

struct WebSocketManagerKey: StorageKey {
    typealias Value = WebSocketManager
}

struct PricingServiceKey: StorageKey {
    typealias Value = PricingService
}

public extension Application {
    var persistenceService: any PersistenceService {
        get { storage[PersistenceServiceKey.self]! }
        set { storage[PersistenceServiceKey.self] = newValue }
    }

    var githubService: GitHubService {
        get { storage[GitHubServiceKey.self]! }
        set { storage[GitHubServiceKey.self] = newValue }
    }

    var claudeService: ClaudeService {
        get { storage[ClaudeServiceKey.self]! }
        set { storage[ClaudeServiceKey.self] = newValue }
    }

    var pushNotificationService: PushNotificationService {
        get { storage[PushNotificationServiceKey.self]! }
        set { storage[PushNotificationServiceKey.self] = newValue }
    }

    var geminiService: GeminiService {
        get { storage[GeminiServiceKey.self]! }
        set { storage[GeminiServiceKey.self] = newValue }
    }

    var repoMap: RepoMap? {
        get { storage[RepoMapKey.self] }
        set { storage[RepoMapKey.self] = newValue }
    }

    var worktreeService: WorktreeService {
        get { storage[WorktreeServiceKey.self]! }
        set { storage[WorktreeServiceKey.self] = newValue }
    }

    var webSocketManager: WebSocketManager {
        get { storage[WebSocketManagerKey.self]! }
        set { storage[WebSocketManagerKey.self] = newValue }
    }

    var pricingService: PricingService {
        get { storage[PricingServiceKey.self]! }
        set { storage[PricingServiceKey.self] = newValue }
    }
}
