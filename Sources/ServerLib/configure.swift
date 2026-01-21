import Vapor
import FirebaseCore
import FirebaseFirestore

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

    // Initialize Firebase
    let serviceAccountPath = app.directory.workingDirectory + "service-account.json"
    if FileManager.default.fileExists(atPath: serviceAccountPath) {
        if let options = FirebaseOptions(contentsOfFile: serviceAccountPath) {
            FirebaseApp.configure(options: options)
            app.logger.info("Firebase initialized successfully")
        } else {
            app.logger.warning("Could not parse service-account.json")
        }
    } else {
        app.logger.warning("service-account.json not found at \(serviceAccountPath)")
        app.logger.warning("Firestore will not be available")
    }

    // Initialize services
    app.firestoreService = FirestoreService()
    app.githubService = GitHubService()
    app.claudeService = ClaudeService(app: app)
    app.pushNotificationService = PushNotificationService()
    app.geminiService = GeminiService()

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

struct FirestoreServiceKey: StorageKey {
    typealias Value = FirestoreService
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

public extension Application {
    var firestoreService: FirestoreService {
        get { storage[FirestoreServiceKey.self]! }
        set { storage[FirestoreServiceKey.self] = newValue }
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
}
