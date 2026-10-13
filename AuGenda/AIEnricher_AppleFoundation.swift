// AIEnricher_AppleFoundation.swift
// AuGenda
//
// On-device task enricher using Apple's FoundationModels framework
// (iOS 26 / macOS 26+). No API key, no network, no cost — best privacy
// story for AuGenda's sensitive task data.
//
// Architecture notes:
//   * The actual `FoundationModels` import is gated by availability —
//     the framework ships with iOS 26 but not all simulators have a
//     model downloaded. We probe with `SystemLanguageModel.default
//     .availability` before each call.
//   * Structured output uses the framework's `@Generable` macro on a
//     mirror struct (`AppleEnrichmentSchema`), then we project that
//     onto our shared `TaskEnrichment` shape. We can't put @Generable
//     on TaskEnrichment directly because @Generable wants concrete
//     types and our TaskEnrichment is shared with Codable cloud
//     responses.
//   * Token accounting on-device is reported as 0 (no cost ever).

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct AppleFoundationEnricher: AITaskEnricher {

    let provider: AIProvider = .appleFoundation

    func isAvailable() async -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default:         return false
            }
        }
        return false
        #else
        return false
        #endif
    }

    func enrich(context: EnrichmentContext) async throws -> TaskEnrichment {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw AIEnricherError.unsupportedOnThisDevice
        }

        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            throw AIEnricherError.unsupportedOnThisDevice
        case .unavailable(.appleIntelligenceNotEnabled):
            throw AIEnricherError.unsupportedOnThisDevice
        case .unavailable(.modelNotReady):
            throw AIEnricherError.unsupportedOnThisDevice
        @unknown default:
            throw AIEnricherError.unsupportedOnThisDevice
        }

        let session = LanguageModelSession(
            instructions: { Instructions(EnrichmentPrompt.system(for: context)) }
        )

        let userPrompt = EnrichmentPrompt.userMessage(for: context)
        let allowInterest = context.personalization?.allowInterestInference ?? false

        do {
            let response = try await session.respond(
                to: userPrompt,
                generating: AppleEnrichmentSchema.self
            )
            return response.content.toTaskEnrichment(
                provider: provider.rawValue,
                model: provider.defaultModel,
                allowInterest: allowInterest
            )
        } catch {
            // Map the framework's GenerationError to a short, calm message.
            // Never surface the raw NSError — its nested UserInfo dump is
            // exactly the kind of wall-of-text this app is built to avoid.
            throw Self.mapGenerationError(error)
        }

        #else
        // Framework not compiled in — older OS, library deps disabled,
        // or building for an unsupported platform.
        throw AIEnricherError.unsupportedOnThisDevice
        #endif
    }

    /// Translate a FoundationModels generation failure into a friendly
    /// `AIEnricherError`. We match on the error's text rather than the
    /// framework's `GenerationError` enum cases: the nested-error markers
    /// (`ModelManager`, `SensitiveContentAnalysisML`) are stable across SDK
    /// betas, whereas the public case names have moved between seeds.
    ///
    /// Order matters — a Simulator asset failure surfaces *through* the
    /// guardrail subsystem (the safety classifier's own model asset is the
    /// thing that's missing), so check the model-availability markers first
    /// and only treat a clean safety hit as a guardrail trip.
    private static func mapGenerationError(_ error: Error) -> AIEnricherError {
        if let alreadyMapped = error as? AIEnricherError { return alreadyMapped }

        let text = String(describing: error).lowercased()

        if text.contains("modelmanager")
            || text.contains("1026")
            || text.contains("assetsunavailable")
            || text.contains("modelnotready")
            || text.contains("unavailable") {
            return .onDeviceModelUnavailable
        }
        if text.contains("sensitivecontentanalysis")
            || text.contains("guardrail")
            || text.contains("safety") {
            return .onDeviceGuardrailTripped
        }
        if text.contains("exceededcontextwindow") || text.contains("contextwindow") {
            return .invalidResponse(
                detail: "this task plus your About-you note was too long for the on-device model. Shorten it, or use a cloud provider."
            )
        }
        if text.contains("ratelimit") {
            return .rateLimited
        }
        return .onDeviceModelFailed
    }
}

// MARK: - On-device schema mirror
//
// FoundationModels needs concrete Generable types. We mirror our
// TaskEnrichment shape here (without `interest` — same private-to-user
// constraint) and project onto TaskEnrichment after the call.

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct AppleEnrichmentSchema {
    @Guide(description: "Cleaned-up task title")
    var title: String

    @Guide(description: "Optional one-paragraph expanded description")
    var taskDescription: String?

    @Guide(description: "Suggested sub-tasks if decomposition is genuinely helpful")
    var subTasks: [String]?

    @Guide(description: "Execution effort, 1 (easy) to 4 (high)")
    var friction: Int

    @Guide(description: "Energy cost, 1 (low) to 4 (high)")
    var energy: Int

    @Guide(description: "Environmental sensory load 0–3 (noise, light, crowd)")
    var sensoryLoad: Int

    @Guide(description: "Synchronous communication weight 0–3")
    var socialLoad: Int

    @Guide(description: "First-step / dread weight 0–3, independent of execution effort")
    var initiationCost: Int

    @Guide(description: "Interest level 1–5. Only fill this in if the system instructions explicitly authorize interest inference; otherwise leave nil.")
    var interest: Int?

    @Guide(description: "Realistic ND-aware time estimate in minutes")
    var estimatedMinutes: Int

    @Guide(description: "Context tag, exactly one of: home, computer, phone, outside, focus, errand")
    var contextTag: String?

    @Guide(description: "Best time of day: morning, afternoon, evening, any")
    var bestTimeOfDay: String?

    @Guide(description: "Your self-assessed confidence 0.0–1.0")
    var confidence: Double

    /// Project onto the shared TaskEnrichment type. Interest is only
    /// carried through when the caller authorized inference — otherwise
    /// we drop whatever the model produced (defense in depth alongside
    /// the prompt rule).
    func toTaskEnrichment(provider: String, model: String, allowInterest: Bool) -> TaskEnrichment {
        TaskEnrichment(
            title:             title,
            taskDescription:   taskDescription,
            subTasks:          subTasks,
            friction:          friction,
            energy:            energy,
            sensoryLoad:       sensoryLoad,
            socialLoad:        socialLoad,
            initiationCost:    initiationCost,
            interest:          allowInterest ? interest : nil,
            estimatedMinutes:  estimatedMinutes,
            contextTag:        contextTag,
            bestTimeOfDay:     bestTimeOfDay,
            confidence:        confidence,
            usage: TaskEnrichment.Usage(
                provider: provider,
                model: model,
                promptTokens: 0,        // on-device — no billable tokens
                completionTokens: 0
            )
        )
    }
}
#endif
