// AIEnricher_OpenAI.swift
// AuGenda
//
// OpenAI ChatGPT adapter. Uses the shared OpenAI-compatible client with
// OpenAI's own base URL + default model.

import Foundation

struct OpenAIEnricher: AITaskEnricher {

    let provider: AIProvider = .openai

    private let baseURL = URL(string: "https://api.openai.com/v1")!

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
