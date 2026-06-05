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
// Privacy tier: .selfHosted — data goes over the user's own network,
// never to a third-party cloud.
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

struct OllamaEnricher: AITaskEnricher {

    let provider: AIProvider = .ollama

    /// Where the user's Ollama server lives. Persisted in @AppStorage by
    /// the Settings UI; read here at call time.
    private var hostURL: URL {
        let stored = UserDefaults.standard.string(forKey: "ai.ollama.host")
            ?? "http://localhost:11434"
        return URL(string: stored) ?? URL(string: "http://localhost:11434")!
    }

    /// User-selected model. Falls back to the provider default.
    private var modelID: String {
        UserDefaults.standard.string(forKey: "ai.ollama.model")
            ?? provider.defaultModel
    }

    func isAvailable() async -> Bool {
        // Probe the server's root endpoint. Cheap, no model load.
        var req = URLRequest(url: hostURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 4
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return true
            }
            return false
        } catch {
            return false
        }
    }

    func enrich(context: EnrichmentContext) async throws -> TaskEnrichment {
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
            enrichment = try JSONDecoder().decode(TaskEnrichment.self, from: contentData)
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
