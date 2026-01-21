import Vapor

/// Request body for posting feedback on an issue
struct FeedbackRequest: Content {
    let feedback: String
    let image_url: String?
}

/// Response for feedback submission
struct FeedbackResponse: Content {
    let status: String
    let message: String
}
