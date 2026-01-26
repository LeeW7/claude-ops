import Vapor

/// Controller for Quick Session REST endpoints
struct QuickSessionController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let sessions = routes.grouped("sessions")

        sessions.post("start", use: startSession)
        sessions.get(use: listSessions)
        sessions.get(":sessionId", use: getSession)
        sessions.post(":sessionId", "message", use: sendMessage)
        sessions.delete(":sessionId", use: deleteSession)
    }

    // MARK: - POST /sessions/start

    /// Create a new quick task session
    @Sendable
    func startSession(req: Request) async throws -> Response {
        let body = try req.content.decode(StartSessionRequest.self)

        req.logger.info("[QuickSession] Starting session for repo: \(body.repo)")

        do {
            let session = try await req.application.quickSessionService.createSession(repo: body.repo)

            let response = Response(status: .created)
            try response.content.encode(session)
            return response

        } catch let error as QuickSessionError {
            throw Abort(.badRequest, reason: error.localizedDescription)
        }
    }

    // MARK: - GET /sessions

    /// List all quick task sessions
    @Sendable
    func listSessions(req: Request) async throws -> [QuickSession] {
        return try await req.application.quickSessionService.getAllSessions()
    }

    // MARK: - GET /sessions/:sessionId

    /// Get a specific session with its message history
    @Sendable
    func getSession(req: Request) async throws -> QuickSessionWithMessages {
        guard let sessionId = req.parameters.get("sessionId") else {
            throw Abort(.badRequest, reason: "Missing session ID")
        }

        guard let sessionWithMessages = try await req.application.quickSessionService.getSessionWithMessages(id: sessionId) else {
            throw Abort(.notFound, reason: "Session not found")
        }

        return sessionWithMessages
    }

    // MARK: - POST /sessions/:sessionId/message

    /// Send a message to Claude in the session context
    @Sendable
    func sendMessage(req: Request) async throws -> QuickMessage {
        guard let sessionId = req.parameters.get("sessionId") else {
            throw Abort(.badRequest, reason: "Missing session ID")
        }

        let body = try req.content.decode(SendMessageRequest.self)

        req.logger.info("[QuickSession] Message for \(sessionId): \(body.content.prefix(50))...")

        do {
            let message = try await req.application.quickSessionService.sendMessage(
                sessionId: sessionId,
                content: body.content
            )
            return message

        } catch let error as QuickSessionError {
            switch error {
            case .sessionNotFound:
                throw Abort(.notFound, reason: error.localizedDescription)
            case .sessionBusy:
                throw Abort(.conflict, reason: error.localizedDescription)
            default:
                throw Abort(.badRequest, reason: error.localizedDescription)
            }
        }
    }

    // MARK: - DELETE /sessions/:sessionId

    /// Delete a session and clean up resources
    @Sendable
    func deleteSession(req: Request) async throws -> Response {
        guard let sessionId = req.parameters.get("sessionId") else {
            throw Abort(.badRequest, reason: "Missing session ID")
        }

        req.logger.info("[QuickSession] Deleting session: \(sessionId)")

        do {
            try await req.application.quickSessionService.deleteSession(id: sessionId)
            return Response(status: .noContent)

        } catch let error as QuickSessionError {
            if case .sessionNotFound = error {
                throw Abort(.notFound, reason: error.localizedDescription)
            }
            throw Abort(.badRequest, reason: error.localizedDescription)
        }
    }
}

// MARK: - Request DTOs

struct StartSessionRequest: Content {
    let repo: String
}

struct SendMessageRequest: Content {
    let content: String
}
