import Foundation

/// Parsed summary from a Claude job log
public struct JobLogSummary: Sendable {
    public let result: String?
    public let prUrl: String?
    public let duration: TimeInterval?
    public let cost: Double?
    public let turns: Int?
    public let isComplete: Bool
    public let error: String?

    public var durationFormatted: String {
        guard let duration = duration else { return "-" }
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    public var costFormatted: String {
        guard let cost = cost else { return "-" }
        return String(format: "$%.2f", cost)
    }
}

/// Parses Claude CLI JSON log output
public struct LogParser {

    /// Parse a log file and extract summary information
    /// Reads only the last portion of the file for efficiency
    public static func parseSummary(from path: String) -> JobLogSummary {
        guard FileManager.default.fileExists(atPath: path) else {
            return JobLogSummary(
                result: nil, prUrl: nil, duration: nil, cost: nil,
                turns: nil, isComplete: false, error: nil
            )
        }

        // Read last 64KB to find the result line
        let content = FileUtilities.readFileTail(path: path, maxBytes: 64 * 1024) ?? ""

        // Look for the result line (should be near the end)
        let lines = content.components(separatedBy: .newlines).reversed()

        for line in lines {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Check for result line
            if let type = json["type"] as? String, type == "result" {
                let result = json["result"] as? String
                let durationMs = json["duration_ms"] as? Double
                let cost = json["total_cost_usd"] as? Double
                let turns = json["num_turns"] as? Int
                let isError = json["is_error"] as? Bool ?? false

                // Extract PR URL from result text
                let prUrl = extractPRUrl(from: result)

                return JobLogSummary(
                    result: result,
                    prUrl: prUrl,
                    duration: durationMs.map { $0 / 1000 },
                    cost: cost,
                    turns: turns,
                    isComplete: true,
                    error: isError ? result : nil
                )
            }
        }

        // No result found - job may be in progress or failed
        return JobLogSummary(
            result: nil, prUrl: nil, duration: nil, cost: nil,
            turns: nil, isComplete: false, error: nil
        )
    }

    /// Extract recent activity from log for in-progress jobs
    public static func parseRecentActivity(from path: String, maxItems: Int = 20) -> [String] {
        guard FileManager.default.fileExists(atPath: path) else {
            return []
        }

        let content = FileUtilities.readFileTail(path: path, maxBytes: 128 * 1024) ?? ""
        let lines = content.components(separatedBy: .newlines)

        var activities: [String] = []

        for line in lines.reversed() {
            guard activities.count < maxItems,
                  !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let activity = extractActivity(from: json) {
                activities.append(activity)
            }
        }

        return activities.reversed()
    }

    // MARK: - Private Helpers

    private static func extractPRUrl(from text: String?) -> String? {
        guard let text = text else { return nil }

        // Look for GitHub PR URLs
        let pattern = #"https://github\.com/[^/]+/[^/]+/pull/\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }

        return String(text[range])
    }

    private static func extractActivity(from json: [String: Any]) -> String? {
        guard let type = json["type"] as? String else { return nil }

        switch type {
        case "assistant":
            // Extract tool calls
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for item in content {
                    if let toolName = item["name"] as? String,
                       let input = item["input"] as? [String: Any] {
                        if let desc = input["description"] as? String {
                            return "🔧 \(toolName): \(desc)"
                        } else if let cmd = input["command"] as? String {
                            let shortCmd = cmd.prefix(60)
                            return "🔧 \(toolName): \(shortCmd)..."
                        } else if let path = input["file_path"] as? String {
                            let filename = (path as NSString).lastPathComponent
                            return "🔧 \(toolName): \(filename)"
                        }
                    }
                }
            }

        case "user":
            // Tool results
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for item in content {
                    if let toolResult = item["type"] as? String, toolResult == "tool_result" {
                        if let isError = item["is_error"] as? Bool, isError {
                            return "❌ Tool error"
                        }
                    }
                }
            }

        default:
            break
        }

        return nil
    }
}
