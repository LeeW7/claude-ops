import Foundation
import JWTKit
import Vapor

/// Service for authenticating with Google APIs using service account credentials
public actor GoogleAuthService {
    private let serviceAccount: ServiceAccountCredentials
    private var cachedToken: String?
    private var tokenExpiry: Date?

    /// Initialize with service account JSON file path
    public init(serviceAccountPath: String) throws {
        let url = URL(fileURLWithPath: serviceAccountPath)
        let data = try Data(contentsOf: url)
        self.serviceAccount = try JSONDecoder().decode(ServiceAccountCredentials.self, from: data)
    }

    /// Get a valid access token (cached or refreshed)
    public func getAccessToken() async throws -> String {
        // Return cached token if still valid (with 5 min buffer)
        if let token = cachedToken,
           let expiry = tokenExpiry,
           expiry > Date().addingTimeInterval(300) {
            return token
        }

        // Generate new token
        let token = try await refreshAccessToken()
        return token
    }

    /// Get the project ID from service account
    public nonisolated var projectId: String {
        serviceAccount.projectId
    }

    /// Refresh the access token using JWT assertion
    private func refreshAccessToken() async throws -> String {
        let jwt = try await createJWT()

        // Exchange JWT for access token
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(jwt)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GoogleAuthError.tokenExchangeFailed(errorBody)
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        cachedToken = tokenResponse.accessToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        return tokenResponse.accessToken
    }

    /// Create a signed JWT for service account authentication
    private func createJWT() async throws -> String {
        let now = Date()
        let expiry = now.addingTimeInterval(3600) // 1 hour

        // Use cloud-platform scope which covers Firestore, FCM, and other Google Cloud APIs
        let claims = GoogleJWTClaims(
            iss: serviceAccount.clientEmail,
            scope: "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/firebase.messaging",
            aud: "https://oauth2.googleapis.com/token",
            iat: now,
            exp: expiry
        )

        // Parse the private key and create signer (jwt-kit 4.x API)
        let privateKeyPEM = serviceAccount.privateKey
        let rsaKey = try RSAKey.private(pem: privateKeyPEM)
        let signer = JWTSigner.rs256(key: rsaKey)

        // Sign the JWT
        let jwt = try signer.sign(claims)
        return jwt
    }
}

// MARK: - Supporting Types

struct ServiceAccountCredentials: Codable, Sendable {
    let type: String
    let projectId: String
    let privateKeyId: String
    let privateKey: String
    let clientEmail: String
    let clientId: String
    let authUri: String
    let tokenUri: String

    enum CodingKeys: String, CodingKey {
        case type
        case projectId = "project_id"
        case privateKeyId = "private_key_id"
        case privateKey = "private_key"
        case clientEmail = "client_email"
        case clientId = "client_id"
        case authUri = "auth_uri"
        case tokenUri = "token_uri"
    }
}

struct GoogleJWTClaims: JWTPayload {
    let iss: String
    let scope: String
    let aud: String
    let iat: Date
    let exp: Date

    func verify(using signer: JWTSigner) throws {
        // Verify expiration - for signing only, no verification needed
        // The JWT is created fresh each time with a 1-hour expiry
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

enum GoogleAuthError: Error {
    case tokenExchangeFailed(String)
    case invalidPrivateKey
}
