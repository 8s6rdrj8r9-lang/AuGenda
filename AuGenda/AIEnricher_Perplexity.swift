// AIEnricher_Perplexity.swift
// AuGenda
//
// Perplexity adapter. OpenAI-compatible schema. Hidden behind the
// "Advanced providers" disclosure in Settings — Perplexity is
// research/web-search focused; for plain task enrichment it's overkill,
// but included for completeness.

import Foundation

private struct PerplexityHealthRequest: Encodable {
    let model: String
    let messages = [Message(role: "user", content: "Test")]
    let max_tokens = 1

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

struct PerplexityEnricher: AITaskEnricher {

    let provider: AIProvider = .perplexity

    private let baseURL = URL(string: "https://api.perplexity.ai")!

    func isAvailable() async -> Bool {
        let storedKey: String?
        do {
            storedKey = try KeychainStore.get(for: provider)
        } catch {
            return false
        }
        guard let key = storedKey, !key.isEmpty else { return false }

        // Perplexity does not document a zero-cost credential-introspection
        // endpoint. Test the same model and Chat Completions route used by
        // enrichment with a one-token synthetic request and no user data.
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            PerplexityHealthRequest(model: provider.defaultModel)
        )
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
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
