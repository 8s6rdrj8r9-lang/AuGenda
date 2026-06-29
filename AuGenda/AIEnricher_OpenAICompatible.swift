// AIEnricher_OpenAICompatible.swift
// AuGenda
//
// Shared HTTP layer for providers that speak the OpenAI Chat Completions
// schema: OpenAI itself, DeepSeek, Mistral, Perplexity, and xAI Grok all
// implement the same `POST /chat/completions` shape. Anthropic Claude
// and Google Gemini have different schemas — they get their own files.
//
// Each adapter wraps this helper with provider-specific config:
//   * baseURL          — e.g. https://api.openai.com/v1
//   * defaultModelID   — the provider's preferred default
//   * authHeader       — "Authorization: Bearer ..." for most, except
//                        Anthropic (different file) which uses x-api-key
//
// Privacy: no logging of body contents. No retries on auth failures
// (would replay the API key over the wire unnecessarily).

import Foundation
import os.log

private let logger = Logger(subsystem: "com.augenda.AuGenda", category: "OpenAICompatibleClient")

// MARK: - Wire shapes (Codable mirrors of OpenAI's chat-completions API)

private struct OAChatRequest: Encodable {
    let model: String
    let messages: [OAMessage]
    let response_format: OAResponseFormat?
    let temperature: Double
}

private struct OAMessage: Encodable {
    let role: String       // "system" | "user" | "assistant"
    let content: String
}

/// We always request JSON object mode where the provider supports it.
/// Providers that don't recognize this field generally ignore it (OpenAI
/// honors it, DeepSeek honors it, Mistral honors it, Grok honors it,
/// Perplexity ignores it — we'd still get JSON because the prompt asks
/// for it and the schema is in the system message).
private struct OAResponseFormat: Encodable {
    let type: String       // "json_object"
}

private struct OAChatResponse: Decodable {
    let choices: [OAChoice]
    let usage: OAUsage?
    struct OAChoice: Decodable {
        let message: OAResponseMessage
    }
    struct OAResponseMessage: Decodable {
        let content: String
    }
    struct OAUsage: Decodable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
    }
}

// MARK: - Client

/// Shared client for any OpenAI-compatible provider. Adapters instantiate
/// one per call with the right config.
struct OpenAICompatibleClient: Sendable {

    let baseURL: URL
    let model: String
    let providerKey: AIProvider
    /// True when this provider expects `Authorization: Bearer <key>`.
    /// Some OpenAI-compat providers may use a different header — toggle
    /// here rather than forking the implementation.
    let usesBearerAuth: Bool

    init(baseURL: URL, model: String, providerKey: AIProvider, usesBearerAuth: Bool = true) {
        self.baseURL = baseURL
        self.model = model
        self.providerKey = providerKey
        self.usesBearerAuth = usesBearerAuth
    }

    func enrich(context: EnrichmentContext) async throws -> TaskEnrichment {
        let apiKey = try KeychainStore.get(for: providerKey)
        guard let key = apiKey, !key.isEmpty else {
            throw AIEnricherError.missingAPIKey
        }

        // Build the request body. System message carries the schema +
        // ND-aware rules; user message has the actual task title + context.
        let systemContent = """
        \(EnrichmentPrompt.system(for: context))

        Respond with a JSON object that validates against this schema:
        \(EnrichmentPrompt.jsonSchema(allowInterest: context.personalization?.allowInterestInference ?? false))
        """
        let userContent = EnrichmentPrompt.userMessage(for: context)

        let body = OAChatRequest(
            model: model,
            messages: [
                OAMessage(role: "system", content: systemContent),
                OAMessage(role: "user",   content: userContent)
            ],
            response_format: OAResponseFormat(type: "json_object"),
            temperature: 0.3        // low — we want consistent metadata, not creativity
        )

        let url = baseURL.appendingPathComponent("chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if usesBearerAuth {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 30

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw AIEnricherError.networkFailure(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIEnricherError.invalidResponse(detail: "no HTTP response")
        }

        switch http.statusCode {
        case 200..<300:
            break
        case 429:
            throw AIEnricherError.rateLimited
        case 401, 403:
            throw AIEnricherError.missingAPIKey
        default:
            let bodyStr = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw AIEnricherError.invalidResponse(detail: "HTTP \(http.statusCode): \(bodyStr)")
        }

        let decoded: OAChatResponse
        do {
            decoded = try JSONDecoder().decode(OAChatResponse.self, from: data)
        } catch {
            throw AIEnricherError.invalidResponse(detail: "outer decode failed")
        }

        guard let content = decoded.choices.first?.message.content else {
            throw AIEnricherError.invalidResponse(detail: "empty content")
        }

        // The provider returns a JSON string in `content`; decode it
        // into our TaskEnrichment shape.
        guard let contentData = content.data(using: .utf8) else {
            throw AIEnricherError.invalidResponse(detail: "content not utf8")
        }

        var enrichment: TaskEnrichment
        do {
            enrichment = try JSONDecoder().decode(TaskEnrichment.self, from: contentData)
        } catch {
            // Some providers wrap JSON in ```json fences — strip and retry once.
            let stripped = Self.stripCodeFences(content)
            guard let strippedData = stripped.data(using: .utf8) else {
                throw AIEnricherError.invalidResponse(detail: "inner decode failed")
            }
            let retry: TaskEnrichment
            do {
                retry = try JSONDecoder().decode(TaskEnrichment.self, from: strippedData)
            } catch {
                logger.error("OpenAI-compatible inner decode failed after stripping fences: \(error.localizedDescription, privacy: .public)")
                throw AIEnricherError.invalidResponse(detail: "inner decode failed: \(error.localizedDescription)")
            }
            enrichment = retry
        }

        enrichment.usage = TaskEnrichment.Usage(
            provider:         providerKey.rawValue,
            model:            model,
            promptTokens:     decoded.usage?.prompt_tokens ?? 0,
            completionTokens: decoded.usage?.completion_tokens ?? 0
        )

        // Defense in depth — strip interest if the caller didn't allow it.
        // The prompt asks the model not to fill it; this catches a model
        // that ignores the prompt.
        if context.personalization?.allowInterestInference != true {
            enrichment.interest = nil
        }

        return enrichment
    }

    /// Best-effort fence stripping for providers that ignore JSON mode.
    private static func stripCodeFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```json") { t.removeFirst("```json".count) }
        else if t.hasPrefix("```") { t.removeFirst(3) }
        if t.hasSuffix("```") { t.removeLast(3) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
