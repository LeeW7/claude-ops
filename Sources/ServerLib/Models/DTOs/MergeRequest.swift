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
    let checks: [[String: Any]]?

    // Custom encoding for `checks` which contains heterogeneous data
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
        self.checks = nil
    }

    enum CodingKeys: String, CodingKey {
        case has_pr, pr_number, pr_url, title, branch, mergeable
        case merge_state_status, check_status, checks
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(has_pr, forKey: .has_pr)
        try container.encodeIfPresent(pr_number, forKey: .pr_number)
        try container.encodeIfPresent(pr_url, forKey: .pr_url)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(branch, forKey: .branch)
        try container.encodeIfPresent(mergeable, forKey: .mergeable)
        try container.encodeIfPresent(merge_state_status, forKey: .merge_state_status)
        try container.encodeIfPresent(check_status, forKey: .check_status)
        // Skip checks for now - will be encoded manually if needed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        has_pr = try container.decode(Bool.self, forKey: .has_pr)
        pr_number = try container.decodeIfPresent(Int.self, forKey: .pr_number)
        pr_url = try container.decodeIfPresent(String.self, forKey: .pr_url)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        mergeable = try container.decodeIfPresent(String.self, forKey: .mergeable)
        merge_state_status = try container.decodeIfPresent(String.self, forKey: .merge_state_status)
        check_status = try container.decodeIfPresent(String.self, forKey: .check_status)
        checks = nil
    }
}
