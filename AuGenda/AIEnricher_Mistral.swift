// AIEnricher_Mistral.swift
// AuGenda
//
// Mistral (EU) adapter. OpenAI-compatible schema, EU-hosted.
//
// AuGenda surfaces Mistral as the EU-jurisdiction option for users
// uncomfortable with US-hosted clouds. Same data-handling risks as any
// cloud provider, but operating under GDPR.

import Foundation

struct MistralEnricher: AITaskEnricher {

    let provider: AIProvider = .mistral

    private let baseURL = URL(string: "https://api.mistral.ai/v1")!

    func isAvailable() async -> Bool {
        await OpenAICompatibleClient(
            baseURL: baseURL,
            model: provider.defaultModel,
            providerKey: provider
        ).isAvailable(requiredModel: provider.defaultModel)
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
