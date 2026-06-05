// AITaskEnricher.swift
// AuGenda
//
// Protocol-based adapter layer for AI task enrichment. The user opts in
// (off by default per spec), picks a provider, optionally enters an API
// key, then per-task or auto-enrich runs the active provider against the
// task's title + context.
//
// Spec: memory/task_difficulty_and_ai_enrichment.md (Part 2)
//
// Privacy model:
//   * AI is OFF by default. Nothing leaves the device until the user has
//     enabled it AND picked a provider AND tapped Enrich (or enabled
//     auto-enrich, which is also off by default).
//   * API keys live in the Keychain, never @AppStorage, never iCloud-sync.
//   * Each cloud provider's first enable shows a disclosure of what is
//     sent to whom. DeepSeek shows an extra PRC jurisdiction warning.
//   * Per-task `excludeFromAI: Bool` flag opts an individual task out.

import Foundation

// MARK: - Privacy tiers

/// How exposed the user's task data is when this provider is used.
/// Surfaced in Settings as a chip beside each provider so the user can
/// make an informed choice without reading the full privacy disclosure.
enum PrivacyTier: String, Sendable {
    case onDevice    // never leaves device (Apple Foundation Models)
    case selfHosted  // local network only (Ollama)
    case cloud       // third-party API (Claude, OpenAI, Gemini, DeepSeek, Mistral, etc.)

    var label: String {
        switch self {
        case .onDevice:   return "On device"
        case .selfHosted: return "Self-hosted"
        case .cloud:      return "Cloud"
        }
    }

    var icon: String {
        switch self {
        case .onDevice:   return "lock.shield.fill"
        case .selfHosted: return "house.fill"
        case .cloud:      return "cloud.fill"
        }
    }
}

// MARK: - AIProvider enum
//
// Single source of truth for which providers AuGenda supports. The
// settings picker walks this enum, and the AIEnrichmentManager looks up
// the right concrete adapter by case.

enum AIProvider: String, CaseIterable, Sendable, Identifiable {

    case appleFoundation = "apple-foundation"
    case claude          = "claude"
    case openai          = "openai"
    case gemini          = "gemini"
    case deepseek        = "deepseek"
    case mistral         = "mistral"
    case ollama          = "ollama"
    case perplexity      = "perplexity"
    case grok            = "grok"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleFoundation: return "Apple (on device)"
        case .claude:          return "Claude (Anthropic)"
        case .openai:          return "ChatGPT (OpenAI)"
        case .gemini:          return "Gemini (Google)"
        case .deepseek:        return "DeepSeek"
        case .mistral:         return "Mistral (EU)"
        case .ollama:          return "Ollama (self-hosted)"
        case .perplexity:      return "Perplexity"
        case .grok:            return "Grok (xAI)"
        }
    }

    var privacyTier: PrivacyTier {
        switch self {
        case .appleFoundation: return .onDevice
        case .ollama:          return .selfHosted
        default:               return .cloud
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .appleFoundation, .ollama: return false
        default:                        return true
        }
    }

    /// Default model ID per provider — used when the user hasn't picked
    /// a specific model. Models current as of 2026-06-03; revisit on
    /// provider major-version updates.
    var defaultModel: String {
        switch self {
        case .appleFoundation: return "apple-foundation-3b"
        case .claude:          return "claude-sonnet-4-5"
        case .openai:          return "gpt-4o"
        case .gemini:          return "gemini-2.5-flash"
        case .deepseek:        return "deepseek-chat"
        case .mistral:         return "mistral-large-latest"
        case .ollama:          return "llama3.1:8b"
        case .perplexity:      return "sonar-pro"
        case .grok:            return "grok-3"
        }
    }

    /// Whether this provider is part of the primary set or hidden behind
    /// the "Advanced providers" disclosure in Settings.
    var isAdvanced: Bool {
        switch self {
        case .perplexity, .grok: return true
        default:                 return false
        }
    }

    /// Shown on the provider picker beside the name. One line.
    var tagline: String {
        switch self {
        case .appleFoundation: return "Free. Zero data leaves your device."
        case .claude:          return "Best nuance + ND-aware framing."
        case .openai:          return "Fast, structured JSON output."
        case .gemini:          return "Generous free tier."
        case .deepseek:        return "Cheapest cloud. ⚠️ PRC-hosted."
        case .mistral:         return "EU-hosted. GDPR-aligned."
        case .ollama:          return "Power-user local LLM."
        case .perplexity:      return "Research-focused. Overkill here."
        case .grok:            return "General purpose."
        }
    }

    /// Disclosure text shown the first time the user enables a cloud
    /// provider. The Settings UI displays this above the confirm button.
    var consentDisclosure: String {
        switch self {
        case .appleFoundation:
            return "Apple's on-device model runs locally on your device. Your task titles, notes, and context never leave the device when this provider is selected."
        case .ollama:
            return "Ollama runs on your own server. Your task data is sent over your local network only — never to a third-party cloud."
        case .deepseek:
            return "DeepSeek's servers are hosted in the People's Republic of China and subject to PRC data laws. Task titles, notes, and neurotype context will be sent to DeepSeek's API. For sensitive tasks (medical, legal, family) consider Apple on-device or Ollama instead."
        default:
            return "Task titles, notes, and neurotype context will be sent to \(displayName)'s API for enrichment. They may be used per \(displayName)'s terms of service. No task data is sent until you enable enrichment AND select this provider."
        }
    }
}

// MARK: - Request context

/// Everything a provider needs to enrich a task. Passed to `enrich(...)`
/// so adapters stay stateless — no shared mutable state across calls.
struct EnrichmentContext: Sendable {
    /// User-typed natural-language task title.
    var rawTitle: String

    /// Optional user-typed note (free-form context).
    var userNote: String?

    /// Active profile's neurotypes (used to soften / sharpen the prompt).
    /// Strings rather than the Neurotype enum to keep this struct free of
    /// SwiftData / model dependencies.
    var neurotypes: [String]

    /// Active profile's current density mode (so suggestions can match).
    var currentDensity: String?

    /// Personalization profile (about-me, tone, recent memory). Optional —
    /// the user may not have filled it in. When nil, providers behave like
    /// they did pre-personalization (cold context per call).
    var personalization: PersonalizationContext?
}

// MARK: - Enrichment result

/// What an AI provider returns. All fields optional — the provider may
/// not have high confidence on every axis. The caller applies fields
/// individually, never replacing user-set values silently.
///
/// **Interest field:** historically AuGenda refused to let AI infer
/// interest ("private to the brain"). That stance is now user-controlled
/// via `PersonalizationStore.allowInterestInference` — when on, the
/// prompt invites the AI to estimate this field; when off, the prompt
/// explicitly forbids it. The field exists in the schema regardless so
/// the Codable shape doesn't fork; the *caller* decides whether to
/// actually apply it.
struct TaskEnrichment: Codable, Sendable {

    /// Refined / cleaned-up title (e.g. "call ins" → "Call insurance about claim").
    var title: String?

    /// Expanded multi-line description.
    var taskDescription: String?

    /// Suggested decomposition into sub-tasks. May be empty.
    var subTasks: [String]?

    // Six-axis difficulty model
    var friction: Int?         // 1–4
    var energy: Int?           // 1–4
    var sensoryLoad: Int?      // 0–3
    var socialLoad: Int?       // 0–3
    var initiationCost: Int?   // 0–3

    /// Estimated interest. Only populated when the user has opted into
    /// AI interest inference (Settings → AI Enrichment → Personalization).
    /// Apply at the call site, never silently — show as "AI guess" so
    /// the user knows to verify.
    var interest: Int?         // 1–5

    var estimatedMinutes: Int?
    var contextTag: String?    // "home", "phone", "computer", "errand", etc.
    var bestTimeOfDay: String? // "morning", "afternoon", "evening", "any"

    /// 0.0–1.0 — how sure the model is. Helpful for surfacing low-confidence
    /// enrichments differently in the UI (e.g. greyed out, "AI guess: ...").
    var confidence: Double?

    /// Provider + model + token count for the usage ledger.
    var usage: Usage?

    struct Usage: Codable, Sendable {
        var provider: String
        var model: String
        var promptTokens: Int
        var completionTokens: Int
    }
}

// MARK: - Errors

enum AIEnricherError: Error, LocalizedError {
    case providerNotConfigured
    case missingAPIKey
    case networkFailure(underlying: Error?)
    case invalidResponse(detail: String)
    case rateLimited
    case unsupportedOnThisDevice
    case cancelled

    // On-device (Apple Foundation Models) specific failures. Mapped from the
    // framework's GenerationError so the user never sees a raw NSError dump.
    case onDeviceModelUnavailable
    case onDeviceGuardrailTripped
    case onDeviceModelFailed

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured:   return "Pick a provider in Settings → AI Enrichment first."
        case .missingAPIKey:           return "This provider needs an API key. Add one in Settings."
        case .networkFailure:          return "Couldn't reach the provider. Check your connection."
        case .invalidResponse(let d):  return "Provider returned an unexpected response: \(d)"
        case .rateLimited:             return "Rate limited. Wait a moment and try again."
        case .unsupportedOnThisDevice: return "This provider isn't available on this device."
        case .cancelled:               return "Cancelled."
        case .onDeviceModelUnavailable:
            return "Apple's on-device model isn't ready here. It's often unavailable in the Simulator — try a real device with Apple Intelligence turned on, or pick a cloud provider in Settings."
        case .onDeviceGuardrailTripped:
            return "Apple's on-device safety filter blocked this task — usually a false positive on harmless wording. Try rephrasing the title slightly, or use a cloud provider for this one."
        case .onDeviceModelFailed:
            return "The on-device model couldn't finish this one. Try again, or switch to a cloud provider in Settings."
        }
    }
}

// MARK: - Protocol

/// Every AI provider conforms to this. One implementation per provider.
/// Concrete adapters live in `AIEnricher_*.swift` files.
protocol AITaskEnricher: Sendable {

    /// Stable enum case identifying this adapter — drives provider lookup.
    var provider: AIProvider { get }

    /// Whether this adapter is actually usable right now (e.g. on-device
    /// model present, API key configured, server reachable). Surfaced in
    /// the test-connection button on Settings.
    func isAvailable() async -> Bool

    /// Run the enrichment. May throw `AIEnricherError`.
    func enrich(context: EnrichmentContext) async throws -> TaskEnrichment
}

// MARK: - Prompt template (provider-agnostic)
//
// All cloud providers receive the same system + user prompt; only the
// transport differs. Apple Foundation Models takes the same string as
// `instructions:` to the LanguageModelSession.

enum EnrichmentPrompt {

    /// System / instructions prompt. Identical structure across providers
    /// so we get comparable behavior. Personalization (about-me + tone)
    /// and the interest-inference rule are conditionally appended.
    ///
    /// - Parameter context: caller passes the full EnrichmentContext so
    ///   tone + interest opt-in can be read from `context.personalization`.
    static func system(for context: EnrichmentContext) -> String {
        let personalization = context.personalization
        let allowInterest = personalization?.allowInterestInference ?? false
        let tone = personalization?.tone ?? .calm

        let interestRule = allowInterest
            ? "- Estimate interestLevel (1 = tedious, 5 = genuinely interesting) "
              + "based on the user's About-me notes and recent task history. "
              + "Mark a lower confidence if unsure — the user can override."
            : "- NEVER infer interestLevel. That field is private to the user. "
              + "Leave it null in your response."

        return """
        You are a task-enrichment assistant for AuGenda, an app used by people \
        with ADHD, autism, and AuDHD. Your job is to take a raw task title and \
        propose structured metadata that helps the app schedule and present the \
        task in a neurodivergent-friendly way.

        \(tone.promptInstruction)

        Rules:
        - Be concise. Do not catastrophize ("HUGE task!"). Do not infantilize \
        ("you've got this, buddy!"). Speak plainly.
        - Decompose only when decomposition is genuinely useful. A 30-second \
        task should not be split into 5 sub-steps.
        \(interestRule)
        - Sensory load rates the ENVIRONMENT, not the task content. A loud \
        reception desk is sensory=3 even for a 1-friction task.
        - Social load rates synchronous communication weight. Email = 1. \
        Known scheduled call = 2. Unknown caller / negotiation / confrontation = 3.
        - Initiation cost rates dread / first-step paralysis weight, independent \
        of execution complexity. A 30-second action can have initiation=3.
        - estimatedMinutes is a realistic ND-aware estimate (not optimistic).
        - confidence is your own self-assessment, 0.0 to 1.0.
        - Output must validate against the provided JSON schema. No prose \
        outside the JSON.
        """
    }

    /// Build the user message from the enrichment context. Includes
    /// the personalization profile (about-me + recent memory) when set.
    static func userMessage(for context: EnrichmentContext) -> String {
        var parts: [String] = []

        // Personalization preamble — only included when the user has set
        // it. Kept above the title so the AI reads "who" before "what."
        if let personalization = context.personalization {
            if let about = personalization.aboutMe, !about.isEmpty {
                parts.append("About the user:\n\(about)")
            }
            if !personalization.recentMemory.isEmpty {
                let lines = personalization.recentMemory
                    .suffix(5)
                    .map { "- \($0.title) (rated \($0.band))" }
                    .joined(separator: "\n")
                parts.append("Recent tasks the user enriched:\n\(lines)")
            }
        }

        parts.append("Task to enrich:")
        parts.append("Title: \(context.rawTitle)")
        if let note = context.userNote, !note.isEmpty {
            parts.append("Optional context: \(note)")
        }
        if !context.neurotypes.isEmpty {
            parts.append("User neurotypes: \(context.neurotypes.joined(separator: ", "))")
        }
        if let density = context.currentDensity {
            parts.append("User's current capacity mode: \(density)")
        }
        parts.append("\nRespond with the enrichment JSON only.")
        return parts.joined(separator: "\n\n")
    }

    /// JSON schema string — handed to providers that support structured
    /// output. The `interest` field is conditionally allowed; when
    /// inference is off we still include it as a `null`able property
    /// (the prompt is what enforces null, since not all providers
    /// honor `enum: [null]`).
    static func jsonSchema(allowInterest: Bool) -> String {
        let interestProperty = allowInterest
            ? "\"interest\":         { \"type\": [\"integer\", \"null\"], \"minimum\": 1, \"maximum\": 5 },"
            : "\"interest\":         { \"type\": \"null\" },"
        return """
        {
          "type": "object",
          "properties": {
            "title":            { "type": "string" },
            "taskDescription":  { "type": "string" },
            "subTasks":         { "type": "array", "items": { "type": "string" } },
            "friction":         { "type": "integer", "minimum": 1, "maximum": 4 },
            "energy":           { "type": "integer", "minimum": 1, "maximum": 4 },
            "sensoryLoad":      { "type": "integer", "minimum": 0, "maximum": 3 },
            "socialLoad":       { "type": "integer", "minimum": 0, "maximum": 3 },
            "initiationCost":   { "type": "integer", "minimum": 0, "maximum": 3 },
            \(interestProperty)
            "estimatedMinutes": { "type": "integer", "minimum": 1 },
            "contextTag":       { "type": "string" },
            "bestTimeOfDay":    { "type": "string", "enum": ["morning","afternoon","evening","any"] },
            "confidence":       { "type": "number", "minimum": 0, "maximum": 1 }
          }
        }
        """
    }
}

// MARK: - Provider registry
//
// Single lookup point. The settings UI + per-task Enrich button both go
// through this. New adapters register by adding a case here.

enum AIEnricherRegistry {

    /// Look up the concrete adapter for a given provider case. Returns
    /// nil if the provider isn't compiled in (shouldn't happen in
    /// production; defensive for partial-build scenarios).
    static func enricher(for provider: AIProvider) -> AITaskEnricher? {
        switch provider {
        case .appleFoundation: return AppleFoundationEnricher()
        case .claude:          return ClaudeEnricher()
        case .openai:          return OpenAIEnricher()
        case .gemini:          return GeminiEnricher()
        case .deepseek:        return DeepSeekEnricher()
        case .mistral:         return MistralEnricher()
        case .ollama:          return OllamaEnricher()
        case .perplexity:      return PerplexityEnricher()
        case .grok:            return GrokEnricher()
        }
    }
}
