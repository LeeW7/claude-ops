import Vapor

/// Workflow phases for an issue
enum WorkflowPhase: String, Codable {
    case new
    case planning
    case planComplete = "plan_complete"
    case implementing
    case review
    case complete
}

/// Workflow state response for an issue
struct WorkflowState: Content {
    let currentPhase: String
    let nextAction: String?
    let nextActionLabel: String?
    let prUrl: String?
    let completedPhases: [String]
    let revisionCount: Int
    let canRevise: Bool
    let canMerge: Bool
    let issueClosed: Bool?
    let activeJobId: String?  // Active job ID for WebSocket connection

    enum CodingKeys: String, CodingKey {
        case currentPhase = "current_phase"
        case nextAction = "next_action"
        case nextActionLabel = "next_action_label"
        case prUrl = "pr_url"
        case completedPhases = "completed_phases"
        case revisionCount = "revision_count"
        case canRevise = "can_revise"
        case canMerge = "can_merge"
        case issueClosed = "issue_closed"
        case activeJobId = "active_job_id"
    }

    /// Create workflow state based on job history
    static func forIssue(
        repo: String,
        issueNum: Int,
        jobs: [Job],
        issueClosed: Bool,
        prUrl: String?
    ) -> WorkflowState {
        let repoSlug = repo.split(separator: "/").last.map(String.init) ?? repo

        // Check which jobs exist and their status
        let planJob = jobs.first { $0.id == "\(repoSlug)-\(issueNum)-plan-headless" }
        let implementJob = jobs.first { $0.id == "\(repoSlug)-\(issueNum)-implement-headless" }
        let retroJob = jobs.first { $0.id == "\(repoSlug)-\(issueNum)-retrospective-headless" }

        // Count completed revisions
        let revisionCount = jobs.filter {
            $0.id.hasPrefix("\(repoSlug)-\(issueNum)-revise-headless") &&
            $0.status == .completed
        }.count

        // Check if revise is running and get active revise job
        let activeReviseJob = jobs.first {
            $0.id.hasPrefix("\(repoSlug)-\(issueNum)-revise-headless") &&
            ($0.status == .pending || $0.status == .running)
        }
        let reviseRunning = activeReviseJob != nil

        // Build completed phases list
        var completedPhases: [String] = []
        if planJob?.status == .completed { completedPhases.append("plan") }
        if implementJob?.status == .completed { completedPhases.append("implement") }
        if retroJob?.status == .completed { completedPhases.append("retrospective") }

        // Determine current phase and next action
        if completedPhases.contains("retrospective") {
            return WorkflowState(
                currentPhase: "complete",
                nextAction: nil,
                nextActionLabel: nil,
                prUrl: prUrl,
                completedPhases: completedPhases,
                revisionCount: revisionCount,
                canRevise: false,
                canMerge: false,
                issueClosed: issueClosed,
                activeJobId: nil
            )
        } else if completedPhases.contains("implement") {
            // Check if retrospective is already running
            let retroRunning = retroJob?.status == .pending || retroJob?.status == .running
            // Determine active job ID
            let activeJobId: String? = {
                if retroRunning { return retroJob?.id }
                if reviseRunning { return activeReviseJob?.id }
                return nil
            }()
            return WorkflowState(
                currentPhase: "review",
                nextAction: retroRunning ? nil : "retrospective",
                nextActionLabel: retroRunning ? nil : "cmd:retrospective-headless",
                prUrl: prUrl,
                completedPhases: completedPhases,
                revisionCount: revisionCount,
                canRevise: !reviseRunning && !retroRunning && !issueClosed,
                canMerge: !reviseRunning && !retroRunning && !issueClosed,
                issueClosed: issueClosed,
                activeJobId: activeJobId
            )
        } else if completedPhases.contains("plan") {
            // Check if implement is already running
            let implementRunning = implementJob?.status == .pending || implementJob?.status == .running
            // Check if plan is being re-run (for plan feedback)
            let planRunning = planJob?.status == .running
            // Determine active job ID
            let activeJobId: String? = {
                if implementRunning { return implementJob?.id }
                if planRunning { return planJob?.id }
                if reviseRunning { return activeReviseJob?.id }
                return nil
            }()
            return WorkflowState(
                currentPhase: implementRunning ? "implementing" : (planRunning ? "planning" : "plan_complete"),
                nextAction: (implementRunning || planRunning) ? nil : "implement",
                nextActionLabel: (implementRunning || planRunning) ? nil : "cmd:implement-headless",
                prUrl: nil,
                completedPhases: completedPhases,
                revisionCount: revisionCount,
                canRevise: !implementRunning && !planRunning && !issueClosed,  // Allow plan feedback
                canMerge: false,
                issueClosed: issueClosed,
                activeJobId: activeJobId
            )
        } else if planJob?.status == .pending || planJob?.status == .running {
            return WorkflowState(
                currentPhase: "planning",
                nextAction: nil,
                nextActionLabel: nil,
                prUrl: nil,
                completedPhases: completedPhases,
                revisionCount: revisionCount,
                canRevise: false,
                canMerge: false,
                issueClosed: issueClosed,
                activeJobId: planJob?.id
            )
        } else {
            return WorkflowState(
                currentPhase: "new",
                nextAction: "plan",
                nextActionLabel: "cmd:plan-headless",
                prUrl: nil,
                completedPhases: completedPhases,
                revisionCount: revisionCount,
                canRevise: false,
                canMerge: false,
                issueClosed: issueClosed,
                activeJobId: nil
            )
        }
    }
}
