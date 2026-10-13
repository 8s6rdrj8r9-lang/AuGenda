// AIEnricher_Ollama.swift
// AuGenda
//
// Ollama (self-hosted local LLM) adapter. Power-user option for users
// running their own Ollama server (typically a Mac at home reachable
// from iPhone over the LAN, or localhost on a Mac).
//
// API:
//   * POST /api/chat
//   * No authentication
//   * Host:port configurable (default localhost:11434)
//
// Privacy tier: .selfHosted — data goes to the user-configured host. That
// host may be local or remote; the outbound policy classifies and constrains it.
//
// Model: defaults to llama3.1:8b. User can change via Settings.
// Future: list available models by hitting /api/tags.

import Foundation

private struct OllamaRequest: Encodable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let format: String?       // "json" forces structured output on supported models
    let options: OllamaOptions?
}

private struct OllamaMessage: Encodable {
    let role: String          // "system" | "user" | "assistant"
    let content: String
}

private struct OllamaOptions: Encodable {
    let temperature: Double
}

private struct OllamaResponse: Decodable {
    let message: OllamaResponseMessage?
    let prompt_eval_count: Int?    // input tokens
    let eval_count: Int?           // output tokens
    struct OllamaResponseMessage: Decodable {
        let content: String
    }
}

private struct OllamaTagsResponse: Decodable {
    let models: [Model]

    struct Model: Decodable {
        let name: String
        let model: String?
    }
}

struct OllamaEnricher: AITaskEnricher {

    let provider: AIProvider = .ollama

    /// Where the user's Ollama server lives. Persisted in @AppStorage by
    /// the Settings UI; read here at call time.
    private func configuredHostURL() throws -> URL {
        let stored = UserDefaults.standard.string(forKey: "ai.ollama.host")
            ?? "http://localhost:11434"
        return try OllamaEndpointPolicy.validatedURL(stored)
    }

    /// User-selected model. Falls back to the provider default.
    private var modelID: String {
        let stored = UserDefaults.standard.string(forKey: "ai.ollama.model")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }
        return provider.defaultModel
    }

    func isAvailable() async -> Bool {
        guard let hostURL = try? configuredHostURL() else { return false }
        // Probe Ollama's API rather than accepting any web server at the host.
        var req = URLRequest(url: hostURL.appendingPathComponent("api/tags"))
        req.httpMethod = "GET"
        req.timeoutInterval = 4
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            else { return false }
            return decoded.models.contains {
                $0.name == modelID || $0.model == modelID
            }
        } catch {
            return false
        }
    }

    func enrich(context: EnrichmentContext) async throws -> TaskEnrichment {
        try AIOutboundPolicy.enforce(provider: provider)
        let hostURL = try configuredHostURL()
        let url = hostURL.appendingPathComponent("api/chat")
        let model = modelID

        let systemContent = """
        \(EnrichmentPrompt.system(for: context))

        Respond with a JSON object that validates against this schema:
        \(EnrichmentPrompt.jsonSchema(allowInterest: context.personalization?.allowInterestInference ?? false))
        """
        let userContent = EnrichmentPrompt.userMessage(for: context)

        let body = OllamaRequest(
            model: model,
            messages: [
                OllamaMessage(role: "system", content: systemContent),
                OllamaMessage(role: "user",   content: userContent)
            ],
            stream: false,
            format: "json",
            options: OllamaOptions(temperature: 0.3)
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 60        // local models can be slow

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw AIEnricherError.networkFailure(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIEnricherError.invalidResponse(detail: "no HTTP response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw AIEnricherError.invalidResponse(detail: "HTTP \(http.statusCode): \(bodyStr)")
        }

        let decoded: OllamaResponse
        do {
            decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
        } catch {
            throw AIEnricherError.invalidResponse(detail: "outer decode failed")
        }

        guard let content = decoded.message?.content,
              let contentData = content.data(using: .utf8) else {
            throw AIEnricherError.invalidResponse(detail: "no content")
        }

        var enrichment: TaskEnrichment
        do {
            enrichment = try EnrichmentPayloadDecoder.decode(contentData)
        } catch {
            throw AIEnricherError.invalidResponse(detail: "inner decode failed")
        }

        enrichment.usage = TaskEnrichment.Usage(
            provider:         provider.rawValue,
            model:            model,
            promptTokens:     decoded.prompt_eval_count ?? 0,
            completionTokens: decoded.eval_count ?? 0
        )
        if context.personalization?.allowInterestInference != true {
            enrichment.interest = nil
        }
        return enrichment
    }
}
