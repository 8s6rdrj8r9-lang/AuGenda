// AIPersonalization.swift
// AuGenda
//
// Per-device personalization profile injected into every AI enrichment
// call's system prompt. The substance of what "signing in" feels like,
// without depending on OAuth that most providers don't expose.
//
// What gets sent on every enrichment call (when the user has filled it in):
//   * About-me text — free-form ND notes, work context, sensory prefs
//   * Tone preference — calm / direct / playful / clinical
//   * Recent enrichment memory — last N task titles + their bands, so the
//     AI builds context across calls (no real session/conversation, but
//     enough to feel coherent)
//   * Neurotypes — already sent today via EnrichmentContext
//
// All storage is per-device (@AppStorage + Application Support JSON).
// Nothing syncs via iCloud — same privacy stance as API keys.

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.augenda.AuGenda", category: "AIPersonalization")

// MARK: - Tone

enum PersonalizationTone: String, CaseIterable, Identifiable, Sendable, Codable {
    case calm
    case direct
    case playful
    case clinical

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calm:     return "Calm"
        case .direct:   return "Direct"
        case .playful:  return "Playful"
        case .clinical: return "Clinical"
        }
    }

    var description: String {
        switch self {
        case .calm:     return "Warm, soft. No urgency."
        case .direct:   return "Plain, no fluff. Straight to it."
        case .playful:  return "Light, friendly. A bit of humor."
        case .clinical: return "Neutral, factual. Like a medical chart."
        }
    }

    /// Instruction appended to the system prompt to shape the AI's voice.
    var promptInstruction: String {
        switch self {
        case .calm:
            return "Use a calm, warm voice. Soft phrasing. No urgency, no exclamation points."
        case .direct:
            return "Be direct and concise. No softening, no caveats. Plain language only."
        case .playful:
            return "Be friendly and light. A small bit of warmth is welcome, but never patronizing."
        case .clinical:
            return "Use neutral, factual language. Like a medical or scientific notation. No editorializing."
        }
    }
}

// MARK: - PersonalizationContext (passed into EnrichmentContext)

/// Snapshot the PersonalizationStore at call time — adapters take a
/// value type so they don't accidentally hold a reference to the store.
struct PersonalizationContext: Sendable, Codable {
    var profileID: UUID?
    var aboutMe: String?
    var tone: PersonalizationTone
    var recentMemory: [MemoryEntry]
    var allowInterestInference: Bool

    init(
        profileID: UUID? = nil,
        aboutMe: String? = nil,
        tone: PersonalizationTone = .calm,
        recentMemory: [MemoryEntry] = [],
        allowInterestInference: Bool = false
    ) {
        self.profileID = profileID
        self.aboutMe = aboutMe
        self.tone = tone
        self.recentMemory = recentMemory
        self.allowInterestInference = allowInterestInference
    }

    /// One past enrichment, sent as context so the AI builds continuity
    /// across calls. Kept terse — title + band is enough; we don't need
    /// to ship the full enrichment back through.
    struct MemoryEntry: Sendable, Codable {
        var profileID: UUID?
        var title: String
        var band: String       // DifficultyBand rawValue
        var timestamp: Date

        init(profileID: UUID? = nil, title: String, band: String, timestamp: Date) {
            self.profileID = profileID
            self.title = title
            self.band = band
            self.timestamp = timestamp
        }
    }
}

private struct PersonalizationMemoryEnvelope: Codable {
    let schemaVersion: Int
    let entries: [PersonalizationContext.MemoryEntry]
}

// MARK: - Store

@MainActor
final class PersonalizationStore: ObservableObject {

    static let shared = PersonalizationStore()

    // MARK: AppStorage-backed prefs

    private static let aboutMeKey       = "ai.personalization.aboutMe"
    private static let toneKey          = "ai.personalization.tone"
    private static let allowInterestKey = "ai.personalization.allowInterestInference"
    private static let memoryEnabledKey = "ai.personalization.memoryEnabled"
    private static let memoryDepthKey   = "ai.personalization.memoryDepth"

    @Published var aboutMe: String {
        didSet {
            let normalized = Self.normalizedAboutMe(aboutMe)
            if normalized != aboutMe {
                aboutMe = normalized
            }
            UserDefaults.standard.set(aboutMe, forKey: Self.aboutMeKey)
        }
    }
    @Published var tone: PersonalizationTone {
        didSet { UserDefaults.standard.set(tone.rawValue, forKey: Self.toneKey) }
    }
    @Published var allowInterestInference: Bool {
        didSet { UserDefaults.standard.set(allowInterestInference, forKey: Self.allowInterestKey) }
    }
    @Published var memoryEnabled: Bool {
        didSet { UserDefaults.standard.set(memoryEnabled, forKey: Self.memoryEnabledKey) }
    }
    @Published var memoryDepth: Int {
        didSet {
            let normalized = Self.normalizedMemoryDepth(memoryDepth)
            if normalized != memoryDepth {
                memoryDepth = normalized
            }
            UserDefaults.standard.set(memoryDepth, forKey: Self.memoryDepthKey)
            if memory.count > memoryDepth {
                let replacement = Array(memory.suffix(memoryDepth))
                do {
                    try replaceMemory(replacement, persist: Self.persistMemory)
                } catch {
                    logger.error(
                        "Failed to apply personalization memory depth: \(error.localizedDescription, privacy: .public)"
                    )
                    persistenceIsHealthy = false
                }
            }
        }
    }

    // MARK: Memory (persisted to Application Support)

    @Published private(set) var memory: [PersonalizationContext.MemoryEntry] = []
    @Published private(set) var persistenceIsHealthy = true

    private init() {
        let defaults = UserDefaults.standard
        self.aboutMe                = Self.normalizedAboutMe(
            defaults.string(forKey: Self.aboutMeKey) ?? ""
        )
        self.tone                   = PersonalizationTone(rawValue: defaults.string(forKey: Self.toneKey) ?? "")
                                       ?? .calm
        self.allowInterestInference = defaults.bool(forKey: Self.allowInterestKey)
        self.memoryEnabled          = defaults.object(forKey: Self.memoryEnabledKey) as? Bool ?? true
        let storedDepth             = defaults.integer(forKey: Self.memoryDepthKey)
        self.memoryDepth            = Self.normalizedMemoryDepth(storedDepth > 0 ? storedDepth : 5)
        loadMemory()
    }

    // MARK: - Recording / clearing

    /// Append a new enrichment to the memory window. Trims to memoryDepth.
    /// No-op when memoryEnabled is false.
    @discardableResult
    func recordEnrichment(
        title: String,
        band: DifficultyBand,
        profileID: UUID? = nil
    ) -> Bool {
        let targetID = profileID ?? ActiveProfileManager.shared.activeProfile?.clientID
        guard memoryEnabled else { return true }
        guard persistenceIsHealthy else { return false }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let boundedTitle = String(trimmed.prefix(500))

        let entry = PersonalizationContext.MemoryEntry(
            profileID: targetID,
            title: boundedTitle,
            band: band.rawValue,
            timestamp: .now
        )
        var replacement = memory
        replacement.append(entry)
        if replacement.count > memoryDepth {
            replacement.removeFirst(replacement.count - memoryDepth)
        }
        do {
            try replaceMemory(replacement, persist: Self.persistMemory)
            return true
        } catch {
            logger.error(
                "Failed to persist personalization memory: \(error.localizedDescription, privacy: .public)"
            )
            persistenceIsHealthy = false
            return false
        }
    }

    @discardableResult
    func clearMemory() -> Bool {
        guard let directory = Self.memoryURL?.deletingLastPathComponent(),
              Self.removeQuarantinedMemoryFiles(in: directory) else {
            persistenceIsHealthy = false
            return false
        }
        do {
            try replaceMemory([], persist: Self.persistMemory, allowRecovery: true)
            return true
        } catch {
            logger.error(
                "Failed to clear personalization memory: \(error.localizedDescription, privacy: .public)"
            )
            persistenceIsHealthy = false
            return false
        }
    }

    /// Erase EVERYTHING — about-me, tone, memory, toggles. Used by the
    /// "Reset personalization" button in Settings.
    @discardableResult
    func resetAll() -> Bool {
        // Persist the fallible file-backed component first. Preference writes
        // and live state are changed only after that succeeds.
        guard clearMemory() else { return false }
        aboutMe = ""
        tone = .calm
        allowInterestInference = false
        memoryEnabled = true
        memoryDepth = 5
        return true
    }

    /// Replaces memory restored from an encrypted whole-product backup.
    /// The observable array remains unchanged if validation or persistence
    /// fails.
    func restoreMemoryForBackup(
        _ restoredEntries: [PersonalizationContext.MemoryEntry]
    ) throws {
        try restoreMemoryForBackup(restoredEntries, persist: Self.persistMemory)
    }

    /// Persistence injection used by failure-atomicity tests.
    func restoreMemoryForBackup(
        _ restoredEntries: [PersonalizationContext.MemoryEntry],
        persist: ([PersonalizationContext.MemoryEntry]) throws -> Void
    ) throws {
        try replaceMemory(restoredEntries, persist: persist)
    }

    /// UserDefaults restore changes storage behind this long-lived singleton.
    /// Refresh every published preference so the current process and UI match
    /// the newly restored backup immediately.
    func reloadFromDefaultsForBackup(defaults: UserDefaults = .standard) {
        aboutMe = Self.normalizedAboutMe(
            defaults.string(forKey: Self.aboutMeKey) ?? ""
        )
        tone = PersonalizationTone(
            rawValue: defaults.string(forKey: Self.toneKey) ?? ""
        ) ?? .calm
        allowInterestInference = defaults.bool(forKey: Self.allowInterestKey)
        memoryEnabled = defaults.object(forKey: Self.memoryEnabledKey) as? Bool ?? true
        let storedDepth = defaults.integer(forKey: Self.memoryDepthKey)
        memoryDepth = Self.normalizedMemoryDepth(storedDepth > 0 ? storedDepth : 5)
    }

    // MARK: - Build context for an outgoing call

    /// Snapshot the current state for inclusion in an EnrichmentContext.
    /// Returns nil if there's nothing useful to share — keeps the prompt
    /// small when the user hasn't personalized anything.
    func snapshot(profileID: UUID? = nil) -> PersonalizationContext? {
        let targetID = profileID ?? ActiveProfileManager.shared.activeProfile?.clientID
        let trimmedAbout = aboutMe.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAbout  = !trimmedAbout.isEmpty
        let scopedMemory = memory.filter { entry in
            guard let targetID else { return true }
            return entry.profileID == nil || entry.profileID == targetID
        }
        let hasMemory = memoryEnabled && !scopedMemory.isEmpty

        // Always include if any field is set OR interest-inference is on
        // (the AI needs to know whether interest is in-scope this call).
        guard hasAbout || hasMemory || tone != .calm || allowInterestInference else {
            return nil
        }

        return PersonalizationContext(
            profileID: targetID,
            aboutMe: hasAbout ? trimmedAbout : nil,
            tone: tone,
            recentMemory: hasMemory ? Array(scopedMemory.suffix(memoryDepth)) : [],
            allowInterestInference: allowInterestInference
        )
    }

    // MARK: - Persistence (memory only — about-me + tone live in UserDefaults)

    private static var memoryURL: URL? {
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
        return dir.appendingPathComponent("ai-personalization-memory.json")
    }

    private func loadMemory() {
        guard let url = Self.memoryURL else {
            persistenceIsHealthy = false
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            persistenceIsHealthy = !Self.hasQuarantinedMemoryFiles(
                in: url.deletingLastPathComponent()
            )
            return
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.error("Failed to read personalization memory: \(error.localizedDescription, privacy: .public)")
            persistenceIsHealthy = false
            return
        }
        do {
            let decoded = try Self.decodePersistedMemory(data)
            self.memory = Array(decoded.entries.suffix(memoryDepth))
            persistenceIsHealthy = !Self.hasQuarantinedMemoryFiles(
                in: url.deletingLastPathComponent()
            )
            if persistenceIsHealthy,
               decoded.needsMigration || decoded.entries.count != memory.count {
                saveMemory()
            }
        } catch {
            logger.error("Failed to decode personalization memory: \(error.localizedDescription, privacy: .public)")
            _ = Self.quarantineCorruptMemoryFile(at: url)
            persistenceIsHealthy = false
        }
    }

    @discardableResult
    private func saveMemory(allowRecovery: Bool = false) -> Bool {
        guard persistenceIsHealthy || allowRecovery else { return false }
        do {
            try Self.persistMemory(memory)
            persistenceIsHealthy = true
            return true
        } catch {
            logger.error("Failed to write personalization memory: \(error.localizedDescription, privacy: .public)")
            persistenceIsHealthy = false
            return false
        }
    }

    private func replaceMemory(
        _ replacement: [PersonalizationContext.MemoryEntry],
        persist: ([PersonalizationContext.MemoryEntry]) throws -> Void,
        allowRecovery: Bool = false
    ) throws {
        guard persistenceIsHealthy || allowRecovery else {
            throw PersonalizationPersistenceError.recoveryRequired
        }
        memory = try Self.validatedBackupMemoryReplacement(
            replacement,
            persist: persist
        )
        persistenceIsHealthy = true
    }

    /// Value-only persistence seam. Tests can inject failures without touching
    /// the process singleton, UserDefaults, or the production Application
    /// Support file.
    static func validatedBackupMemoryReplacement(
        _ replacement: [PersonalizationContext.MemoryEntry],
        persist: ([PersonalizationContext.MemoryEntry]) throws -> Void
    ) throws -> [PersonalizationContext.MemoryEntry] {
        try validatePersistedMemory(replacement)
        try persist(replacement)
        return replacement
    }

    private static func persistMemory(
        _ replacement: [PersonalizationContext.MemoryEntry]
    ) throws {
        guard let url = memoryURL else {
            throw PersonalizationPersistenceError.storageUnavailable
        }
        let data = try encodePersistedMemory(replacement)
        try data.write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    struct DecodedMemory {
        let entries: [PersonalizationContext.MemoryEntry]
        let needsMigration: Bool
    }

    /// Version 2 uses seconds-since-1970 for lossless fractional timestamps.
    /// Version 1 used ISO-8601 strings and remains a migration input.
    static let persistenceSchemaVersion = 2

    static func decodePersistedMemory(_ data: Data) throws -> DecodedMemory {
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601

        if let object = try? JSONSerialization.jsonObject(with: data),
           let dictionary = object as? [String: Any],
           dictionary["schemaVersion"] != nil {
            guard let version = dictionary["schemaVersion"] as? Int else {
                throw PersonalizationPersistenceError.unsupportedVersion
            }
            let envelope: PersonalizationMemoryEnvelope
            switch version {
            case persistenceSchemaVersion:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                envelope = try decoder.decode(PersonalizationMemoryEnvelope.self, from: data)
            case 1:
                envelope = try isoDecoder.decode(PersonalizationMemoryEnvelope.self, from: data)
            default:
                throw PersonalizationPersistenceError.unsupportedVersion
            }
            try validatePersistedMemory(envelope.entries)
            return DecodedMemory(
                entries: envelope.entries,
                needsMigration: version != persistenceSchemaVersion
            )
        }

        // Migration path for the unversioned ISO-8601 array format.
        if let entries = try? isoDecoder.decode(
            [PersonalizationContext.MemoryEntry].self,
            from: data
        ) {
            try validatePersistedMemory(entries)
            return DecodedMemory(entries: entries, needsMigration: true)
        }

        // Migration path for the original numeric-Date array format.
        let legacyEntries = try JSONDecoder().decode(
            [PersonalizationContext.MemoryEntry].self,
            from: data
        )
        try validatePersistedMemory(legacyEntries)
        return DecodedMemory(entries: legacyEntries, needsMigration: true)
    }

    static func encodePersistedMemory(
        _ entries: [PersonalizationContext.MemoryEntry]
    ) throws -> Data {
        try validatePersistedMemory(entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(
            PersonalizationMemoryEnvelope(
                schemaVersion: persistenceSchemaVersion,
                entries: entries
            )
        )
    }

    @discardableResult
    static func quarantineCorruptMemoryFile(at url: URL) -> URL? {
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
                "Quarantined unreadable personalization memory as \(quarantineURL.lastPathComponent, privacy: .public)"
            )
            return quarantineURL
        } catch {
            logger.error(
                "Failed to quarantine unreadable personalization memory: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    static func removeQuarantinedMemoryFiles(in directory: URL) -> Bool {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            for url in urls where
                url.lastPathComponent.hasPrefix("ai-personalization-memory.corrupt-")
                && url.pathExtension == "json" {
                try FileManager.default.removeItem(at: url)
            }
            return true
        } catch {
            logger.error(
                "Failed to remove quarantined personalization memory: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    static func hasQuarantinedMemoryFiles(in directory: URL) -> Bool {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).contains {
                $0.lastPathComponent.hasPrefix("ai-personalization-memory.corrupt-")
                    && $0.pathExtension == "json"
            }
        } catch {
            return true
        }
    }

    static func normalizedMemoryDepth(_ value: Int) -> Int {
        min(max(value, 1), 20)
    }

    static func normalizedAboutMe(_ value: String) -> String {
        String(value.prefix(4_000))
    }

    private static func validatePersistedMemory(
        _ entries: [PersonalizationContext.MemoryEntry]
    ) throws {
        for entry in entries {
            guard !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.title.count <= 500,
                  DifficultyBand(rawValue: entry.band) != nil,
                  entry.timestamp.timeIntervalSinceReferenceDate.isFinite else {
                throw PersonalizationPersistenceError.invalidEntry
            }
        }
    }
}

private enum PersonalizationPersistenceError: Error {
    case invalidEntry
    case unsupportedVersion
    case recoveryRequired
    case storageUnavailable
}
