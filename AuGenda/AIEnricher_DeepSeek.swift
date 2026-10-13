// AIEnricher_DeepSeek.swift
// AuGenda
//
// DeepSeek adapter. OpenAI-compatible schema, different base URL.
//
// ⚠️ Privacy: DeepSeek's servers are hosted in the People's Republic of
// China. The Settings UI shows an extra PRC jurisdiction warning before
// the user can enable this provider — see AIProvider.consentDisclosure.
// AuGenda's recommendation for sensitive task data is Apple Foundation
// (on-device) or Ollama (self-hosted), not DeepSeek.
//
// Why we include it anyway: the cost is ~10× cheaper than OpenAI/Claude
// for cost-sensitive users who have accepted the jurisdiction tradeoff.

import Foundation

struct DeepSeekEnricher: AITaskEnricher {

    let provider: AIProvider = .deepseek

    private let baseURL = URL(string: "https://api.deepseek.com/v1")!

    private var modelID: String? {
        Self.configuredModel(
            from: UserDefaults.standard.string(forKey: "ai.deepseek.model")
        )
    }

    static func configuredModel(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let model = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty,
              model != "deepseek-chat",
              model != "deepseek-reasoner",
              model.count <= 200 else {
            return nil
        }
        return model
    }

    func isAvailable() async -> Bool {
        guard let model = modelID else { return false }
        return await OpenAICompatibleClient(
            baseURL: baseURL,
            model: model,
            providerKey: provider
        ).isAvailable(requiredModel: model)
    }

    func enrich(context: EnrichmentContext) async throws -> TaskEnrichment {
        guard let model = modelID else {
            throw AIEnricherError.providerModelUnavailable
        }
        let client = OpenAICompatibleClient(
            baseURL:     baseURL,
            model:       model,
            providerKey: provider
        )
        // Verify the explicit model against the live list before sending any
        // task or personalization content.
        guard await client.isAvailable(requiredModel: model) else {
            throw AIEnricherError.providerModelUnavailable
        }
        return try await client.enrich(context: context)
    }
}
