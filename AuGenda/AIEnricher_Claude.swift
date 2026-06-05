// AIEnricher_Claude.swift
// AuGenda
//
// Anthropic Claude adapter. Speaks the Messages API (different shape
// from OpenAI's chat/completions), uses x-api-key header instead of
// Authorization: Bearer, and supports tool-use for structured output.
//
// For task enrichment we use the simpler approach: ask for JSON in the
// prompt + parse the assistant message's text content. Tool-use would
// give us stricter schema enforcement but adds API surface for a
// minimal quality win on this scale of task.
//
// API ref: https://docs.anthropic.com/en/api/messages

import Foundation

private struct ClaudeRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [ClaudeMessage]
    let temperature: Double
}

private struct ClaudeMessage: Encodable {
    let role: String       // "user" | "assistant"
    let content: String
}

private struct ClaudeResponse: Decodable {
    let content: [ClaudeContentBlock]
    let usage: ClaudeUsage?

    struct ClaudeContentBlock: Decodable {
        let type: String       // "text"
        let text: String?
    }

    struct ClaudeUsage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
    }
}

struct ClaudeEnricher: AITaskEnricher {

    let provider: AIProvider = .claude

    /// Claude API base. Models live under /v1/messages.
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Anthropic version pin — required header. Update if Anthropic
    /// publishes a new stable version we want to adopt.
    private let anthropicVersion = "2023-06-01"

    func isAvailable() async -> Bool {
        KeychainStore.hasKey(for: provider)
    }

    func enrich(context: EnrichmentContext) async throws -> TaskEnrichment {
        guard let key = try KeychainStore.get(for: provider), !key.isEmpty else {
            throw AIEnricherError.missingAPIKey
        }

        let model = provider.defaultModel

        // Claude takes the system message separately + a user message
        // with the schema-shaped request.
        let systemContent = """
        \(EnrichmentPrompt.system(for: context))

        Respond with a JSON object that validates against this schema:
        \(EnrichmentPrompt.jsonSchema(allowInterest: context.personalization?.allowInterestInference ?? false))

        Output ONLY the JSON object. No code fences. No prose.
        """
        let userContent = EnrichmentPrompt.userMessage(for: context)

        let body = ClaudeRequest(
            model: model,
            max_tokens: 1024,
            system: systemContent,
            messages: [ClaudeMessage(role: "user", content: userContent)],
            temperature: 0.3
        )

        var req = URLRequest(url: baseURL)
        req.httpMethod = "POST"
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        req.setValue(key,                 forHTTPHeaderField: "x-api-key")
        req.setValue(anthropicVersion,    forHTTPHeaderField: "anthropic-version")
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

        let decoded: ClaudeResponse
        do {
            decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        } catch {
            throw AIEnricherError.invalidResponse(detail: "outer decode failed")
        }

        // Pull the first text block's content
        guard let textBlock = decoded.content.first(where: { $0.type == "text" }),
              let text = textBlock.text else {
            throw AIEnricherError.invalidResponse(detail: "no text content")
        }

        guard let textData = text.data(using: .utf8) else {
            throw AIEnricherError.invalidResponse(detail: "content not utf8")
        }

        var enrichment: TaskEnrichment
        do {
            enrichment = try JSONDecoder().decode(TaskEnrichment.self, from: textData)
        } catch {
            // Strip fences and retry (Claude usually obeys but defensive)
            let stripped = Self.stripCodeFences(text)
            guard let strippedData = stripped.data(using: .utf8),
                  let retry = try? JSONDecoder().decode(TaskEnrichment.self, from: strippedData) else {
                throw AIEnricherError.invalidResponse(detail: "inner decode failed")
            }
            enrichment = retry
        }

        enrichment.usage = TaskEnrichment.Usage(
            provider:         provider.rawValue,
            model:            model,
            promptTokens:     decoded.usage?.input_tokens ?? 0,
            completionTokens: decoded.usage?.output_tokens ?? 0
        )
        if context.personalization?.allowInterestInference != true {
            enrichment.interest = nil
        }
        return enrichment
    }

    private static func stripCodeFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```json") { t.removeFirst("```json".count) }
        else if t.hasPrefix("```") { t.removeFirst(3) }
        if t.hasSuffix("```") { t.removeLast(3) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
