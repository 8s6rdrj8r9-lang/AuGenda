// GoogleOAuth.swift
// AuGenda
//
// Google Sign-In configuration for Gemini API access. Wraps the generic
// OAuthCoordinator with Google's specific endpoints + scope.
//
// 🚨 TESTFLIGHT BLOCKER 🚨
//
// The clientID below is a PLACEHOLDER. To ship Google Sign-In to users:
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
//   5. Replace `clientID` below with the new client's ID, in the form:
//        123456789012-xxxxxxx.apps.googleusercontent.com
//   6. Register the reversed-DNS URL scheme in Info.plist under
//      CFBundleURLTypes:
//        com.googleusercontent.apps.123456789012-xxxxxxx
//      The redirect URI is `{REVERSED_CLIENT_ID}:/oauth2redirect`.
//   7. Update `redirectURI` below to match.
//
// Until this is real, the "Sign in with Google" button in Settings will
// fail with `tokenExchangeFailed` or open Google's OAuth screen showing
// a "401: invalid_client" error.

import Foundation

enum GoogleOAuth {

    // Real iOS OAuth client (project: AuGenda). iOS clients have no secret,
    // and the reversed-ID scheme ships in the bundle anyway, so this is fine
    // in source. To re-create, follow the checklist above.
    static let clientID = "416358058147-9g1kdn4bpip0ink7mg0ou6foj1a3nk4k.apps.googleusercontent.com"

    /// Reversed-DNS form is what Google requires for iOS OAuth clients.
    /// Must match the URL scheme registered in Info.plist (CFBundleURLTypes).
    static let redirectURI = "com.googleusercontent.apps.416358058147-9g1kdn4bpip0ink7mg0ou6foj1a3nk4k:/oauth2redirect"

    /// Scope for Gemini / Generative Language API access.
    static let scope = "https://www.googleapis.com/auth/generative-language"

    static let authEndpoint  = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    /// Quick check — is the OAuth client configured? Used by the
    /// Settings UI to disable the Sign-In button on placeholder builds.
    static var isConfigured: Bool {
        !clientID.contains("PLACEHOLDER")
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
        try await OAuthCoordinator.shared.validAccessToken(config: providerConfig)
    }

    @MainActor
    static var isSignedIn: Bool {
        OAuthCoordinator.shared.isSignedIn(provider: .gemini)
    }
}
