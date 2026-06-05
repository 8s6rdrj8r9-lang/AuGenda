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

    func isAvailable() async -> Bool {
        KeychainStore.hasKey(for: provider)
    }

    func enrich(context: EnrichmentContext) async throws -> TaskEnrichment {
        let client = OpenAICompatibleClient(
            baseURL:     baseURL,
            model:       provider.defaultModel,
            providerKey: provider
        )
        return try await client.enrich(context: context)
    }
}
