import Vapor

/// Request body for merging a PR
struct MergeRequest: Content {
    let method: String?  // "squash", "merge", or "rebase"

    var mergeMethod: String {
        method ?? "squash"
    }
}

/// Response for merge operation
struct MergeResponse: Content {
    let status: String
    let pr_number: Int
    let message: String
}

/// Response for PR details
struct PRDetailsResponse: Content {
    let has_pr: Bool
    let pr_number: Int?
    let pr_url: String?
    let title: String?
    let branch: String?
    let mergeable: String?
    let merge_state_status: String?
    let check_status: String?

    init(
        hasPr: Bool,
        prNumber: Int? = nil,
        prUrl: String? = nil,
        title: String? = nil,
        branch: String? = nil,
        mergeable: String? = nil,
        mergeStateStatus: String? = nil,
        checkStatus: String? = nil
    ) {
        self.has_pr = hasPr
        self.pr_number = prNumber
        self.pr_url = prUrl
        self.title = title
        self.branch = branch
        self.mergeable = mergeable
        self.merge_state_status = mergeStateStatus
        self.check_status = checkStatus
    }
}
