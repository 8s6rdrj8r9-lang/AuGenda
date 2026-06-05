// AIEnricher_Perplexity.swift
// AuGenda
//
// Perplexity adapter. OpenAI-compatible schema. Hidden behind the
// "Advanced providers" disclosure in Settings — Perplexity is
// research/web-search focused; for plain task enrichment it's overkill,
// but included for completeness.

import Foundation

struct PerplexityEnricher: AITaskEnricher {

    let provider: AIProvider = .perplexity

    private let baseURL = URL(string: "https://api.perplexity.ai")!

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
