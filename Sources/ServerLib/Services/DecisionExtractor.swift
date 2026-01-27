import Foundation

/// Extracts decisions and reasoning from Claude's assistant messages
public struct DecisionExtractor {

    /// Patterns that indicate a decision with reasoning
    private static let decisionPatterns: [(pattern: String, actionGroup: Int, reasonGroup: Int)] = [
        // === Explicit decisions ===
        // "I'll [action] because [reason]"
        (#"I'll\s+(.+?)\s+because\s+(.+?)(?:\.|$)"#, 1, 2),
        // "I'm going to [action] because [reason]"
        (#"I'm going to\s+(.+?)\s+because\s+(.+?)(?:\.|$)"#, 1, 2),
        // "I chose [action] because [reason]"
        (#"I chose\s+(.+?)\s+because\s+(.+?)(?:\.|$)"#, 1, 2),
        // "I decided to [action] because [reason]"
        (#"I decided to\s+(.+?)\s+because\s+(.+?)(?:\.|$)"#, 1, 2),
        // "I'm opting for [action] because [reason]"
        (#"I'm opting for\s+(.+?)\s+because\s+(.+?)(?:\.|$)"#, 1, 2),
        // "The best approach is [action] because [reason]"
        (#"The best approach is\s+(.+?)\s+because\s+(.+?)(?:\.|$)"#, 1, 2),
        // "[Action] is better here because [reason]"
        (#"(.+?)\s+is better (?:here\s+)?because\s+(.+?)(?:\.|$)"#, 1, 2),
        // "Let's use [action] because [reason]"
        (#"Let's use\s+(.+?)\s+because\s+(.+?)(?:\.|$)"#, 1, 2),

        // === Implicit decisions with "to" ===
        // "Uses [action] to [reason]"
        (#"Uses\s+(.+?)\s+to\s+(.+?)(?:\.|$)"#, 1, 2),
        // "Using [action] to [reason]"
        (#"Using\s+(.+?)\s+to\s+(.+?)(?:\.|$)"#, 1, 2),
        // "Added [action] to [reason]"
        (#"Added\s+(.+?)\s+to\s+(.+?)(?:\.|$)"#, 1, 2),
        // "Added [action] for [reason]"
        (#"Added\s+(.+?)\s+for\s+(.+?)(?:\.|$)"#, 1, 2),
        // "I decided to [action] to [reason]"
        (#"I decided to\s+(.+?)\s+to\s+(.+?)(?:\.|$)"#, 1, 2),

        // === Implicit decisions with "because/since/for" ===
        // "Using [action] because [reason]"
        (#"Using\s+(.+?)\s+because\s+(.+?)(?:\.|$)"#, 1, 2),
        // "Using [action] since [reason]"
        (#"Using\s+(.+?)\s+since\s+(.+?)(?:\.|$)"#, 1, 2),
        // "I'll use [action] since [reason]"
        (#"I'll use\s+(.+?)\s+since\s+(.+?)(?:\.|$)"#, 1, 2),
        // "Went with [action] since [reason]"
        (#"[Ww]ent with\s+(.+?)\s+(?:since|for|because)\s+(.+?)(?:\.|$)"#, 1, 2),
        // "[action] approach for [reason]"
        (#"(.+?)\s+approach\s+(?:for|because|since)\s+(.+?)(?:\.|$)"#, 1, 2),

        // === Technical implementation patterns ===
        // "Implemented [action] using [reason/method]"
        (#"[Ii]mplemented\s+(.+?)\s+using\s+(.+?)(?:\.|$)"#, 1, 2),
        // "Wrapped [action] with [wrapper] to [reason]"
        (#"[Ww]rapped\s+(.+?)\s+with\s+(.+?)\s+to\s+.+?(?:\.|$)"#, 1, 2),
        // "with [action] to preserve/enable/allow [reason]"
        (#"with\s+(.+?)\s+to\s+(?:preserve|enable|allow|ensure|maintain|support)\s+(.+?)(?:\.|$)"#, 1, 2),

        // === Comparison patterns ===
        // "[action] instead of [alternative] because/since/for [reason]"
        (#"(.+?)\s+instead of\s+.+?\s+(?:because|since|for)\s+(.+?)(?:\.|$)"#, 1, 2),
        // "[action] rather than [alternative] because/since/for [reason]"
        (#"(.+?)\s+rather than\s+.+?\s+(?:because|since|for)\s+(.+?)(?:\.|$)"#, 1, 2),
        // "Opted for [action] because/since/for [reason]"
        (#"[Oo]pted for\s+(.+?)\s+(?:because|since|for)\s+(.+?)(?:\.|$)"#, 1, 2),
        // "Opted for [action] to [reason]"
        (#"[Oo]pted for\s+(.+?)\s+to\s+(.+?)(?:\.|$)"#, 1, 2),

        // === Created/Built patterns ===
        // "Created [action] to [reason]"
        (#"[Cc]reated\s+(.+?)\s+to\s+(.+?)(?:\.|$)"#, 1, 2),
        // "Built [action] to [reason]"
        (#"[Bb]uilt\s+(.+?)\s+to\s+(.+?)(?:\.|$)"#, 1, 2),
        // "Set up [action] to [reason]"
        (#"[Ss]et up\s+(.+?)\s+to\s+(.+?)(?:\.|$)"#, 1, 2),
    ]

    /// Patterns for extracting alternatives (e.g., "X over Y", "X instead of Y")
    private static let alternativePatterns: [String] = [
        #"chose\s+.+?\s+over\s+(.+?)\s+(?:because|since|due)"#,
        #"instead of\s+(.+?)[,\s]+(?:I|because|since)"#,
        #"rather than\s+(.+?)[,\s]+(?:I|because|since)"#,
    ]

    /// Words that indicate hedging (not actual decisions)
    private static let hedgingPhrases = [
        "might want to consider",
        "one option could be",
        "we could potentially",
        "might be worth",
        "could consider",
        "may want to",
        "possibly",
        "perhaps",
    ]

    /// Extract decisions from log content (handles both plain text and streaming JSON)
    public static func extractDecisions(from logContent: String, jobId: String) -> [JobDecision] {
        // First, reconstruct plain text from streaming JSON format
        let text = reconstructTextFromStreamingLog(logContent)

        var decisions: [JobDecision] = []
        var seenActions: Set<String> = []

        // Split into sentences for processing
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))

        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Skip hedging statements
            let lowercased = trimmed.lowercased()
            if hedgingPhrases.contains(where: { lowercased.contains($0) }) {
                continue
            }

            // Try each decision pattern
            for (pattern, actionGroup, reasonGroup) in decisionPatterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                    continue
                }

                let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
                if let match = regex.firstMatch(in: trimmed, options: [], range: range) {
                    guard let actionRange = Range(match.range(at: actionGroup), in: trimmed),
                          let reasonRange = Range(match.range(at: reasonGroup), in: trimmed) else {
                        continue
                    }

                    let action = String(trimmed[actionRange]).trimmingCharacters(in: .whitespaces)
                    let reasoning = String(trimmed[reasonRange]).trimmingCharacters(in: .whitespaces)

                    // Skip if action is too short or too long
                    guard action.count >= 3 && action.count <= 300 else { continue }
                    guard reasoning.count >= 5 && reasoning.count <= 500 else { continue }

                    // Deduplicate by normalized action
                    let normalizedAction = normalizeAction(action)
                    if seenActions.contains(normalizedAction) {
                        continue
                    }
                    seenActions.insert(normalizedAction)

                    // Extract alternatives if mentioned
                    let alternatives = extractAlternatives(from: trimmed)

                    // Categorize the decision
                    let category = categorizeDecision(action: action, reasoning: reasoning)

                    let decision = JobDecision(
                        jobId: jobId,
                        action: cleanAction(action),
                        reasoning: cleanReasoning(reasoning),
                        alternatives: alternatives.isEmpty ? nil : alternatives,
                        category: category
                    )
                    decisions.append(decision)
                    break // Only extract one decision per sentence
                }
            }
        }

        return decisions
    }

    /// Extract alternatives mentioned in the text
    private static func extractAlternatives(from text: String) -> [String] {
        var alternatives: [String] = []

        for pattern in alternativePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match = match,
                      let altRange = Range(match.range(at: 1), in: text) else {
                    return
                }
                let alt = String(text[altRange]).trimmingCharacters(in: .whitespaces)
                if !alt.isEmpty && alt.count < 100 {
                    alternatives.append(alt)
                }
            }
        }

        return alternatives
    }

    /// Categorize a decision based on keywords
    private static func categorizeDecision(action: String, reasoning: String) -> DecisionCategory {
        let combined = (action + " " + reasoning).lowercased()

        // UI/Widget decisions (check first - most specific for Flutter/SwiftUI)
        if combined.contains("widget") || combined.contains("view") ||
           combined.contains("scaffold") || combined.contains("container") ||
           combined.contains("listview") || combined.contains("gridview") ||
           combined.contains("pageview") || combined.contains("scrollview") ||
           combined.contains("customscroll") || combined.contains("sliver") ||
           combined.contains("refreshindicator") || combined.contains("gesture") ||
           combined.contains("swip") || combined.contains("pull") ||
           combined.contains("animation") || combined.contains("transition") ||
           combined.contains("layout") || combined.contains("padding") ||
           combined.contains("margin") || combined.contains("stack") {
            return .ui
        }

        if combined.contains("architect") || combined.contains("structure") ||
           combined.contains("layer") || combined.contains("separation") ||
           combined.contains("service class") || combined.contains("component") {
            return .architecture
        }

        if combined.contains("package") || combined.contains("library") ||
           combined.contains("dependency") || combined.contains("import") ||
           combined.contains(" dio ") || combined.contains(" http ") ||
           combined.contains("provider") || combined.contains("riverpod") {
            return .library
        }

        if combined.contains("pattern") || combined.contains("singleton") ||
           combined.contains("factory") || combined.contains("repository") ||
           combined.contains("mvc") || combined.contains("mvvm") {
            return .pattern
        }

        if combined.contains("sqlite") || combined.contains("database") ||
           combined.contains("storage") || combined.contains("cache") ||
           combined.contains("preferences") || combined.contains("persist") {
            return .storage
        }

        if combined.contains("api") || combined.contains("endpoint") ||
           combined.contains("rest") || combined.contains("request") ||
           combined.contains("response") {
            return .api
        }

        if combined.contains("test") || combined.contains("mock") ||
           combined.contains("spec") || combined.contains("coverage") {
            return .testing
        }

        return .other
    }

    /// Normalize action text for deduplication
    private static func normalizeAction(_ action: String) -> String {
        action.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// Clean up action text for display
    private static func cleanAction(_ action: String) -> String {
        var cleaned = action.trimmingCharacters(in: .whitespacesAndNewlines)
        // Capitalize first letter
        if let first = cleaned.first {
            cleaned = first.uppercased() + cleaned.dropFirst()
        }
        return cleaned
    }

    /// Clean up reasoning text for display
    private static func cleanReasoning(_ reasoning: String) -> String {
        var cleaned = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        // Capitalize first letter
        if let first = cleaned.first {
            cleaned = first.uppercased() + cleaned.dropFirst()
        }
        // Remove trailing punctuation if incomplete
        if cleaned.last == "," || cleaned.last == ";" {
            cleaned = String(cleaned.dropLast())
        }
        return cleaned
    }

    /// Reconstruct plain text from streaming JSON log format
    /// Handles logs that contain streaming events like:
    /// {"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"..."}}}
    private static func reconstructTextFromStreamingLog(_ logContent: String) -> String {
        var fullText = ""

        // Process line by line
        let lines = logContent.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Try to parse as JSON
            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // Not JSON - might be plain text, include it
                if !trimmed.hasPrefix("{") {
                    fullText += trimmed + " "
                }
                continue
            }

            // Handle stream_event with text_delta
            if let eventType = json["type"] as? String, eventType == "stream_event",
               let event = json["event"] as? [String: Any],
               let delta = event["delta"] as? [String: Any],
               let deltaType = delta["type"] as? String, deltaType == "text_delta",
               let text = delta["text"] as? String {
                fullText += text
                continue
            }

            // Handle content_block_delta directly (some formats)
            if let eventType = json["type"] as? String, eventType == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               let deltaType = delta["type"] as? String, deltaType == "text_delta",
               let text = delta["text"] as? String {
                fullText += text
                continue
            }

            // Handle assistant message with content array
            if let eventType = json["type"] as? String, eventType == "assistant",
               let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for item in content {
                    if let itemType = item["type"] as? String, itemType == "text",
                       let text = item["text"] as? String {
                        fullText += text + " "
                    }
                }
                continue
            }
        }

        return fullText
    }
}
