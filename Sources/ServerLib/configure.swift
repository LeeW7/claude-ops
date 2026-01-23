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
    app.repoMap = try? RepoMap.load(from: repoMapPath)

    // Start polling job
    let pollingJob = PollingJob(app: app)
    Task {
        await pollingJob.start()
    }

    // Register routes
    try routes(app)
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
