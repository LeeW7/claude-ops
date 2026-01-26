import Vapor

/// Request body for closing an issue
struct CloseIssueRequest: Content {
    let reason: String?  // "completed" or "not_planned"

    var closeReason: String {
        reason ?? "completed"
    }
}

/// Response for close issue operation
struct CloseIssueResponse: Content {
    let status: String
    let message: String
}
