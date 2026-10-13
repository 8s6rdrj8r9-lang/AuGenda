// AIEnricher_Grok.swift
// AuGenda
//
// xAI Grok adapter. OpenAI-compatible schema. Hidden behind the
// "Advanced providers" disclosure in Settings.

import Foundation

struct GrokEnricher: AITaskEnricher {

    let provider: AIProvider = .grok

    private let baseURL = URL(string: "https://api.x.ai/v1")!

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
