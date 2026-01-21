import Vapor
import Foundation

/// Service for AI-enhanced issue creation using Gemini API
public actor GeminiService {
    private let apiKey: String?

    public init() {
        self.apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
    }

    /// Check if Gemini is configured
    var isConfigured: Bool {
        apiKey != nil && !apiKey!.isEmpty
    }

    /// Enhance an issue description using Gemini
    func enhanceIssue(title: String?, description: String, repo: String?) async throws -> (title: String, body: String) {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw Abort(.internalServerError, reason: "Gemini API key not configured. Set GEMINI_API_KEY environment variable.")
        }

        let prompt = """
        You are a technical writer helping improve a GitHub issue.

        Polish and enhance the following issue while preserving the user's intent.

        Title: \(title ?? "(not provided)")
        Description: \(description)
        \(repo != nil ? "Repository: \(repo!)" : "")

        Improve by:
        1. Making title clear, specific, and action-oriented (e.g., "Add X to Y", "Fix Z in W")
        2. Making description clearer and more specific
        3. Fixing grammar and spelling
        4. Adding acceptance criteria if not present
        5. Keeping it concise - don't add fluff

        Output format (use exactly this structure):
        TITLE: [Polished title - short, action-oriented, under 60 chars]

        ## Description
        [Polished description - keep the user's intent but make it clearer]

        ## Acceptance Criteria
        - [What "done" looks like - 2-4 bullet points]

        IMPORTANT:
        - Preserve the user's original intent
        - Don't invent new features they didn't ask for
        - Keep title short and actionable
        - Output ONLY in the format above, no extra text
        """

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 1024
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Abort(.internalServerError, reason: "Invalid response from Gemini API")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw Abort(.internalServerError, reason: "Gemini API error: \(errorBody)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw Abort(.internalServerError, reason: "Failed to parse Gemini response")
        }

        // Parse the response
        return parseEnhancedResponse(text, originalTitle: title ?? description)
    }

    /// Parse the enhanced response from Gemini
    private func parseEnhancedResponse(_ text: String, originalTitle: String) -> (title: String, body: String) {
        var enhancedTitle = originalTitle
        var enhancedBody = text

        if text.hasPrefix("TITLE:") {
            let lines = text.components(separatedBy: "\n")
            if let firstLine = lines.first {
                enhancedTitle = firstLine
                    .replacingOccurrences(of: "TITLE:", with: "")
                    .trimmingCharacters(in: .whitespaces)

                if lines.count > 1 {
                    enhancedBody = lines.dropFirst()
                        .joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        return (enhancedTitle, enhancedBody)
    }
}
