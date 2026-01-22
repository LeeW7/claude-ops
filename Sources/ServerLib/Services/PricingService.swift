import Vapor
import Foundation

/// Service that manages Claude model pricing
/// Loads pricing from a JSON file (auto-updated or manual) with hardcoded fallback
public actor PricingService {
    /// Cached pricing data
    private var pricingCache: [String: ModelPricing] = [:]

    /// Path to pricing JSON file
    private let pricingFilePath: String

    /// Last file modification time
    private var lastFileModTime: Date?

    /// Fallback pricing if file doesn't exist or is invalid
    /// Source: https://claude.com/pricing (Jan 2026)
    private static let fallbackPricing: [String: ModelPricing] = [
        // 4.5 generation (current)
        "opus-4-5": ModelPricing(inputPerMillion: 5.0, outputPerMillion: 25.0, cacheReadPerMillion: 0.5, cacheWritePerMillion: 6.25),
        "sonnet-4-5": ModelPricing(inputPerMillion: 3.0, outputPerMillion: 15.0, cacheReadPerMillion: 0.3, cacheWritePerMillion: 3.75),
        "haiku-4-5": ModelPricing(inputPerMillion: 1.0, outputPerMillion: 5.0, cacheReadPerMillion: 0.1, cacheWritePerMillion: 1.25),
        // 4.1 generation
        "opus-4-1": ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0, cacheReadPerMillion: 1.5, cacheWritePerMillion: 18.75),
        // 4.0 generation
        "opus-4": ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0, cacheReadPerMillion: 1.5, cacheWritePerMillion: 18.75),
        "sonnet-4": ModelPricing(inputPerMillion: 3.0, outputPerMillion: 15.0, cacheReadPerMillion: 0.3, cacheWritePerMillion: 3.75),
        // 3.5 generation
        "sonnet-3-5": ModelPricing(inputPerMillion: 3.0, outputPerMillion: 15.0, cacheReadPerMillion: 0.3, cacheWritePerMillion: 3.75),
        "haiku-3-5": ModelPricing(inputPerMillion: 0.8, outputPerMillion: 4.0, cacheReadPerMillion: 0.08, cacheWritePerMillion: 1.0),
        // 3.0 generation
        "opus-3": ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0, cacheReadPerMillion: 1.5, cacheWritePerMillion: 18.75),
        "haiku-3": ModelPricing(inputPerMillion: 0.25, outputPerMillion: 1.25, cacheReadPerMillion: 0.03, cacheWritePerMillion: 0.3),
    ]

    /// Default pricing when model not found
    private static let defaultPricing = ModelPricing(
        inputPerMillion: 3.0,
        outputPerMillion: 15.0,
        cacheReadPerMillion: 0.3,
        cacheWritePerMillion: 3.75
    )

    public init() {
        self.pricingFilePath = FileManager.default.currentDirectoryPath + "/pricing.json"
        self.pricingCache = Self.fallbackPricing
    }

    /// Initialize and load pricing from file
    public func initialize() async {
        await loadPricingFromFile()
    }

    /// Get pricing for a model
    public func getPricing(for model: String) async -> ModelPricing {
        // Check if file has been updated
        await reloadIfFileChanged()

        let normalized = model.lowercased()

        // Try exact matches first, then pattern matching
        for (pattern, pricing) in pricingCache {
            if normalized.contains(pattern) {
                return pricing
            }
        }

        return Self.defaultPricing
    }

    /// Force reload pricing from file
    public func reload() async {
        await loadPricingFromFile()
    }

    /// Check if pricing file changed and reload if so
    private func reloadIfFileChanged() async {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: pricingFilePath),
              let modTime = attrs[.modificationDate] as? Date else {
            return
        }

        if lastFileModTime == nil || modTime > lastFileModTime! {
            await loadPricingFromFile()
        }
    }

    /// Load pricing from JSON file
    private func loadPricingFromFile() async {
        guard FileManager.default.fileExists(atPath: pricingFilePath),
              let data = FileManager.default.contents(atPath: pricingFilePath) else {
            print("[PricingService] No pricing.json found, using fallback pricing")
            pricingCache = Self.fallbackPricing
            return
        }

        do {
            let decoded = try JSONDecoder().decode([String: PricingEntry].self, from: data)
            var newCache: [String: ModelPricing] = [:]

            for (key, entry) in decoded {
                newCache[key] = ModelPricing(
                    inputPerMillion: entry.input,
                    outputPerMillion: entry.output,
                    cacheReadPerMillion: entry.cacheRead,
                    cacheWritePerMillion: entry.cacheWrite
                )
            }

            pricingCache = newCache
            lastFileModTime = Date()
            print("[PricingService] Loaded pricing for \(newCache.count) models from pricing.json")
        } catch {
            print("[PricingService] Failed to parse pricing.json: \(error), using fallback")
            pricingCache = Self.fallbackPricing
        }
    }

    /// Get all cached pricing (for debugging/display)
    public func getAllPricing() -> [String: ModelPricing] {
        return pricingCache
    }

    /// Create a sample pricing.json file
    public func createSamplePricingFile() {
        let sample: [String: PricingEntry] = [
            "opus-4-5": PricingEntry(input: 5.0, output: 25.0, cacheRead: 0.5, cacheWrite: 6.25),
            "sonnet-4-5": PricingEntry(input: 3.0, output: 15.0, cacheRead: 0.3, cacheWrite: 3.75),
            "haiku-4-5": PricingEntry(input: 1.0, output: 5.0, cacheRead: 0.1, cacheWrite: 1.25),
            "opus-4-1": PricingEntry(input: 15.0, output: 75.0, cacheRead: 1.5, cacheWrite: 18.75),
            "opus-4": PricingEntry(input: 15.0, output: 75.0, cacheRead: 1.5, cacheWrite: 18.75),
            "sonnet-4": PricingEntry(input: 3.0, output: 15.0, cacheRead: 0.3, cacheWrite: 3.75),
            "sonnet-3-5": PricingEntry(input: 3.0, output: 15.0, cacheRead: 0.3, cacheWrite: 3.75),
            "haiku-3-5": PricingEntry(input: 0.8, output: 4.0, cacheRead: 0.08, cacheWrite: 1.0),
            "opus-3": PricingEntry(input: 15.0, output: 75.0, cacheRead: 1.5, cacheWrite: 18.75),
            "haiku-3": PricingEntry(input: 0.25, output: 1.25, cacheRead: 0.03, cacheWrite: 0.3),
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(sample) else { return }
        try? data.write(to: URL(fileURLWithPath: pricingFilePath))
        print("[PricingService] Created sample pricing.json")
    }
}

/// JSON structure for pricing file
private struct PricingEntry: Codable {
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite: Double
}
