// AIEnricher_Gemini.swift
// AuGenda
//
// Google Gemini adapter. Different shape from OpenAI's chat-completions:
//   * Endpoint: /v1beta/models/{model}:generateContent?key={key}
//   * API key goes as a query parameter, not a header
//   * Content uses `contents[].parts[].text` shape
//   * Structured output via `generationConfig.responseSchema`
//
// API ref: https://ai.google.dev/api/generate-content

import Foundation

private struct GeminiRequest: Encodable {
    let contents: [GContent]
    let systemInstruction: GContent
    let generationConfig: GGenConfig
}

private struct GContent: Encodable {
    let parts: [GPart]
}

private struct GPart: Encodable {
    let text: String
}

private struct GGenConfig: Encodable {
    let temperature: Double
    let responseMimeType: String      // "application/json"
}

private struct GeminiResponse: Decodable {
    let candidates: [GCandidate]?
    let usageMetadata: GUsage?

    struct GCandidate: Decodable {
        let content: GContentResp?
    }
    struct GContentResp: Decodable {
        let parts: [GPartResp]?
    }
    struct GPartResp: Decodable {
        let text: String?
    }
    struct GUsage: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
    }
}

struct GeminiEnricher: AITaskEnricher {

    let provider: AIProvider = .gemini

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    func isAvailable() async -> Bool {
        // Either OAuth sign-in OR a stored API key satisfies availability.
        if await MainActor.run(body: { GoogleOAuth.isSignedIn }) { return true }
        return KeychainStore.hasKey(for: provider)
    }

    func enrich(context: EnrichmentContext) async throws -> TaskEnrichment {
        let model = provider.defaultModel

        // Auth: prefer OAuth (more personalized — Google associates the
        // call with the user's actual account + project), fall back to
        // API key if signed-in tokens aren't available.
        let oauthToken: String? = await {
            do {
                return try await GoogleOAuth.currentAccessToken()
            } catch {
                return nil
            }
        }()

        let url: URL
        var bearerToken: String? = nil

        if let token = oauthToken {
            // OAuth path — token goes in Authorization header.
            guard let u = URL(string: "\(baseURL)/\(model):generateContent") else {
                throw AIEnricherError.invalidResponse(detail: "url construction failed")
            }
            url = u
            bearerToken = token
        } else {
            // API key path — key goes as query parameter.
            guard let key = try KeychainStore.get(for: provider), !key.isEmpty else {
                throw AIEnricherError.missingAPIKey
            }
            guard let u = URL(string: "\(baseURL)/\(model):generateContent?key=\(key)") else {
                throw AIEnricherError.invalidResponse(detail: "url construction failed")
            }
            url = u
        }

        let systemContent = """
        \(EnrichmentPrompt.system(for: context))

        Respond with a JSON object that validates against this schema:
        \(EnrichmentPrompt.jsonSchema(allowInterest: context.personalization?.allowInterestInference ?? false))

        Output ONLY the JSON object.
        """
        let userContent = EnrichmentPrompt.userMessage(for: context)

        let body = GeminiRequest(
            contents: [GContent(parts: [GPart(text: userContent)])],
            systemInstruction: GContent(parts: [GPart(text: systemContent)]),
            generationConfig: GGenConfig(
                temperature: 0.3,
                responseMimeType: "application/json"
            )
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer = bearerToken {
            req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
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

        let decoded: GeminiResponse
        do {
            decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        } catch {
            throw AIEnricherError.invalidResponse(detail: "outer decode failed")
        }

        guard let text = decoded.candidates?.first?.content?.parts?.first?.text else {
            throw AIEnricherError.invalidResponse(detail: "no text in candidates")
        }

        guard let textData = text.data(using: .utf8) else {
            throw AIEnricherError.invalidResponse(detail: "content not utf8")
        }

        var enrichment: TaskEnrichment
        do {
            enrichment = try JSONDecoder().decode(TaskEnrichment.self, from: textData)
        } catch {
            // Strip fences and retry
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
            promptTokens:     decoded.usageMetadata?.promptTokenCount ?? 0,
            completionTokens: decoded.usageMetadata?.candidatesTokenCount ?? 0
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
