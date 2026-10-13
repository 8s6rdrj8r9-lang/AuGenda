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
    var id: UUID = UUID()
    var provider: String
    var model: String
    var promptTokens: Int
    var completionTokens: Int
    var estimatedCostUSD: Double
    var timestamp: Date

    init(
        id: UUID = UUID(),
        provider: String,
        model: String,
        promptTokens: Int,
        completionTokens: Int,
        estimatedCostUSD: Double,
        timestamp: Date
    ) {
        self.id = id
        self.provider = provider
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.estimatedCostUSD = estimatedCostUSD
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case id, provider, model, promptTokens, completionTokens, estimatedCostUSD, timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.provider = try container.decode(String.self, forKey: .provider)
        self.model = try container.decode(String.self, forKey: .model)
        self.promptTokens = try container.decode(Int.self, forKey: .promptTokens)
        self.completionTokens = try container.decode(Int.self, forKey: .completionTokens)
        self.estimatedCostUSD = try container.decode(Double.self, forKey: .estimatedCostUSD)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
    }
}

private struct AIUsageLedgerEnvelope: Codable {
    let schemaVersion: Int
    let entries: [AIUsageEntry]
}

// MARK: - Ledger

@MainActor
final class AIUsageLedger: ObservableObject {

    static let shared = AIUsageLedger()
    private static let recoveryRequiredKey = "ai.usageLedger.recoveryRequired"

    @Published private(set) var entries: [AIUsageEntry] = []
    /// False when an existing ledger could not be read or decoded. A configured
    /// spend cap fails closed until the user explicitly clears the ledger.
    @Published private(set) var persistenceIsHealthy = true

    private init() {
        load()
    }

    // MARK: - Recording

    /// Append a new usage entry from a TaskEnrichment response.
    /// A missing usage payload is a successful no-op. The in-memory ledger is
    /// published only after the replacement file is durably written.
    @discardableResult
    func record(_ enrichment: TaskEnrichment) -> Bool {
        guard let u = enrichment.usage else { return true }
        if entries.contains(where: { $0.id == u.id }) {
            return true
        }
        let entry = AIUsageEntry(
            id:                 u.id,
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
        var replacement = entries
        replacement.append(entry)
        replacement = Self.pruned(replacement)
        do {
            try replaceEntries(replacement, persist: Self.persistEntries)
            return true
        } catch {
            logger.error("Failed to persist AI usage: \(error.localizedDescription, privacy: .public)")
            Self.setRecoveryRequired(true)
            persistenceIsHealthy = false
            return false
        }
    }

    /// Bound growth by age. Never drop current-month entries merely to satisfy
    /// a count cap: doing so could understate the configured monthly spend cap.
    private static func pruned(_ entries: [AIUsageEntry]) -> [AIUsageEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .distantPast
        return entries.filter { $0.timestamp >= cutoff }
    }

    @discardableResult
    func clear() -> Bool {
        guard let directory = Self.fileURL?.deletingLastPathComponent(),
              Self.removeQuarantinedFiles(in: directory) else {
            Self.setRecoveryRequired(true)
            persistenceIsHealthy = false
            return false
        }
        do {
            try replaceEntries([], persist: Self.persistEntries, allowRecovery: true)
            return true
        } catch {
            logger.error("Failed to clear AI usage: \(error.localizedDescription, privacy: .public)")
            Self.setRecoveryRequired(true)
            persistenceIsHealthy = false
            return false
        }
    }

    /// Replaces usage restored from an encrypted whole-product backup.
    /// Validation and persistence happen before the live observable state is
    /// changed, so a failed restore leaves the prior entries intact.
    func restoreForBackup(_ restoredEntries: [AIUsageEntry]) throws {
        try restoreForBackup(restoredEntries, persist: Self.persistEntries)
    }

    /// Persistence injection used by failure-atomicity tests.
    func restoreForBackup(
        _ restoredEntries: [AIUsageEntry],
        persist: ([AIUsageEntry]) throws -> Void
    ) throws {
        try replaceEntries(restoredEntries, persist: persist)
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
            .lazy
            .filter { $0.timestamp >= monthStart }
            .reduce(into: 0) { total, entry in
                let (entryTokens, entryOverflow) = entry.promptTokens
                    .addingReportingOverflow(entry.completionTokens)
                guard !entryOverflow else {
                    total = Int.max
                    return
                }
                let (newTotal, totalOverflow) = total.addingReportingOverflow(entryTokens)
                total = totalOverflow ? Int.max : newTotal
            }
    }

    // MARK: - Cost cap
    
    var maxMonthlyCostUSD: Double {
        get { UserDefaults.standard.double(forKey: "ai.maxMonthlyCostUSD") }
        set { UserDefaults.standard.set(newValue, forKey: "ai.maxMonthlyCostUSD") }
    }
    
    func canEnrich() -> Bool {
        Self.spendAllowed(
            cap: maxMonthlyCostUSD,
            monthCost: thisMonthCostUSD,
            persistenceIsHealthy: persistenceIsHealthy
        )
    }

    /// User-facing reason for a failed spend check. An unreadable ledger is a
    /// recovery problem, not evidence that the monthly budget was reached.
    var enrichmentPauseReason: String? {
        guard !canEnrich() else { return nil }
        if maxMonthlyCostUSD > 0 && !persistenceIsHealthy {
            return "AI enrichment paused because usage history is unavailable. Clear usage history in AI settings to recover."
        }
        return "AI enrichment paused — monthly budget reached."
    }

    static func spendAllowed(
        cap: Double,
        monthCost: Double,
        persistenceIsHealthy: Bool
    ) -> Bool {
        guard cap.isFinite, cap >= 0 else { return false }
        guard cap > 0 else { return true }
        guard persistenceIsHealthy, monthCost.isFinite, monthCost >= 0 else {
            return false
        }
        return monthCost < cap
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
        guard let url = Self.fileURL else {
            Self.setRecoveryRequired(true)
            persistenceIsHealthy = false
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            let hasQuarantine = Self.hasQuarantinedFiles(
                in: url.deletingLastPathComponent()
            )
            persistenceIsHealthy = !Self.recoveryIsRequired() && !hasQuarantine
            return
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.error("Failed to read usage ledger: \(error.localizedDescription, privacy: .public)")
            Self.setRecoveryRequired(true)
            persistenceIsHealthy = false
            return
        }
        do {
            let decoded = try Self.decodePersistedEntries(data)
            self.entries = decoded.entries
            let hasQuarantine = Self.hasQuarantinedFiles(
                in: url.deletingLastPathComponent()
            )
            persistenceIsHealthy = !hasQuarantine
            Self.setRecoveryRequired(hasQuarantine)
            if decoded.needsMigration, persistenceIsHealthy {
                _ = save(allowRecovery: true)
            }
        } catch {
            logger.error("Failed to decode usage ledger: \(error.localizedDescription, privacy: .public)")
            Self.setRecoveryRequired(true)
            _ = Self.quarantineCorruptFile(at: url)
            persistenceIsHealthy = false
        }
    }

    @discardableResult
    private func save(allowRecovery: Bool = false) -> Bool {
        // Do not overwrite unreadable historical usage with a partial in-memory
        // view. Explicit Clear is the recovery action.
        guard persistenceIsHealthy || allowRecovery else { return false }
        do {
            try Self.persistEntries(entries)
            persistenceIsHealthy = true
            Self.setRecoveryRequired(false)
            return true
        } catch {
            logger.error("Failed to write usage ledger: \(error.localizedDescription, privacy: .public)")
            Self.setRecoveryRequired(true)
            persistenceIsHealthy = false
            return false
        }
    }

    private func replaceEntries(
        _ replacement: [AIUsageEntry],
        persist: ([AIUsageEntry]) throws -> Void,
        allowRecovery: Bool = false
    ) throws {
        guard persistenceIsHealthy || allowRecovery else {
            throw AIUsagePersistenceError.recoveryRequired
        }
        entries = try Self.validatedBackupReplacement(
            replacement,
            persist: persist
        )
        persistenceIsHealthy = true
        Self.setRecoveryRequired(false)
    }

    /// Value-only persistence seam. Tests can inject a failure and prove no
    /// live singleton or production file is touched.
    static func validatedBackupReplacement(
        _ replacement: [AIUsageEntry],
        persist: ([AIUsageEntry]) throws -> Void
    ) throws -> [AIUsageEntry] {
        try validatePersistedEntries(replacement)
        try persist(replacement)
        return replacement
    }

    private static func persistEntries(_ replacement: [AIUsageEntry]) throws {
        guard let url = fileURL else {
            throw AIUsagePersistenceError.storageUnavailable
        }
        let data = try encodePersistedEntries(replacement)
        try data.write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    struct DecodedEntries {
        let entries: [AIUsageEntry]
        let needsMigration: Bool
    }

    /// Version 2 uses seconds-since-1970 for lossless fractional timestamps.
    /// Version 1 used ISO-8601 strings and remains a migration input.
    static let persistenceSchemaVersion = 2

    static func recoveryIsRequired(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: recoveryRequiredKey)
    }

    static func setRecoveryRequired(
        _ required: Bool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(required, forKey: recoveryRequiredKey)
    }

    static func decodePersistedEntries(_ data: Data) throws -> DecodedEntries {
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601

        if let object = try? JSONSerialization.jsonObject(with: data),
           let dictionary = object as? [String: Any],
           dictionary["schemaVersion"] != nil {
            guard let version = dictionary["schemaVersion"] as? Int else {
                throw AIUsagePersistenceError.unsupportedVersion
            }
            let envelope: AIUsageLedgerEnvelope
            switch version {
            case persistenceSchemaVersion:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                envelope = try decoder.decode(AIUsageLedgerEnvelope.self, from: data)
            case 1:
                envelope = try isoDecoder.decode(AIUsageLedgerEnvelope.self, from: data)
            default:
                throw AIUsagePersistenceError.unsupportedVersion
            }
            try validatePersistedEntries(envelope.entries)
            return DecodedEntries(
                entries: envelope.entries,
                needsMigration: version != persistenceSchemaVersion
            )
        }

        // Migration path for the unversioned ISO-8601 array format.
        if let entries = try? isoDecoder.decode([AIUsageEntry].self, from: data) {
            try validatePersistedEntries(entries)
            return DecodedEntries(entries: entries, needsMigration: true)
        }

        // Migration path for the original unversioned array format that used
        // JSONEncoder's default numeric Date representation.
        let legacyEntries = try JSONDecoder().decode([AIUsageEntry].self, from: data)
        try validatePersistedEntries(legacyEntries)
        return DecodedEntries(entries: legacyEntries, needsMigration: true)
    }

    static func encodePersistedEntries(_ entries: [AIUsageEntry]) throws -> Data {
        try validatePersistedEntries(entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(
            AIUsageLedgerEnvelope(
                schemaVersion: persistenceSchemaVersion,
                entries: entries
            )
        )
    }

    @discardableResult
    static func quarantineCorruptFile(at url: URL) -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let baseName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension
        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        let quarantineURL = url.deletingLastPathComponent().appendingPathComponent(
            "\(baseName).corrupt-\(UUID().uuidString)\(suffix)"
        )
        do {
            try fileManager.moveItem(at: url, to: quarantineURL)
            logger.error(
                "Quarantined unreadable usage ledger as \(quarantineURL.lastPathComponent, privacy: .public)"
            )
            return quarantineURL
        } catch {
            logger.error(
                "Failed to quarantine unreadable usage ledger: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    static func removeQuarantinedFiles(in directory: URL) -> Bool {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            for url in urls where
                url.lastPathComponent.hasPrefix("ai-usage-ledger.corrupt-")
                && url.pathExtension == "json" {
                try FileManager.default.removeItem(at: url)
            }
            return true
        } catch {
            logger.error(
                "Failed to remove quarantined usage ledgers: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    static func hasQuarantinedFiles(in directory: URL) -> Bool {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).contains {
                $0.lastPathComponent.hasPrefix("ai-usage-ledger.corrupt-")
                    && $0.pathExtension == "json"
            }
        } catch {
            // A directory we cannot inspect is not safe to declare clean.
            return true
        }
    }

    private static func validatePersistedEntries(_ entries: [AIUsageEntry]) throws {
        let maximumTokenCount = 10_000_000
        for entry in entries {
            guard !entry.provider.isEmpty,
                  !entry.model.isEmpty,
                  (0...maximumTokenCount).contains(entry.promptTokens),
                  (0...maximumTokenCount).contains(entry.completionTokens),
                  entry.estimatedCostUSD.isFinite,
                  (0...1_000_000).contains(entry.estimatedCostUSD),
                  entry.timestamp.timeIntervalSinceReferenceDate.isFinite else {
                throw AIUsagePersistenceError.invalidEntry
            }
        }
    }
}

private enum AIUsagePersistenceError: Error {
    case invalidEntry
    case unsupportedVersion
    case recoveryRequired
    case storageUnavailable
}
