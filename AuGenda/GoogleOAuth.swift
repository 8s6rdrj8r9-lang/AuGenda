// GoogleOAuth.swift
// AuGenda
//
// Google Sign-In configuration for Gemini API access. Wraps the generic
// OAuthCoordinator with Google's specific endpoints + scope.
//
// Google Sign-In is optional. Placeholder builds keep the Sign-In button
// disabled, while the Gemini API-key path remains available. To enable OAuth:
//
//   1. Create a Google Cloud project (or reuse one):
//      https://console.cloud.google.com/projectcreate
//   2. Enable the Generative Language API for the project.
//   3. Configure OAuth consent screen (external).
//      Required scopes:
//        https://www.googleapis.com/auth/generative-language
//      Add yourself as a test user during development.
//   4. Create an OAuth 2.0 Client ID:
//        Application type: iOS
//        Bundle ID: <your AuGenda bundle id, e.g. ensdev.AuGenda>
//        (No client secret on iOS clients)
//   5. Set the `AuGendaGoogleClientID` Info.plist value (normally through
//      an Xcode build-setting substitution) to the new client's ID:
//        123456789012-xxxxxxx.apps.googleusercontent.com
//   6. Set `AuGendaGoogleRedirectScheme` to the reversed client ID and
//      register that exact scheme under CFBundleURLTypes:
//        com.googleusercontent.apps.123456789012-xxxxxxx
//      The redirect URI is `{REVERSED_CLIENT_ID}:/oauth2redirect`.
//
// Until this is real, the "Sign in with Google" button remains disabled.

import Foundation

enum GoogleOAuth {

    private static let clientIDInfoKey = "AuGendaGoogleClientID"
    private static let redirectSchemeInfoKey = "AuGendaGoogleRedirectScheme"

    // OAuth client IDs and redirect schemes are public application
    // configuration, not secrets. They are injected into Info.plist so the
    // same values are available in an archived/TestFlight build; API keys and
    // OAuth tokens remain in Keychain.
    static let clientID = infoString(for: clientIDInfoKey)
    static let redirectScheme = infoString(for: redirectSchemeInfoKey)

    /// Reversed-DNS form is what Google requires for iOS OAuth clients.
    /// Must match the URL scheme registered in Info.plist (CFBundleURLTypes).
    static let redirectURI = redirectScheme.isEmpty
        ? ""
        : "\(redirectScheme):/oauth2redirect"

    /// Scope for Gemini / Generative Language API access.
    static let scope = "https://www.googleapis.com/auth/generative-language"

    static let authEndpoint  = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    /// Checks the complete runtime configuration. A build is configured only
    /// when both Info.plist values are valid, the redirect scheme is the
    /// reversed client ID, and that exact scheme is registered with iOS.
    static var isConfigured: Bool {
        validateConfiguration(
            clientID: clientID,
            redirectScheme: redirectScheme,
            registeredSchemes: registeredURLSchemes()
        )
    }

    static func validateConfiguration(
        clientID: String,
        redirectScheme: String,
        registeredSchemes: Set<String>
    ) -> Bool {
        let normalizedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedScheme = redirectScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedClientID.isEmpty,
              !normalizedClientID.contains("$("),
              !normalizedClientID.localizedCaseInsensitiveContains("YOUR_CLIENT_ID"),
              normalizedClientID.hasSuffix(".apps.googleusercontent.com"),
              !normalizedScheme.isEmpty,
              !normalizedScheme.contains("$("),
              normalizedScheme.range(
                of: #"^[A-Za-z][A-Za-z0-9+.-]*$"#,
                options: .regularExpression
              ) != nil else {
            return false
        }

        let expectedScheme = normalizedClientID
            .components(separatedBy: ".")
            .reversed()
            .joined(separator: ".")
        guard normalizedScheme.caseInsensitiveCompare(expectedScheme) == .orderedSame else {
            return false
        }

        return registeredSchemes.contains {
            $0.caseInsensitiveCompare(normalizedScheme) == .orderedSame
        }
    }

    /// Static config for the generic coordinator. Google requires
    /// `access_type=offline` + `prompt=consent` to consistently return
    /// a refresh_token, so include those as extra auth params.
    static var providerConfig: OAuthProviderConfig {
        OAuthProviderConfig(
            provider:        .gemini,
            clientID:        clientID,
            redirectURI:     redirectURI,
            scope:           scope,
            authEndpoint:    authEndpoint,
            tokenEndpoint:   tokenEndpoint,
            extraAuthParams: [
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt",      value: "consent")
            ]
        )
    }

    /// Returns a valid access token, refreshing if needed. Throws if not
    /// signed in. Adapters call this in place of reading the API key from
    /// the Keychain.
    @MainActor
    static func currentAccessToken() async throws -> String {
        guard isConfigured else { throw OAuthError.configMissing }
        return try await OAuthCoordinator.shared.validAccessToken(config: providerConfig)
    }

    @MainActor
    static var isSignedIn: Bool {
        isConfigured && OAuthCoordinator.shared.isSignedIn(provider: .gemini)
    }

    /// Local credential presence is independent of whether this build's
    /// Info.plist configuration is valid, so Settings can always offer a way
    /// to remove a previously stored token.
    @MainActor
    static var hasLocalSession: Bool {
        OAuthCoordinator.shared.hasStoredTokenRecord(provider: .gemini)
    }

    @MainActor
    static func authorize() async throws -> OAuthTokens {
        guard isConfigured else { throw OAuthError.configMissing }
        return try await OAuthCoordinator.shared.authorize(config: providerConfig)
    }

    private static func infoString(for key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func registeredURLSchemes() -> Set<String> {
        guard let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes")
                as? [[String: Any]] else {
            return []
        }

        return Set(
            urlTypes
                .compactMap { $0["CFBundleURLSchemes"] as? [String] }
                .flatMap { $0 }
                .map { $0.lowercased() }
        )
    }
}
