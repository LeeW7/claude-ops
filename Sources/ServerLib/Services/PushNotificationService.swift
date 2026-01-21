import Vapor
import Foundation
import Logging

/// Service for sending push notifications via Firebase Cloud Messaging
public actor PushNotificationService {
    private let logger = Logger(label: "push-notifications")

    public init() {}
    private var accessToken: String?
    private var tokenExpiry: Date?

    /// Send a push notification to all subscribed devices via topic
    func send(title: String, body: String) async {
        // For topic-based messaging, we use the legacy FCM HTTP API
        // which is simpler and works with service accounts

        guard let projectId = getProjectId() else {
            logger.warning("Could not determine Firebase project ID")
            return
        }

        // Get OAuth2 access token for FCM
        guard let token = await getAccessToken() else {
            logger.warning("Could not get FCM access token")
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
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                logger.error("FCM send failed with status: \(httpResponse.statusCode)")
            }
        } catch {
            logger.error("Push notification failed: \(error)")
        }
    }

    /// Get Firebase project ID from service account
    private func getProjectId() -> String? {
        let path = FileManager.default.currentDirectoryPath + "/service-account.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projectId = json["project_id"] as? String else {
            return nil
        }
        return projectId
    }

    /// Get OAuth2 access token for FCM (using service account)
    private func getAccessToken() async -> String? {
        // Check if we have a valid cached token
        if let token = accessToken, let expiry = tokenExpiry, Date() < expiry {
            return token
        }

        // Use gcloud to get an access token (requires gcloud CLI)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gcloud", "auth", "print-access-token"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let token = token, !token.isEmpty {
                self.accessToken = token
                self.tokenExpiry = Date().addingTimeInterval(3500) // Token valid for ~1 hour
                return token
            }
        } catch {
            logger.error("Failed to get access token: \(error)")
        }

        return nil
    }
}
