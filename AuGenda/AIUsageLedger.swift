// AIUsageLedger.swift
// AuGenda
//
// Local-only usage tracking for AI enrichment calls. Stores:
//   * per-provider token totals (prompt + completion)
//   * per-provider estimated cost (rough — list prices baked in)
//   * monthly aggregates (one rolling window)
//
// Powers the "Usage" section in Settings → AI Enrichment and the soft-cap
// warning banner. Persisted to a small JSON file in Application Support,
// not @AppStorage (so it doesn't sync to iCloud — usage stays per-device).
//
// Cost numbers below are list prices as of 2026-06-03. Update when
// providers publish new pricing.

import Foundation
import os.log
import Combine

private let logger = Logger(subsystem: "com.augenda.AuGenda", category: "AIUsageLedger")

// MARK: - LedgerEntry

struct AIUsageEntry: Codable, Sendable {
    var provider: String
    var model: String
    var promptTokens: Int
    var completionTokens: Int
    var estimatedCostUSD: Double
    var timestamp: Date
}

// MARK: - Ledger

@MainActor
final class AIUsageLedger: ObservableObject {

    static let shared = AIUsageLedger()

    @Published private(set) var entries: [AIUsageEntry] = []

    private init() {
        load()
    }

    // MARK: - Recording

    /// Append a new usage entry from a TaskEnrichment response.
    /// Silently no-ops if the enrichment has no `usage` payload.
    func record(_ enrichment: TaskEnrichment) {
        guard let u = enrichment.usage else { return }
        let entry = AIUsageEntry(
            provider:           u.provider,
            model:              u.model,
            promptTokens:       u.promptTokens,
            completionTokens:   u.completionTokens,
            estimatedCostUSD:   Self.estimateCost(
                                    provider: u.provider,
                                    promptTokens: u.promptTokens,
                                    completionTokens: u.completionTokens
                                ),
            timestamp:          .now
        )
        entries.append(entry)
        pruneOldEntries()
        save()
    }

    /// Bound growth: keep ~90 days (the aggregates only read the current month)
    /// plus a hard count cap against pathological burst usage. Entries are
    /// appended chronologically, so removeFirst() drops the oldest.
    private func pruneOldEntries() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .distantPast
        entries.removeAll { $0.timestamp < cutoff }
        let maxEntries = 1000
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Aggregates

    /// Sum of estimated costs in the current calendar month.
    var thisMonthCostUSD: Double {
        let cal = Calendar.current
        let monthStart = cal.dateInterval(of: .month, for: .now)?.start ?? .distantPast
        return entries
            .filter { $0.timestamp >= monthStart }
            .reduce(0) { $0 + $1.estimatedCostUSD }
    }

    /// Sum of all tokens (prompt + completion) in the current calendar month.
    var thisMonthTokens: Int {
        let cal = Calendar.current
        let monthStart = cal.dateInterval(of: .month, for: .now)?.start ?? .distantPast
        return entries
            .filter { $0.timestamp >= monthStart }
            .reduce(0) { $0 + $1.promptTokens + $1.completionTokens }
    }

    // MARK: - Cost cap
    
    var maxMonthlyCostUSD: Double {
        get { UserDefaults.standard.double(forKey: "ai.maxMonthlyCostUSD") }
        set { UserDefaults.standard.set(newValue, forKey: "ai.maxMonthlyCostUSD") }
    }
    
    func canEnrich() -> Bool {
        let cap = maxMonthlyCostUSD
        guard cap > 0 else { return true }
        return thisMonthCostUSD < cap
    }
    
    // MARK: - Cost estimation
    //
    // Rough back-of-envelope numbers (USD per 1M tokens). Update when
    // providers publish new pricing. Apple Foundation + Ollama are free.

    private struct Pricing {
        let promptPer1M: Double
        let completionPer1M: Double
    }

    private static func pricing(for provider: String) -> Pricing {
        switch provider {
        case AIProvider.appleFoundation.rawValue: return Pricing(promptPer1M: 0,    completionPer1M: 0)
        case AIProvider.ollama.rawValue:          return Pricing(promptPer1M: 0,    completionPer1M: 0)
        case AIProvider.claude.rawValue:          return Pricing(promptPer1M: 3.0,  completionPer1M: 15.0)
        case AIProvider.openai.rawValue:          return Pricing(promptPer1M: 2.5,  completionPer1M: 10.0)
        case AIProvider.gemini.rawValue:          return Pricing(promptPer1M: 0.3,  completionPer1M: 2.5)
        case AIProvider.deepseek.rawValue:        return Pricing(promptPer1M: 0.14, completionPer1M: 0.28)
        case AIProvider.mistral.rawValue:         return Pricing(promptPer1M: 2.0,  completionPer1M: 6.0)
        case AIProvider.perplexity.rawValue:      return Pricing(promptPer1M: 1.0,  completionPer1M: 5.0)
        case AIProvider.grok.rawValue:            return Pricing(promptPer1M: 3.0,  completionPer1M: 15.0)
        default:                                  return Pricing(promptPer1M: 0,    completionPer1M: 0)
        }
    }

    static func estimateCost(provider: String, promptTokens: Int, completionTokens: Int) -> Double {
        let p = pricing(for: provider)
        let prompt = Double(promptTokens)     / 1_000_000.0 * p.promptPer1M
        let comp   = Double(completionTokens) / 1_000_000.0 * p.completionPer1M
        return prompt + comp
    }

    // MARK: - Persistence

    private static var fileURL: URL? {
        let dir: URL
        do {
            dir = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            logger.error("Failed to get Application Support directory: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return dir.appendingPathComponent("ai-usage-ledger.json")
    }

    private func load() {
        guard let url = Self.fileURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.error("Failed to read usage ledger: \(error.localizedDescription, privacy: .public)")
            return
        }
        do {
            self.entries = try JSONDecoder().decode([AIUsageEntry].self, from: data)
        } catch {
            logger.error("Failed to decode usage ledger: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        guard let url = Self.fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        do {
            data = try encoder.encode(entries)
        } catch {
            logger.error("Failed to encode usage ledger: \(error.localizedDescription, privacy: .public)")
            return
        }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            logger.error("Failed to write usage ledger: \(error.localizedDescription, privacy: .public)")
        }
    }
}
