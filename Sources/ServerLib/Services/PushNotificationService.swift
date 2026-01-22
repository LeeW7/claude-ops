import Vapor
import Foundation
import Logging

/// Service for sending push notifications via Firebase Cloud Messaging
public actor PushNotificationService {
    private let logger = Logger(label: "push-notifications")
    private let authService: GoogleAuthService?
    private let projectId: String?

    public init() {
        // Try to load service account credentials
        let serviceAccountPath = FileManager.default.currentDirectoryPath + "/service-account.json"

        do {
            let auth = try GoogleAuthService(serviceAccountPath: serviceAccountPath)
            self.authService = auth
            self.projectId = auth.projectId
            logger.info("[FCM] Initialized with project: \(auth.projectId)")
        } catch {
            logger.warning("[FCM] Service account not found, push notifications disabled: \(error)")
            self.authService = nil
            self.projectId = nil
        }
    }

    /// Send a push notification to all subscribed devices via topic
    public func send(title: String, body: String) async {
        guard let projectId = projectId else {
            // Silently skip if not configured
            return
        }

        guard let authService = authService else {
            return
        }

        // Get OAuth2 access token for FCM
        let token: String
        do {
            token = try await authService.getAccessToken()
        } catch {
            logger.warning("Could not get FCM access token: \(error)")
            return
        }

        let url = URL(string: "https://fcm.googleapis.com/v1/projects/\(projectId)/messages:send")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "message": [
                "topic": "all",
                "notification": [
                    "title": title,
                    "body": body
                ]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    logger.debug("Push notification sent: \(title)")
                } else {
                    let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                    logger.error("FCM send failed with status \(httpResponse.statusCode): \(errorBody)")
                }
            }
        } catch {
            logger.error("Push notification failed: \(error)")
        }
    }
}
