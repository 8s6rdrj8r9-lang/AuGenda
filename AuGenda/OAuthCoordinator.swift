// OAuthCoordinator.swift
// AuGenda
//
// Generic OAuth2 Authorization Code + PKCE flow via Apple's
// AuthenticationServices framework. No third-party SDK dependencies.
//
// Used today only by Google for Gemini sign-in (see GoogleOAuth.swift)
// — other AI providers don't expose third-party OAuth. The scaffolding
// is generic enough to support more if/when providers add OAuth.
//
// Token storage:
//   * Access + refresh tokens → Keychain, per-provider (separate
//     entries from API keys; an "oauth-{provider}" account name).
//     Written with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly so the
//     long-lived refresh token never rides along in an encrypted iCloud
//     device backup or iCloud Keychain — it stays on this device only.
//   * Expiry is encoded with the token record in Keychain so we know when
//     to refresh without unwrapping the JWT.
//
// Flow:
//   1. Generate PKCE verifier + challenge
//   2. Build authorize URL with challenge, scope, redirect URI
//   3. Open ASWebAuthenticationSession in-app
//   4. Receive callback URL with auth code
//   5. POST to token endpoint (code + verifier) → access + refresh tokens
//   6. Store + return

import Foundation
import Combine
import os.log
import Security
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if os(iOS)
import UIKit
#endif

private let logger = Logger(subsystem: "com.augenda.AuGenda", category: "OAuthCoordinator")

// MARK: - Tokens

struct OAuthTokens: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    /// Absolute date this access token expires. Refresh ~30s before.
    var expiresAt: Date?

    var isExpiredOrAboutTo: Bool {
        guard let expiry = expiresAt else { return false }
        return expiry.addingTimeInterval(-30) <= .now
    }
}

// MARK: - Provider config

struct OAuthProviderConfig {
    let provider: AIProvider
    let clientID: String
    let redirectURI: String       // must be a custom URL scheme registered to this app
    let scope: String
    let authEndpoint: URL
    let tokenEndpoint: URL
    /// Some providers (Google) need this query param appended on the
    /// authorize URL to return refresh tokens on subsequent runs.
    let extraAuthParams: [URLQueryItem]
}

// MARK: - Errors

enum OAuthError: Error, LocalizedError {
    case userCancelled
    case missingCode
    case missingState
    case stateMismatch
    case tokenExchangeFailed(detail: String)
    case configMissing
    case noKnownTokens
    case expiredToken
    case sessionStartFailed
    case secureRandomFailed

    var errorDescription: String? {
        switch self {
        case .userCancelled:                 return "Sign-in cancelled."
        case .missingCode:                   return "Provider didn't return an auth code."
        case .missingState, .stateMismatch:  return "Auth state mismatch — possible interception."
        case .tokenExchangeFailed(let d):    return "Token exchange failed: \(d)"
        case .configMissing:                 return "Google OAuth is not configured for this build."
        case .noKnownTokens:                 return "Not signed in."
        case .expiredToken:                  return "Your sign-in expired. Sign in again."
        case .sessionStartFailed:            return "Couldn't start the secure sign-in session."
        case .secureRandomFailed:            return "Couldn't create secure sign-in credentials."
        }
    }
}

// MARK: - Token storage helpers

private extension OAuthTokens {
    /// Keychain account name for this provider's OAuth tokens (separate
    /// from the provider's API key, which uses a different account).
    static func keychainAccount(for provider: AIProvider) -> String {
        "oauth-\(provider.rawValue)"
    }
}

// MARK: - Coordinator

@MainActor
final class OAuthCoordinator: NSObject, ObservableObject {

    static let shared = OAuthCoordinator()
    private static let oauthKeychainService = "com.augenda.AuGenda.oauth"

    /// Raw record presence for deletion UI. Unlike `isSignedIn`, this does not
    /// decode, refresh, or remove an expired record; even an unusable token must
    /// remain visible so the user can retry deletion after a Keychain failure.
    func hasStoredTokenRecord(provider: AIProvider) -> Bool {
        do {
            return try KeychainStore.getData(
                service: Self.oauthKeychainService,
                account: OAuthTokens.keychainAccount(for: provider)
            ) != nil
        } catch {
            logger.error(
                "Could not determine whether an OAuth token record exists: \(error.localizedDescription, privacy: .public)"
            )
            return true
        }
    }

    /// True iff this provider has tokens stored locally.
    func isSignedIn(provider: AIProvider) -> Bool {
        guard let tokens = readTokens(for: provider) else { return false }
        if tokens.isExpiredOrAboutTo, tokens.refreshToken == nil {
            signOut(provider: provider)
            return false
        }
        return true
    }

    /// Read tokens (decoded from Keychain). Nil if not signed in or decode fails.
    func readTokens(for provider: AIProvider) -> OAuthTokens? {
        let account = OAuthTokens.keychainAccount(for: provider)
        let data: Data
        do {
            guard let stored = try KeychainStore.getData(
                service: Self.oauthKeychainService,
                account: account
            ) else {
                return nil
            }
            data = stored
        } catch {
            logger.error("Failed to read stored OAuth tokens: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let tokens: OAuthTokens
        do {
            tokens = try JSONDecoder().decode(OAuthTokens.self, from: data)
        } catch {
            logger.error("Failed to decode stored OAuth tokens: \(error.localizedDescription, privacy: .public)")
            signOut(provider: provider)
            return nil
        }
        guard !tokens.accessToken.isEmpty else {
            signOut(provider: provider)
            return nil
        }
        return tokens
    }

    /// Write tokens to Keychain (insert or update).
    func writeTokens(_ tokens: OAuthTokens, for provider: AIProvider) throws {
        guard !tokens.accessToken.isEmpty else {
            throw OAuthError.tokenExchangeFailed(detail: "empty access token")
        }
        let account = OAuthTokens.keychainAccount(for: provider)
        let data = try JSONEncoder().encode(tokens)
        do {
            try KeychainStore.setData(data, service: Self.oauthKeychainService, account: account)
        } catch {
            throw OAuthError.tokenExchangeFailed(detail: "keychain write: \(error.localizedDescription)")
        }
    }

    /// Sign out — drops local tokens. Does NOT revoke server-side; the
    /// user can do that from their provider console if they want.
    @discardableResult
    func signOut(provider: AIProvider) -> Bool {
        do {
            try KeychainStore.remove(
                service: Self.oauthKeychainService,
                account: OAuthTokens.keychainAccount(for: provider)
            )
            return true
        } catch {
            logger.error(
                "Failed to remove OAuth tokens during sign-out: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    // MARK: - Authorize

    #if canImport(AuthenticationServices)
    /// Run the full PKCE authorize + token-exchange flow. Throws on
    /// cancel / network failure / state mismatch.
    @MainActor
    func authorize(config: OAuthProviderConfig) async throws -> OAuthTokens {
        let verifier  = try Self.makePKCEVerifier()
        let challenge = Self.makePKCEChallenge(verifier: verifier)
        let state     = UUID().uuidString

        // Build authorize URL
        var comps = URLComponents(url: config.authEndpoint, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "client_id",             value: config.clientID),
            URLQueryItem(name: "redirect_uri",          value: config.redirectURI),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "scope",                 value: config.scope),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state",                 value: state)
        ]
        items.append(contentsOf: config.extraAuthParams)
        comps.queryItems = items

        guard let authURL = comps.url else {
            throw OAuthError.configMissing
        }

        // Extract the callback scheme from the redirect URI for ASWebAuth.
        let scheme = URL(string: config.redirectURI)?.scheme ?? "com.augenda.AuGenda"

        // Run ASWebAuthenticationSession with the modern Callback API
        // when available, falling back to callbackURLScheme on older OS.
        let callbackURL = try await Self.runWebAuthSession(
            url: authURL,
            callbackScheme: scheme
        )

        // Parse callback URL for code + state
        let cbComps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let cbItems = cbComps?.queryItems ?? []
        guard let returnedState = cbItems.first(where: { $0.name == "state" })?.value else {
            throw OAuthError.missingState
        }
        guard returnedState == state else {
            throw OAuthError.stateMismatch
        }
        guard let code = cbItems.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.missingCode
        }

        // Exchange code for tokens
        let tokens = try await exchangeCodeForTokens(
            code: code,
            verifier: verifier,
            config: config
        )
        try writeTokens(tokens, for: config.provider)
        return tokens
    }

    /// Refresh tokens for a provider. Uses the stored refresh_token.
    func refreshTokens(config: OAuthProviderConfig) async throws -> OAuthTokens {
        guard let existing = readTokens(for: config.provider),
              let refresh = existing.refreshToken else {
            throw OAuthError.noKnownTokens
        }

        var req = URLRequest(url: config.tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id":     config.clientID,
            "refresh_token": refresh,
            "grant_type":    "refresh_token"
        ]
        req.httpBody = Self.formURLEncoded(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw OAuthError.tokenExchangeFailed(detail: "refresh network failure")
        }
        guard let http = response as? HTTPURLResponse else {
            throw OAuthError.tokenExchangeFailed(detail: "refresh missing HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 400 || http.statusCode == 401 {
                signOut(provider: config.provider)
                throw OAuthError.expiredToken
            }
            throw OAuthError.tokenExchangeFailed(detail: "refresh HTTP \(http.statusCode)")
        }

        let decoded: TokenResponse
        do {
            decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            logger.error("Failed to decode token refresh response: \(error.localizedDescription, privacy: .public)")
            throw OAuthError.tokenExchangeFailed(detail: "decode: \(error.localizedDescription)")
        }

        let tokens = OAuthTokens(
            accessToken:  decoded.access_token,
            refreshToken: decoded.refresh_token ?? existing.refreshToken,
            expiresAt:    decoded.expires_in.map { .now.addingTimeInterval(TimeInterval($0)) }
        )
        try writeTokens(tokens, for: config.provider)
        return tokens
    }

    /// Get a valid access token, refreshing if needed. Used by adapters.
    func validAccessToken(config: OAuthProviderConfig) async throws -> String {
        guard let tokens = readTokens(for: config.provider) else {
            throw OAuthError.noKnownTokens
        }
        if tokens.isExpiredOrAboutTo {
            guard tokens.refreshToken != nil else {
                signOut(provider: config.provider)
                throw OAuthError.expiredToken
            }
            let refreshed = try await refreshTokens(config: config)
            return refreshed.accessToken
        }
        return tokens.accessToken
    }

    // MARK: - Token exchange

    private struct TokenResponse: Decodable {
        let access_token:  String
        let refresh_token: String?
        let expires_in:    Int?
        let token_type:    String?
    }

    private func exchangeCodeForTokens(
        code: String,
        verifier: String,
        config: OAuthProviderConfig
    ) async throws -> OAuthTokens {
        var req = URLRequest(url: config.tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id":     config.clientID,
            "code":          code,
            "code_verifier": verifier,
            "redirect_uri":  config.redirectURI,
            "grant_type":    "authorization_code"
        ]
        req.httpBody = Self.formURLEncoded(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(150) ?? ""
            throw OAuthError.tokenExchangeFailed(detail: "non-2xx: \(snippet)")
        }

        let decoded: TokenResponse
        do {
            decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            logger.error("Failed to decode token exchange response: \(error.localizedDescription, privacy: .public)")
            throw OAuthError.tokenExchangeFailed(detail: "decode failed: \(error.localizedDescription)")
        }

        return OAuthTokens(
            accessToken:  decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt:    decoded.expires_in.map { .now.addingTimeInterval(TimeInterval($0)) }
        )
    }

    /// Encode an application/x-www-form-urlencoded body without allowing
    /// query delimiters (`&`, `+`, `=`) through inside OAuth token values.
    static func formURLEncoded(_ parameters: [String: String]) -> Data {
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        let body = parameters
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(
                    withAllowedCharacters: unreserved
                ) ?? ""
                let encodedValue = value.addingPercentEncoding(
                    withAllowedCharacters: unreserved
                ) ?? ""
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    // MARK: - Web auth session helper

    /// Wrap ASWebAuthenticationSession in async/await. Uses the modern
    /// `Callback` API for richer return values; falls back to the older
    /// `callbackURLScheme` initializer when needed.
    @MainActor
    private static func runWebAuthSession(
        url: URL,
        callbackScheme: String
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let nserror = error as? NSError,
                   nserror.domain == ASWebAuthenticationSessionError.errorDomain,
                   nserror.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    continuation.resume(throwing: OAuthError.userCancelled)
                    return
                }
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: OAuthError.missingCode)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = OAuthPresentationProvider.shared
            session.prefersEphemeralWebBrowserSession = false
            guard session.start() else {
                continuation.resume(throwing: OAuthError.sessionStartFailed)
                return
            }
        }
    }

    // MARK: - PKCE helpers

    private static func makePKCEVerifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw OAuthError.secureRandomFailed
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func makePKCEChallenge(verifier: String) -> String {
        let hash = sha256(verifier)
        return hash.base64URLEncodedString()
    }

    private static func sha256(_ input: String) -> Data {
        // CryptoKit is available on iOS 13+ / macOS 10.15+ — we're way past that.
        // Use CC_SHA256 to avoid the import on Catalyst edge cases.
        let data = Data(input.utf8)
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buf in
            _ = CC_SHA256_helper(buf.baseAddress, UInt32(buf.count), &hash)
        }
        return Data(hash)
    }
    #endif
}

// MARK: - ASWebAuthenticationPresentationContextProviding

#if canImport(AuthenticationServices)
@MainActor
final class OAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthPresentationProvider()

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        MainActor.assumeIsolated {
            Self.currentPresentationAnchor()
        }
        #else
        MainActor.assumeIsolated {
            ASPresentationAnchor()
        }
        #endif
    }

    #if os(iOS)
    @MainActor
    private static func currentPresentationAnchor() -> ASPresentationAnchor {
        // Find the active window scene's key window; if launch timing means no
        // key window is registered yet, create an anchor bound to that scene.
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive }

        if let keyWindow = activeScene?.windows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }

        if let anchorScene = activeScene ?? scenes.first {
            return ASPresentationAnchor(windowScene: anchorScene)
        }

        // ASWebAuthenticationSession can ask for its anchor while the app is
        // between scene transitions. Returning a detached anchor lets
        // `session.start()` fail through the normal recoverable error path
        // instead of crashing the process.
        return ASPresentationAnchor()
    }
    #endif
}
#endif

// MARK: - Base64URL + CommonCrypto bridge

extension Data {
    fileprivate func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// CommonCrypto's CC_SHA256 is a C function that doesn't bridge cleanly
// to Swift Concurrency Sendable types when called from @MainActor
// closures with capturing. Wrap it in a free function so the @MainActor
// site stays clean.
@_silgen_name("CC_SHA256")
private func CC_SHA256_helper(
    _ data: UnsafeRawPointer?,
    _ len: UInt32,
    _ md: UnsafeMutablePointer<UInt8>
) -> UnsafeMutablePointer<UInt8>?
