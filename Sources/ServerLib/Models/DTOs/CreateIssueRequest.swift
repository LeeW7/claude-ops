import Vapor

/// Request body for creating a GitHub issue
struct CreateIssueRequest: Content {
    let repo: String
    let title: String
    let body: String?
}

/// Request body for enhancing an issue with AI
struct EnhanceIssueRequest: Content {
    let idea: String
    let title: String?
    let repo: String?
}

/// Response for enhanced issue
struct EnhanceIssueResponse: Content {
    let enhanced_title: String
    let enhanced_body: String
    let original_idea: String
}

/// Response for issue creation
struct CreateIssueResponse: Content {
    let status: String
    let issue_url: String
    let message: String
}
