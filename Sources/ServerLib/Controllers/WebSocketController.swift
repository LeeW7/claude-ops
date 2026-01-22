import Vapor

/// Controller for WebSocket endpoints
struct WebSocketController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        // WebSocket endpoint for job streaming (specific job)
        // Use non-async handler to stay on the correct event loop
        routes.webSocket("ws", "jobs", ":jobId") { req, ws in
            handleJobStream(req: req, ws: ws)
        }

        // WebSocket endpoint for global job events (all job lifecycle updates)
        // Flutter connects here on app start to receive all status changes
        routes.webSocket("ws", "events") { req, ws in
            handleGlobalEvents(req: req, ws: ws)
        }
    }

    /// Handle global WebSocket connection for all job events
    private func handleGlobalEvents(req: Request, ws: WebSocket) {
        let wsManager = req.application.webSocketManager
        let eventLoop = req.eventLoop

        // Add as global subscriber
        wsManager.addGlobalConnection(ws, eventLoop: eventLoop)

        req.logger.info("[WebSocket] Global events client connected (total: \(wsManager.globalClientCount()))")

        // Send connection confirmation
        let welcome: [String: Any] = [
            "type": "connected",
            "message": "Subscribed to global job events"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: welcome),
           let text = String(data: data, encoding: .utf8) {
            eventLoop.execute {
                ws.send(text, promise: nil)
            }
        }

        // Handle ping/pong for keepalive
        ws.onText { ws, text in
            if text.contains("ping") {
                eventLoop.execute {
                    ws.send("{\"type\":\"pong\"}", promise: nil)
                }
            }
        }

        // Handle disconnect
        ws.onClose.whenComplete { _ in
            wsManager.removeGlobalConnection(ws)
            req.logger.info("[WebSocket] Global events client disconnected (remaining: \(wsManager.globalClientCount()))")
        }
    }

    /// Handle WebSocket connection for job streaming
    /// This is called synchronously on the WebSocket's event loop
    private func handleJobStream(req: Request, ws: WebSocket) {
        guard let jobId = req.parameters.get("jobId") else {
            _ = ws.close(code: .policyViolation)
            return
        }

        let wsManager = req.application.webSocketManager
        let eventLoop = req.eventLoop

        // Add this connection (synchronous, thread-safe)
        wsManager.addConnection(ws, eventLoop: eventLoop, forJob: jobId)

        req.logger.info("[WebSocket] Client connected for job: \(jobId)")

        // Send initial connection message
        let connectMessage = StreamMessage(
            type: .connected,
            jobId: jobId,
            data: .status("Connected to job stream")
        )
        wsManager.broadcast(to: jobId, message: connectMessage)

        // Try to get current job status asynchronously
        Task {
            if let job = try? await req.application.firestoreService.getJobFuzzy(id: jobId) {
                let statusMessage = StreamMessage(
                    type: .statusChange,
                    jobId: jobId,
                    data: .status(job.status.rawValue)
                )
                wsManager.broadcast(to: jobId, message: statusMessage)
            }
        }

        // Handle incoming messages from client
        ws.onText { ws, text in
            handleClientMessage(wsManager: wsManager, ws: ws, eventLoop: eventLoop, jobId: jobId, text: text, logger: req.logger)
        }

        // Handle disconnect
        ws.onClose.whenComplete { _ in
            wsManager.removeConnection(ws, forJob: jobId)
            req.logger.info("[WebSocket] Client disconnected from job: \(jobId)")
        }
    }

    /// Handle messages from WebSocket client
    private func handleClientMessage(wsManager: WebSocketManager, ws: WebSocket, eventLoop: EventLoop, jobId: String, text: String, logger: Logger) {
        // Parse client message
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(ClientMessage.self, from: data) else {
            return
        }

        switch message.type {
        case "user_input":
            // Forward user input to Claude (Phase 2)
            if let content = message.content {
                logger.info("[WebSocket] User input for job \(jobId): \(content.prefix(50))...")
                // TODO: Forward to ClaudeService stdin
            }

        case "ping":
            // Respond with pong on the correct event loop
            eventLoop.execute {
                ws.send("{\"type\":\"pong\"}", promise: nil)
            }

        default:
            break
        }
    }
}

/// Message from WebSocket client
struct ClientMessage: Codable {
    let type: String
    let content: String?
}
