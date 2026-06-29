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
    var aboutMe: String?
    var tone: PersonalizationTone
    var recentMemory: [MemoryEntry]
    var allowInterestInference: Bool

    /// One past enrichment, sent as context so the AI builds continuity
    /// across calls. Kept terse — title + band is enough; we don't need
    /// to ship the full enrichment back through.
    struct MemoryEntry: Sendable, Codable {
        var title: String
        var band: String       // DifficultyBand rawValue
        var timestamp: Date
    }
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
        didSet { UserDefaults.standard.set(aboutMe, forKey: Self.aboutMeKey) }
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
        didSet { UserDefaults.standard.set(memoryDepth, forKey: Self.memoryDepthKey) }
    }

    // MARK: Memory (persisted to Application Support)

    @Published private(set) var memory: [PersonalizationContext.MemoryEntry] = []

    private init() {
        let defaults = UserDefaults.standard
        self.aboutMe                = defaults.string(forKey: Self.aboutMeKey) ?? ""
        self.tone                   = PersonalizationTone(rawValue: defaults.string(forKey: Self.toneKey) ?? "")
                                       ?? .calm
        self.allowInterestInference = defaults.bool(forKey: Self.allowInterestKey)
        self.memoryEnabled          = defaults.object(forKey: Self.memoryEnabledKey) as? Bool ?? true
        let storedDepth             = defaults.integer(forKey: Self.memoryDepthKey)
        self.memoryDepth            = storedDepth > 0 ? storedDepth : 5
        loadMemory()
    }

    // MARK: - Recording / clearing

    /// Append a new enrichment to the memory window. Trims to memoryDepth.
    /// No-op when memoryEnabled is false.
    func recordEnrichment(title: String, band: DifficultyBand) {
        guard memoryEnabled else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let entry = PersonalizationContext.MemoryEntry(
            title: trimmed,
            band: band.rawValue,
            timestamp: .now
        )
        memory.append(entry)
        if memory.count > memoryDepth {
            memory.removeFirst(memory.count - memoryDepth)
        }
        saveMemory()
    }

    func clearMemory() {
        memory.removeAll()
        saveMemory()
    }

    /// Erase EVERYTHING — about-me, tone, memory, toggles. Used by the
    /// "Reset personalization" button in Settings.
    func resetAll() {
        aboutMe = ""
        tone = .calm
        allowInterestInference = false
        memoryEnabled = true
        memoryDepth = 5
        clearMemory()
    }

    // MARK: - Build context for an outgoing call

    /// Snapshot the current state for inclusion in an EnrichmentContext.
    /// Returns nil if there's nothing useful to share — keeps the prompt
    /// small when the user hasn't personalized anything.
    func snapshot() -> PersonalizationContext? {
        let trimmedAbout = aboutMe.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAbout  = !trimmedAbout.isEmpty
        let hasMemory = memoryEnabled && !memory.isEmpty

        // Always include if any field is set OR interest-inference is on
        // (the AI needs to know whether interest is in-scope this call).
        guard hasAbout || hasMemory || tone != .calm || allowInterestInference else {
            return nil
        }

        return PersonalizationContext(
            aboutMe: hasAbout ? trimmedAbout : nil,
            tone: tone,
            recentMemory: hasMemory ? memory : [],
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
        guard let url = Self.memoryURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            logger.error("Failed to read personalization memory: \(error.localizedDescription, privacy: .public)")
            return
        }
        do {
            self.memory = try JSONDecoder().decode([PersonalizationContext.MemoryEntry].self, from: data)
        } catch {
            logger.error("Failed to decode personalization memory: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveMemory() {
        guard let url = Self.memoryURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        do {
            data = try encoder.encode(memory)
        } catch {
            logger.error("Failed to encode personalization memory: \(error.localizedDescription, privacy: .public)")
            return
        }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            logger.error("Failed to write personalization memory: \(error.localizedDescription, privacy: .public)")
        }
    }
}
