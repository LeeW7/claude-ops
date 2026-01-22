import Vapor

/// Cost breakdown for a single phase
struct PhaseCost: Content {
    let phase: String
    let command: String
    let cost: Double
    let input_tokens: Int
    let output_tokens: Int
    let cache_read_tokens: Int
    let cache_write_tokens: Int
    let model: String
    let run_count: Int

    init(
        phase: String,
        command: String,
        cost: Double,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheWriteTokens: Int,
        model: String,
        runCount: Int
    ) {
        self.phase = phase
        self.command = command
        self.cost = cost
        self.input_tokens = inputTokens
        self.output_tokens = outputTokens
        self.cache_read_tokens = cacheReadTokens
        self.cache_write_tokens = cacheWriteTokens
        self.model = model
        self.run_count = runCount
    }
}

/// Response for issue cost breakdown
struct IssueCostsResponse: Content {
    let repo: String
    let issue_num: Int
    let phases: [PhaseCost]
    let total_cost: Double
    let total_input_tokens: Int
    let total_output_tokens: Int
    let total_cache_read_tokens: Int
    let total_cache_write_tokens: Int

    init(
        repo: String,
        issueNum: Int,
        phases: [PhaseCost],
        totalCost: Double,
        totalInputTokens: Int,
        totalOutputTokens: Int,
        totalCacheReadTokens: Int,
        totalCacheWriteTokens: Int
    ) {
        self.repo = repo
        self.issue_num = issueNum
        self.phases = phases
        self.total_cost = totalCost
        self.total_input_tokens = totalInputTokens
        self.total_output_tokens = totalOutputTokens
        self.total_cache_read_tokens = totalCacheReadTokens
        self.total_cache_write_tokens = totalCacheWriteTokens
    }
}
