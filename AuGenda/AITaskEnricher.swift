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
import Darwin

// MARK: - Privacy tiers

/// How exposed the user's task data is when this provider is used.
/// Surfaced in Settings as a chip beside each provider so the user can
/// make an informed choice without reading the full privacy disclosure.
enum PrivacyTier: String, Sendable {
    case onDevice    // never leaves device (Apple Foundation Models)
    case selfHosted  // user-chosen host (Ollama; may be local or remote)
    case cloud       // third-party API (Claude, OpenAI, Gemini, DeepSeek, Mistral, etc.)

    var label: String {
        switch self {
        case .onDevice:   return "On device"
        case .selfHosted: return "User-hosted"
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

    /// Providers remain unavailable in production until their current API
    /// model and response contract have passed the release smoke gate.
    var isReleaseEnabled: Bool {
        switch self {
        case .deepseek:
            return false
        default:
            return true
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
        // DeepSeek scheduled its moving aliases for retirement on 2026-07-24.
        // Require an explicit model ID that is verified against /models instead
        // of silently sending task data to a stale alias.
        case .deepseek:        return ""
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
        case .deepseek:        return "Unavailable pending a live release smoke test."
        case .mistral:         return "EU-hosted. GDPR-aligned."
        case .ollama:          return "Power-user, user-hosted LLM."
        case .perplexity:      return "Research-focused. Overkill here."
        case .grok:            return "General purpose."
        }
    }

    /// Official provider terms that govern API input, retention, and training.
    /// On-device Apple and user-operated Ollama do not have a third-party API
    /// destination for which AuGenda can present a single applicable policy.
    var dataTermsURL: URL? {
        let rawValue: String?
        switch self {
        case .appleFoundation, .ollama:
            rawValue = nil
        case .claude:
            rawValue = "https://www.anthropic.com/legal/commercial-terms"
        case .openai:
            rawValue = "https://openai.com/policies/services-agreement/"
        case .gemini:
            rawValue = "https://ai.google.dev/gemini-api/terms"
        case .deepseek:
            rawValue = "https://cdn.deepseek.com/policies/en-US/deepseek-privacy-policy.html"
        case .mistral:
            rawValue = "https://legal.mistral.ai/terms"
        case .perplexity:
            rawValue = "https://www.perplexity.ai/hub/legal/perplexity-api-terms-of-service"
        case .grok:
            rawValue = "https://x.ai/legal/terms-of-service-enterprise"
        }
        return rawValue.flatMap(URL.init(string:))
    }

    private var enrichmentPayloadDisclosure: String {
        "Payload: task title; optional free-form note; active profile neurotype "
            + "labels; current capacity mode; a response-tone instruction; "
            + "whether interest inference is enabled; any configured About-you "
            + "text; and, when history sharing is enabled, the configured number "
            + "of recent enriched task titles and difficulty bands."
    }

    /// Disclosure text shown the first time the user enables a cloud
    /// provider. The Settings UI displays this above the confirm button.
    var consentDisclosure: String {
        switch self {
        case .appleFoundation:
            return "\(enrichmentPayloadDisclosure) Apple's model processes this locally, so these fields do not leave the device. AuGenda keeps only the task fields you apply, local usage totals, and optional local personalization memory."
        case .ollama:
            return "\(enrichmentPayloadDisclosure) Destination: the Ollama server address you configure; a remote HTTPS address leaves your network. Retention and training: AuGenda keeps only applied task fields, local usage totals, and optional local memory; the server operator controls server-side logs, retention, and model training. AuGenda blocks unencrypted HTTP to remote hosts."
        case .deepseek:
            return "\(enrichmentPayloadDisclosure) Destination: DeepSeek's cloud API, which is subject to PRC law. Retention and training: AuGenda keeps only applied task fields, local usage totals, and optional local memory; DeepSeek may retain or use API data under its current terms. Review the linked provider terms before continuing. AuGenda requires an explicit model ID and verifies it before sending task content."
        default:
            return "\(enrichmentPayloadDisclosure) Destination: \(displayName)'s cloud API. Retention and training: AuGenda keeps only applied task fields, local usage totals, and optional local memory; the provider may retain or use API data under its current terms. Review the linked provider terms before continuing. No task data is sent until you accept this disclosure and enrich a task."
        }
    }
}

// MARK: - Versioned provider consent

/// Consent is keyed by provider and disclosure version. Increment the version
/// whenever the payload, destination, or retention disclosure materially
/// changes; stale selections then fail closed at the outbound boundary.
enum AIConsentPolicy {
    static let currentDisclosureVersion = 3
    static let ollamaDestinationKey = "ai.consent.ollama.destination"

    static func consentKey(for provider: AIProvider) -> String {
        "ai.consent.\(provider.rawValue).version"
    }

    static func hasCurrentConsent(
        for provider: AIProvider,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard provider != .appleFoundation else { return true }
        guard defaults.integer(forKey: consentKey(for: provider))
                == currentDisclosureVersion else {
            return false
        }
        guard provider == .ollama else { return true }
        let rawHost = defaults.string(forKey: "ai.ollama.host")
            ?? "http://localhost:11434"
        guard let destination = OllamaEndpointPolicy.destinationIdentifier(rawHost) else {
            return false
        }
        return defaults.string(forKey: ollamaDestinationKey) == destination
    }

    static func recordConsent(
        for provider: AIProvider,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(currentDisclosureVersion, forKey: consentKey(for: provider))
        if provider == .ollama {
            let rawHost = defaults.string(forKey: "ai.ollama.host")
                ?? "http://localhost:11434"
            if let destination = OllamaEndpointPolicy.destinationIdentifier(rawHost) {
                defaults.set(destination, forKey: ollamaDestinationKey)
            } else {
                defaults.removeObject(forKey: ollamaDestinationKey)
            }
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
        var id: UUID = UUID()
        var provider: String
        var model: String
        var promptTokens: Int
        var completionTokens: Int

        init(
            id: UUID = UUID(),
            provider: String,
            model: String,
            promptTokens: Int,
            completionTokens: Int
        ) {
            self.id = id
            self.provider = provider
            self.model = model
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
        }

        private enum CodingKeys: String, CodingKey {
            case id, provider, model, promptTokens, completionTokens
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            self.provider = try container.decode(String.self, forKey: .provider)
            self.model = try container.decode(String.self, forKey: .model)
            self.promptTokens = try container.decode(Int.self, forKey: .promptTokens)
            self.completionTokens = try container.decode(Int.self, forKey: .completionTokens)
        }
    }
}

/// Strictly decodes provider-authored JSON. Swift's synthesized Decodable
/// ignores unknown keys, which could silently accept provider schema drift.
enum EnrichmentPayloadDecoder {
    private static let allowedKeys: Set<String> = [
        "title",
        "taskDescription",
        "subTasks",
        "friction",
        "energy",
        "sensoryLoad",
        "socialLoad",
        "initiationCost",
        "interest",
        "estimatedMinutes",
        "contextTag",
        "bestTimeOfDay",
        "confidence"
    ]

    static func decode(_ data: Data) throws -> TaskEnrichment {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AIEnricherError.invalidResponse(detail: "enrichment is not valid JSON")
        }
        guard let dictionary = object as? [String: Any] else {
            throw AIEnricherError.invalidResponse(detail: "enrichment must be a JSON object")
        }
        let unknownKeys = Set(dictionary.keys).subtracting(allowedKeys)
        guard unknownKeys.isEmpty else {
            throw AIEnricherError.invalidResponse(
                detail: "unknown field(s): \(unknownKeys.sorted().joined(separator: ", "))"
            )
        }
        do {
            return try JSONDecoder().decode(TaskEnrichment.self, from: data)
        } catch {
            throw AIEnricherError.invalidResponse(
                detail: "enrichment fields do not match the schema"
            )
        }
    }
}

// MARK: - Provider output validation

/// Validates untrusted model output before any caller can assign it to a task.
/// Provider-side JSON schemas are advisory; this is the authoritative boundary.
enum EnrichmentResultValidator {

    static func validate(
        _ candidate: TaskEnrichment,
        provider: AIProvider,
        allowInterest: Bool
    ) throws -> TaskEnrichment {
        var result = candidate

        result.title = try normalizedNonemptyTextIfPresent(
            result.title,
            field: "title",
            maxLength: 240
        )
        result.taskDescription = try normalizedText(
            result.taskDescription,
            field: "taskDescription",
            maxLength: 8_000
        )
        if let contextTag = try normalizedText(
            result.contextTag,
            field: "contextTag",
            maxLength: 20
        )?.lowercased() {
            guard Self.allowedContextTags.contains(contextTag) else {
                throw AIEnricherError.invalidResponse(detail: "contextTag is unsupported")
            }
            result.contextTag = contextTag
        } else {
            result.contextTag = nil
        }

        if let subTasks = result.subTasks {
            guard subTasks.count <= 20 else {
                throw AIEnricherError.invalidResponse(detail: "too many subTasks")
            }
            result.subTasks = try subTasks.map {
                try normalizedNonemptyTextIfPresent(
                    $0,
                    field: "subTask",
                    maxLength: 500
                )!
            }
        }

        try require(result.friction, in: TaskFieldDomain.friction, field: "friction")
        try require(result.energy, in: TaskFieldDomain.energy, field: "energy")
        try require(result.sensoryLoad, in: TaskFieldDomain.load, field: "sensoryLoad")
        try require(result.socialLoad, in: TaskFieldDomain.load, field: "socialLoad")
        try require(result.initiationCost, in: TaskFieldDomain.load, field: "initiationCost")
        try require(result.estimatedMinutes, in: 1...10_080, field: "estimatedMinutes")

        if allowInterest {
            try require(result.interest, in: TaskFieldDomain.interest, field: "interest")
        } else {
            // Defense in depth for providers that ignore the prompt/schema.
            result.interest = nil
        }

        if let confidence = result.confidence {
            guard confidence.isFinite, (0...1).contains(confidence) else {
                throw AIEnricherError.invalidResponse(detail: "confidence is outside 0...1")
            }
        }

        if let rawTime = result.bestTimeOfDay {
            let time = rawTime.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard ["morning", "afternoon", "evening", "any"].contains(time) else {
                throw AIEnricherError.invalidResponse(detail: "bestTimeOfDay is unsupported")
            }
            result.bestTimeOfDay = time
        }

        guard let usage = result.usage else {
            throw AIEnricherError.invalidResponse(detail: "missing usage metadata")
        }
        let maximumTokenCount = 10_000_000
        guard usage.provider == provider.rawValue,
              !usage.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (0...maximumTokenCount).contains(usage.promptTokens),
              (0...maximumTokenCount).contains(usage.completionTokens) else {
            throw AIEnricherError.invalidResponse(detail: "invalid usage metadata")
        }

        let hasUsefulContent =
            result.title != nil
            || result.taskDescription != nil
            || !(result.subTasks ?? []).isEmpty
            || result.friction != nil
            || result.energy != nil
            || result.sensoryLoad != nil
            || result.socialLoad != nil
            || result.initiationCost != nil
            || result.interest != nil
            || result.estimatedMinutes != nil
            || result.contextTag != nil
            || result.bestTimeOfDay != nil
            || result.confidence != nil
        guard hasUsefulContent else {
            throw AIEnricherError.invalidResponse(detail: "empty enrichment")
        }

        return result
    }

    static let allowedContextTags: Set<String> = [
        "home", "computer", "phone", "outside", "focus", "errand"
    ]

    private static func normalizedNonemptyTextIfPresent(
        _ value: String?,
        field: String,
        maxLength: Int
    ) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIEnricherError.invalidResponse(detail: "\(field) is empty")
        }
        guard trimmed.count <= maxLength else {
            throw AIEnricherError.invalidResponse(detail: "\(field) is too long")
        }
        return trimmed
    }

    private static func normalizedText(
        _ value: String?,
        field: String,
        maxLength: Int
    ) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= maxLength else {
            throw AIEnricherError.invalidResponse(detail: "\(field) is too long")
        }
        return trimmed
    }

    private static func require(
        _ value: Int?,
        in allowed: ClosedRange<Int>,
        field: String
    ) throws {
        guard let value else { return }
        guard allowed.contains(value) else {
            throw AIEnricherError.invalidResponse(detail: "\(field) is outside \(allowed)")
        }
    }
}

// MARK: - Errors

enum AIEnricherError: Error, LocalizedError {
    case providerNotConfigured
    case providerModelUnavailable
    case missingAPIKey
    case providerConsentRequired
    case localOnlyPolicyViolation
    case insecureEndpoint
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
        case .providerModelUnavailable:return "Configure and verify a currently supported model for this provider."
        case .missingAPIKey:           return "This provider needs an API key. Add one in Settings."
        case .providerConsentRequired: return "Review and accept this provider's current data disclosure in Settings before enriching."
        case .localOnlyPolicyViolation:return "Local AI only is on, so this provider or host is blocked."
        case .insecureEndpoint:        return "Remote Ollama servers must use HTTPS so task data is encrypted in transit."
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

// MARK: - Outbound privacy policy

enum OllamaEndpointClassification: Equatable {
    case loopback
    case privateNetwork
    case remote
    case invalid
}

enum OllamaEndpointPolicy {

    static func validatedURL(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              let url = components.url else {
            throw AIEnricherError.invalidResponse(detail: "invalid Ollama server URL")
        }
        return url
    }

    static func destinationIdentifier(_ rawValue: String) -> String? {
        (try? validatedURL(rawValue))?.absoluteString
    }

    static func classify(_ rawValue: String) -> OllamaEndpointClassification {
        guard let url = try? validatedURL(rawValue),
              var host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host?
                .lowercased() else {
            return .invalid
        }

        if host.hasPrefix("[") && host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }

        if host == "localhost" || host.hasSuffix(".localhost") || host == "::1" {
            return .loopback
        }
        if host.hasSuffix(".local") {
            return .privateNetwork
        }

        if let octets = ipv4Octets(host) {
            if octets[0] == 127 { return .loopback }
            if octets[0] == 10
                || (octets[0] == 192 && octets[1] == 168)
                || (octets[0] == 172 && (16...31).contains(octets[1]))
                || (octets[0] == 169 && octets[1] == 254) {
                return .privateNetwork
            }
            return .remote
        }

        if host.contains(":") {
            guard let bytes = ipv6Bytes(host) else { return .invalid }
            if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes.last == 1 {
                return .loopback
            }
            // IPv4-mapped IPv6 (::ffff:a.b.c.d) inherits the embedded IPv4
            // classification instead of being treated as an arbitrary remote.
            if bytes.prefix(10).allSatisfy({ $0 == 0 }),
               bytes[10] == 0xff,
               bytes[11] == 0xff {
                return classifyIPv4(Array(bytes[12...15]))
            }
            // IPv6 unique-local (fc00::/7) and link-local (fe80::/10).
            if bytes[0] & 0xfe == 0xfc
                || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80) {
                return .privateNetwork
            }
            return .remote
        }

        return .remote
    }

    static func warning(for rawValue: String) -> String? {
        guard let url = try? validatedURL(rawValue) else {
            return "Enter a full http or https URL without embedded credentials."
        }
        let classification = classify(rawValue)
        if classification == .invalid {
            return "Enter a valid Ollama host name or IP address."
        }
        if url.scheme?.lowercased() == "http", classification == .remote {
            return "Remote Ollama hosts must use HTTPS; AuGenda will block this address."
        }
        if classification == .remote {
            return "This is a remote host. Task and enabled personalization data will leave your local network."
        }
        return nil
    }

    static func isLocal(_ classification: OllamaEndpointClassification) -> Bool {
        classification == .loopback || classification == .privateNetwork
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        guard parts.allSatisfy({ part in
            !part.isEmpty
                && part.count <= 3
                && (part.count == 1 || part.first != "0")
                && part.utf8.allSatisfy { (48...57).contains($0) }
        }) else {
            return nil
        }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return nil
        }
        return octets
    }

    private static func ipv6Bytes(_ host: String) -> [UInt8]? {
        let unscopedHost = host.split(separator: "%", maxSplits: 1)
            .first
            .map(String.init) ?? host
        var address = in6_addr()
        let parsed = unscopedHost.withCString {
            inet_pton(AF_INET6, $0, &address)
        }
        guard parsed == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    private static func classifyIPv4(_ octets: [UInt8]) -> OllamaEndpointClassification {
        guard octets.count == 4 else { return .invalid }
        if octets[0] == 127 { return .loopback }
        if octets[0] == 10
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 172 && (16...31).contains(Int(octets[1])))
            || (octets[0] == 169 && octets[1] == 254) {
            return .privateNetwork
        }
        return .remote
    }
}

enum AIOutboundPolicy {

    static func enforce(
        provider: AIProvider,
        defaults: UserDefaults = .standard
    ) throws {
        guard defaults.bool(forKey: "ai.enabled") else {
            throw AIEnricherError.providerNotConfigured
        }

        if provider == .ollama {
            let rawHost = defaults.string(forKey: "ai.ollama.host")
                ?? "http://localhost:11434"
            let url = try OllamaEndpointPolicy.validatedURL(rawHost)
            let classification = OllamaEndpointPolicy.classify(rawHost)

            guard classification != .invalid else {
                throw AIEnricherError.invalidResponse(detail: "invalid Ollama server host")
            }
            if url.scheme?.lowercased() == "http", classification == .remote {
                throw AIEnricherError.insecureEndpoint
            }
            if defaults.bool(forKey: "ai.localOnlyMode"),
               !OllamaEndpointPolicy.isLocal(classification) {
                throw AIEnricherError.localOnlyPolicyViolation
            }
            guard AIConsentPolicy.hasCurrentConsent(for: provider, defaults: defaults) else {
                throw AIEnricherError.providerConsentRequired
            }
            return
        }

        if defaults.bool(forKey: "ai.localOnlyMode"),
           provider.privacyTier == .cloud {
            throw AIEnricherError.localOnlyPolicyViolation
        }
        guard AIConsentPolicy.hasCurrentConsent(for: provider, defaults: defaults) else {
            throw AIEnricherError.providerConsentRequired
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
            ? "- Estimate interest (1 = tedious, 5 = genuinely interesting) "
              + "based on the user's About-me notes and recent task history. "
              + "Mark a lower confidence if unsure — the user can override."
            : "- NEVER infer interest. That field is private to the user. "
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
            "title":            { "type": ["string", "null"], "minLength": 1, "maxLength": 240 },
            "taskDescription":  { "type": ["string", "null"], "maxLength": 8000 },
            "subTasks":         { "type": ["array", "null"], "maxItems": 20, "items": { "type": "string", "minLength": 1, "maxLength": 500 } },
            "friction":         { "type": ["integer", "null"], "minimum": 1, "maximum": 4 },
            "energy":           { "type": ["integer", "null"], "minimum": 1, "maximum": 4 },
            "sensoryLoad":      { "type": ["integer", "null"], "minimum": 0, "maximum": 3 },
            "socialLoad":       { "type": ["integer", "null"], "minimum": 0, "maximum": 3 },
            "initiationCost":   { "type": ["integer", "null"], "minimum": 0, "maximum": 3 },
            \(interestProperty)
            "estimatedMinutes": { "type": ["integer", "null"], "minimum": 1, "maximum": 10080 },
            "contextTag":       { "type": ["string", "null"], "enum": ["home","computer","phone","outside","focus","errand",null] },
            "bestTimeOfDay":    { "type": ["string", "null"], "enum": ["morning","afternoon","evening","any",null] },
            "confidence":       { "type": ["number", "null"], "minimum": 0, "maximum": 1 }
          },
          "additionalProperties": false
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
        guard provider.isReleaseEnabled else { return nil }
        let base: any AITaskEnricher
        switch provider {
        case .appleFoundation: base = AppleFoundationEnricher()
        case .claude:          base = ClaudeEnricher()
        case .openai:          base = OpenAIEnricher()
        case .gemini:          base = GeminiEnricher()
        case .deepseek:        base = DeepSeekEnricher()
        case .mistral:         base = MistralEnricher()
        case .ollama:          base = OllamaEnricher()
        case .perplexity:      base = PerplexityEnricher()
        case .grok:            base = GrokEnricher()
        }
        return ProtectedAIEnricher(base: base)
    }
}

/// The single application-facing provider boundary. It enforces privacy
/// policy before a network-capable adapter runs, then validates untrusted
/// output before the task editor can observe it.
struct ProtectedAIEnricher: AITaskEnricher {
    let base: any AITaskEnricher

    var provider: AIProvider { base.provider }

    func isAvailable() async -> Bool {
        do {
            try AIOutboundPolicy.enforce(provider: provider)
        } catch {
            return false
        }
        return await base.isAvailable()
    }

    func enrich(context: EnrichmentContext) async throws -> TaskEnrichment {
        try AIOutboundPolicy.enforce(provider: provider)
        do {
            let candidate = try await base.enrich(context: context)
            return try EnrichmentResultValidator.validate(
                candidate,
                provider: provider,
                allowInterest: context.personalization?.allowInterestInference == true
            )
        } catch let primaryError as AIEnricherError {
            if provider == .appleFoundation, shouldAttemptBackupFallback(for: primaryError) {
                if let fallback = makeBackupEnricher() {
                    do {
                        return try await fallback.enrich(context: context)
                    } catch {
                        // Fallback also failed; bubble up primary error or fallback details
                        throw primaryError
                    }
                }
            }
            throw primaryError
        } catch {
            if provider == .appleFoundation,
               UserDefaults.standard.bool(forKey: "ai.enableBackupFallback"),
               !UserDefaults.standard.bool(forKey: "ai.localOnlyMode") {
                if let fallback = makeBackupEnricher() {
                    return try await fallback.enrich(context: context)
                }
            }
            throw error
        }
    }

    private func shouldAttemptBackupFallback(for error: AIEnricherError) -> Bool {
        let defaults = UserDefaults.standard
        let isEnabled = defaults.object(forKey: "ai.enableBackupFallback") == nil ? true : defaults.bool(forKey: "ai.enableBackupFallback")
        guard isEnabled, !defaults.bool(forKey: "ai.localOnlyMode") else { return false }
        switch error {
        case .onDeviceGuardrailTripped, .onDeviceModelUnavailable, .onDeviceModelFailed, .unsupportedOnThisDevice:
            return true
        default:
            return false
        }
    }

    private func makeBackupEnricher() -> (any AITaskEnricher)? {
        let backupRaw = UserDefaults.standard.string(forKey: "ai.backupProvider") ?? AIProvider.openai.rawValue
        guard let backupProvider = AIProvider(rawValue: backupRaw), backupProvider != .appleFoundation else {
            return nil
        }
        return AIEnricherRegistry.enricher(for: backupProvider)
    }
}

