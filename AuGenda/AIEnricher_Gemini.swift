// AIEnricher_Gemini.swift
// AuGenda
//
// Google Gemini adapter. Different shape from OpenAI's chat-completions:
//   * Endpoint: /v1beta/models/{model}:generateContent
//   * API key goes in the x-goog-api-key header; OAuth uses Bearer auth
//   * Content uses `contents[].parts[].text` shape
//   * Structured output via `generationConfig.responseSchema`
//
// API ref: https://ai.google.dev/api/generate-content

import Foundation
import os.log

private let logger = Logger(subsystem: "com.augenda.AuGenda", category: "AIEnricherGemini")

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
        do {
            let authentication = try await authentication()
            guard let url = URL(string: "\(baseURL)/\(provider.defaultModel)") else {
                return false
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            apply(authentication, to: &request)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if (http.statusCode == 401 || http.statusCode == 403),
               case .oauth = authentication {
                await invalidateOAuthSession()
            }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    func enrich(context: EnrichmentContext) async throws -> TaskEnrichment {
        let model = provider.defaultModel

        // Prefer a valid OAuth token. Never silently fall back to API-key
        // billing from a selected Google session; the user must sign out first.
        let authentication = try await authentication()
        guard let url = URL(string: "\(baseURL)/\(model):generateContent") else {
            throw AIEnricherError.invalidResponse(detail: "url construction failed")
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
        apply(authentication, to: &req)
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
            if case .oauth = authentication {
                await invalidateOAuthSession()
                throw OAuthError.expiredToken
            }
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
            enrichment = try EnrichmentPayloadDecoder.decode(textData)
        } catch {
            // Strip fences and retry
            let stripped = Self.stripCodeFences(text)
            guard let strippedData = stripped.data(using: .utf8) else {
                throw AIEnricherError.invalidResponse(detail: "inner decode failed")
            }
            let retry: TaskEnrichment
            do {
                retry = try EnrichmentPayloadDecoder.decode(strippedData)
            } catch {
                logger.error("Gemini inner decode failed after stripping fences: \(error.localizedDescription, privacy: .public)")
                throw AIEnricherError.invalidResponse(detail: "inner decode failed: \(error.localizedDescription)")
            }
            enrichment = retry
        }

        guard let wireUsage = decoded.usageMetadata,
              let promptTokens = wireUsage.promptTokenCount,
              let completionTokens = wireUsage.candidatesTokenCount else {
            throw AIEnricherError.invalidResponse(detail: "missing token usage")
        }
        enrichment.usage = TaskEnrichment.Usage(
            provider:         provider.rawValue,
            model:            model,
            promptTokens:     promptTokens,
            completionTokens: completionTokens
        )
        if context.personalization?.allowInterestInference != true {
            enrichment.interest = nil
        }
        return enrichment
    }

    private enum Authentication {
        case oauth(String)
        case apiKey(String)
    }

    private func authentication() async throws -> Authentication {
        let oauthState = await MainActor.run {
            (isConfigured: GoogleOAuth.isConfigured, hasRecord: GoogleOAuth.hasLocalSession)
        }
        if oauthState.isConfigured, oauthState.hasRecord {
            let token = try await GoogleOAuth.currentAccessToken()
            return .oauth(token)
        }

        guard let key = try KeychainStore.get(for: provider), !key.isEmpty else {
            throw AIEnricherError.missingAPIKey
        }
        return .apiKey(key)
    }

    private func apply(_ authentication: Authentication, to request: inout URLRequest) {
        switch authentication {
        case .oauth(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .apiKey(let key):
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        }
    }

    private func invalidateOAuthSession() async {
        _ = await MainActor.run {
            OAuthCoordinator.shared.signOut(provider: .gemini)
        }
    }

    private static func stripCodeFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```json") { t.removeFirst("```json".count) }
        else if t.hasPrefix("```") { t.removeFirst(3) }
        if t.hasSuffix("```") { t.removeLast(3) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
