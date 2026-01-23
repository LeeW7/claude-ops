import Vapor

/// Track if logging has been bootstrapped (can only happen once per process)
private var loggingBootstrapped = false

/// Public function to create and configure a Vapor application
public func createServer() async throws -> Application {
    var env = try Environment.detect()

    // LoggingSystem.bootstrap can only be called once per process
    if !loggingBootstrapped {
        try LoggingSystem.bootstrap(from: &env)
        loggingBootstrapped = true
    }

    let app = try await Application.make(env)
    try await configure(app)

    return app
}

/// Public function to run the server (blocking)
public func runServer() async throws {
    let app = try await createServer()
    defer { Task { try? await app.asyncShutdown() } }
    try await app.execute()
}

/// Public function to start server in background (non-blocking)
public func startServerInBackground() async throws -> Application {
    let app = try await createServer()

    // Start the server without blocking
    Task {
        do {
            try await app.execute()
        } catch {
            app.logger.error("Server error: \(error)")
        }
    }

    return app
}
