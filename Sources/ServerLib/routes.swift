import Vapor

func routes(_ app: Application) throws {
    // Health check
    app.get { req in
        return "claude-ops server running"
    }

    // Register controllers
    try app.register(collection: WebhookController())
    try app.register(collection: JobController())
    try app.register(collection: IssueController())
    try app.register(collection: RepoController())
    try app.register(collection: ImageController())
    try app.register(collection: WebSocketController())
    try app.register(collection: QuickSessionController())
}
