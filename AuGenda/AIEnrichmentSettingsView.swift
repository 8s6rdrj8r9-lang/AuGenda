// AIEnrichmentSettingsView.swift
// AuGenda
//
// Settings → AI Enrichment screen. The user opts in here (OFF by default,
// per the spec). Once enabled, picks a provider, optionally enters an
// API key, optionally toggles auto-enrich.
//
// Layered consent (matches spec's "Privacy model" section):
//   1. AI off            → only the master toggle is visible
//   2. AI on, no provider → master toggle + provider picker
//   3. Provider chosen   → + API key field, test button, behavior toggles
//   4. Auto-enrich on    → + warning that new tasks are enriched on save
//
// API keys: written via KeychainStore, never @AppStorage / iCloud.

import SwiftUI

// MARK: - View

struct AIEnrichmentSettingsView: View {

    // Master toggle — OFF by default per spec.
    @AppStorage("ai.enabled") private var aiEnabled: Bool = false

    // Active provider (rawValue). Defaults to on-device Apple Foundation Models.
    @AppStorage("ai.activeProvider") private var activeProviderRaw: String = "apple-foundation"

    // Backup provider fallback (macOS 27).
    @AppStorage("ai.backupProvider") private var backupProviderRaw: String = "openai"
    @AppStorage("ai.enableBackupFallback") private var enableBackupFallback: Bool = true

    // Auto-enrich new tasks on save. OFF by default even after AI enabled.
    @AppStorage("ai.autoEnrichNewTasks") private var autoEnrich: Bool = false

    // Whether the per-task "Enrich" button is shown anywhere. ON by default
    // once AI is enabled — gives the user manual triggers without auto.
    @AppStorage("ai.showEnrichButtons") private var showEnrichButtons: Bool = true

    // Ollama-specific config (only used if Ollama is the active provider).
    @AppStorage("ai.ollama.host")  private var ollamaHost: String = "http://localhost:11434"
    @AppStorage("ai.ollama.model") private var ollamaModel: String = "llama3.1:8b"
    @AppStorage("ai.deepseek.model") private var deepSeekModel: String = ""

    // Local AI only mode — enforces the outbound host/provider boundary.
    @AppStorage("ai.localOnlyMode") private var localOnlyMode: Bool = false

    // Monthly AI budget cap (0 = unlimited)
    @AppStorage("ai.maxMonthlyCostUSD") private var maxMonthlyCostUSD: Double = 0

    // Local UI state
    @State private var apiKeyDraft: String = ""
    @State private var apiKeyExists: Bool = false
    @State private var testState: TestState = .idle
    @State private var testTask: Task<Void, Never>? = nil
    @State private var showAdvancedProviders: Bool = false
    @State private var pendingProvider: AIProvider? = nil  // disclosure prompt
    @State private var showDisclosure: Bool = false

    @StateObject private var ledger = AIUsageLedger.shared
    @StateObject private var personalization = PersonalizationStore.shared

    // Google OAuth UI state — separate from the generic test-state so the
    // sign-in button can update independently of the test button.
    @State private var googleSigningIn: Bool = false
    @State private var googleAuthError: String? = nil
    @State private var googleSignedIn: Bool = false
    @State private var usagePersistenceError: String? = nil
    @State private var personalizationPersistenceError: String? = nil

    private var activeProvider: AIProvider? {
        AIProvider(rawValue: activeProviderRaw)
    }

    /// Providers visible when local-only mode is active.
    private var visibleProviders: [AIProvider] {
        let releaseProviders = AIProvider.allCases.filter(\.isReleaseEnabled)
        if localOnlyMode {
            return releaseProviders.filter { $0 == .appleFoundation || $0 == .ollama }
        }
        return releaseProviders
    }

    var body: some View {
        Form {
            masterToggleSection

            if aiEnabled {
                providerPickerSection

                if let provider = activeProvider {
                    // Google Sign-In appears ABOVE the API-key section
                    // for Gemini — OAuth is the preferred auth when
                    // available.
                    if provider == .gemini {
                        googleSignInSection
                    }

                    if provider.requiresAPIKey {
                        apiKeySection(for: provider)
                        if provider == .deepseek {
                            deepSeekModelSection
                        }
                    } else if provider == .ollama {
                        ollamaConfigSection
                    } else if provider == .appleFoundation {
                        appleFoundationInfoSection
                    }

                    // Sign-in disclosure — only for providers that have
                    // a famous consumer subscription that users might
                    // expect to sign into (Claude / ChatGPT).
                    if provider == .claude || provider == .openai {
                        subscriptionDisclosureSection(for: provider)
                    }

                    behaviorSection
                    personalizationSection
                    usageSection
                }
            }

            footerLegalSection
        }
        .navigationTitle("AI Enrichment")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if let provider = activeProvider, !provider.isReleaseEnabled {
                activeProviderRaw = ""
            }
            syncKeyState()
            googleSignedIn = GoogleOAuth.hasLocalSession
            promptForStaleConsentIfNeeded()
        }
        .onChange(of: aiEnabled) { _, enabled in
            if enabled {
                promptForStaleConsentIfNeeded()
            } else {
                testTask?.cancel()
                testTask = nil
                testState = .idle
            }
        }
        .onDisappear {
            testTask?.cancel()
            testTask = nil
        }
        .onChange(of: activeProviderRaw) { _, _ in syncKeyState(); testState = .idle }
        .onChange(of: deepSeekModel) { _, _ in testState = .idle }
        .onChange(of: ollamaHost) { _, _ in testState = .idle }
        .onChange(of: localOnlyMode) { _, isLocal in
            if isLocal, let provider = activeProvider, provider != .appleFoundation && provider != .ollama {
                activeProviderRaw = ""
            }
        }
        .alert(
            "Confirm provider",
            isPresented: $showDisclosure,
            presenting: pendingProvider
        ) { provider in
            Button("Use \(provider.displayName)") {
                AIConsentPolicy.recordConsent(for: provider)
                activeProviderRaw = provider.rawValue
                pendingProvider = nil
            }
            Button("Cancel", role: .cancel) {
                pendingProvider = nil
            }
        } message: { provider in
            Text(
                provider.consentDisclosure
                    + (provider == .ollama
                        ? "\n\nCurrent destination: \(ollamaHost)"
                        : "")
            )
        }
    }

    // MARK: - Sections

    private var masterToggleSection: some View {
        Section {
            Toggle(isOn: $aiEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable AI enrichment").fontWeight(.medium)
                    Text(aiEnabled
                         ? "On — pick a provider below."
                         : "Off — no task data leaves your device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .tint(Color.appAccent)

            if aiEnabled {
                Toggle(isOn: $localOnlyMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local AI only").fontWeight(.medium)
                        Text(localOnlyMode
                             ? "On — only on-device or locally addressed user-hosted providers."
                             : "Off — all providers available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .tint(Color.appAccent)
            }
        } footer: {
            if localOnlyMode {
                Text("Local AI only blocks cloud providers and remote Ollama hosts at the provider boundary. Apple runs on device; Ollama must use localhost or a private/local-network address.")
            } else {
                Text("AI enrichment auto-fills task metadata (difficulty axes, sub-tasks, time estimate) from your task title. Off by default. Even after enabling, no data leaves your device until you pick a provider AND enrich a task.")
            }
        }
    }

    private var providerPickerSection: some View {
        Section {
            // Primary providers
            ForEach(visibleProviders.filter { !$0.isAdvanced }) { provider in
                providerRow(provider)
            }

            // Advanced disclosure — only when not in local-only mode
            if !localOnlyMode {
                DisclosureGroup(isExpanded: $showAdvancedProviders) {
                    ForEach(visibleProviders.filter(\.isAdvanced)) { provider in
                        providerRow(provider)
                    }
                } label: {
                    HStack {
                        Text("Advanced providers").foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        } header: {
            Text("Provider")
        } footer: {
            Text(localOnlyMode
                 ? "On-device and locally addressed user-hosted providers only."
                 : "Apple runs on device. Ollama sends data to the host you configure, which may be local or remote. Cloud providers send the disclosed fields to their APIs and require credentials stored in this device's Keychain.")
        }
    }

    private func providerRow(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                // New providers and stale disclosure versions require an explicit
                // acknowledgement before the outbound boundary permits a call.
                if provider.rawValue != activeProviderRaw
                    || !AIConsentPolicy.hasCurrentConsent(for: provider) {
                    pendingProvider = provider
                    showDisclosure = true
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: provider.privacyTier.icon)
                        .foregroundStyle(privacyTint(provider.privacyTier))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(provider.displayName)
                                .foregroundStyle(.primary)
                                .fontWeight(activeProviderRaw == provider.rawValue ? .semibold : .regular)
                            Text(provider.privacyTier.label)
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(privacyTint(provider.privacyTier).opacity(0.15), in: Capsule())
                                .foregroundStyle(privacyTint(provider.privacyTier))
                        }
                        Text(provider.tagline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if activeProviderRaw == provider.rawValue {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.appAccent)
                    }
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            if let dataTermsURL = provider.dataTermsURL {
                Link(destination: dataTermsURL) {
                    Label("Review provider API data terms", systemImage: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityHint(
                    "Opens \(provider.displayName)'s official terms governing API data"
                )
            }
        }
    }

    private func privacyTint(_ tier: PrivacyTier) -> Color {
        switch tier {
        case .onDevice:   return .green
        case .selfHosted: return .blue
        case .cloud:      return .orange
        }
    }

    private func apiKeySection(for provider: AIProvider) -> some View {
        Section {
            SecureField(apiKeyExists ? "•••• stored in Keychain" : "Paste API key", text: $apiKeyDraft)
                .textContentType(.password)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

            HStack {
                Button {
                    saveKey(for: provider)
                } label: {
                    Label(apiKeyExists ? "Update key" : "Save key", systemImage: "key.fill")
                }
                .disabled(apiKeyDraft.isEmpty)

                Spacer()

                if apiKeyExists {
                    Button(role: .destructive) {
                        removeKey(for: provider)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }

            Button {
                startTest(for: provider)
            } label: {
                HStack(spacing: 8) {
                    switch testState {
                    case .idle:
                        Image(systemName: "play.circle")
                        Text("Test connection")
                    case .running:
                        ProgressView().controlSize(.small)
                        Text("Testing…")
                    case .ok:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Working")
                    case .failed(let message):
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(message).lineLimit(2)
                    }
                }
            }
            .disabled(
                !apiKeyExists
                    && !(provider == .gemini
                        && googleSignedIn
                        && GoogleOAuth.isConfigured)
            )
        } header: {
            Text("API key")
        } footer: {
            if provider == .perplexity {
                Text("Your key is stored in the device Keychain and is not synced to iCloud. Perplexity has no credential-introspection endpoint, so Test connection sends the synthetic word “Test” in a one-token chat-completions request to the configured model, which may use a minimal amount of quota. No task or profile data is included.")
            } else {
                Text("Your key is stored in the device Keychain. It is not synced to iCloud, and not visible to anyone else with access to your Apple ID. Remove it any time.")
            }
        }
    }

    private var ollamaHostWarning: String? {
        OllamaEndpointPolicy.warning(for: ollamaHost)
    }

    private var ollamaConfigSection: some View {
        Section {
            HStack {
                Text("Host")
                Spacer()
                TextField("http://localhost:11434", text: $ollamaHost)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            }
            if let warning = ollamaHostWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Tokens.Color.warning)
                    .accessibilityLabel("Warning: \(warning)")
            }
            if !AIConsentPolicy.hasCurrentConsent(for: .ollama) {
                Label(
                    "This server destination is not approved. Re-select Ollama above and review the disclosure before connecting.",
                    systemImage: "lock.trianglebadge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(Tokens.Color.warning)
            }
            HStack {
                Text("Model")
                Spacer()
                TextField("llama3.1:8b", text: $ollamaModel)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            }
            Button {
                startTest(for: .ollama)
            } label: {
                HStack(spacing: 8) {
                    switch testState {
                    case .idle:    Image(systemName: "play.circle"); Text("Test connection")
                    case .running: ProgressView().controlSize(.small); Text("Testing…")
                    case .ok:      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("Working")
                    case .failed(let m): Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text(m).lineLimit(2)
                    }
                }
            }
        } header: {
            Text("Ollama server")
        } footer: {
            Text("Point this at your Ollama server. Local HTTP is allowed for localhost, .local, link-local, and RFC 1918 addresses. Remote hosts require HTTPS and are blocked while Local AI only is on.")
        }
    }

    private var deepSeekModelSection: some View {
        Section {
            HStack {
                Text("Model ID")
                Spacer()
                TextField("Required", text: $deepSeekModel)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            }
            if DeepSeekEnricher.configuredModel(from: deepSeekModel) == nil {
                Label(
                    "Enter a current model ID. The retired deepseek-chat and deepseek-reasoner aliases are blocked.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(Tokens.Color.warning)
            }
        } header: {
            Text("DeepSeek model")
        } footer: {
            Text("AuGenda verifies this ID against DeepSeek's models endpoint before task content is sent.")
        }
    }

    private var appleFoundationInfoSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                Text("On-device model. No API key, no setup. Default engine.")
                    .font(.subheadline)
            }

            HStack {
                Label("Siri AI Delegation", systemImage: "waveform")
                Spacer()
                Text("Active via App Intents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !localOnlyMode {
                Toggle(isOn: $enableBackupFallback) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ChatGPT (OpenAI) Backup").fontWeight(.medium)
                        Text("Automatic cloud fallback if on-device model trips guardrails or is busy.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(Color.appAccent)
            }

            Button {
                startTest(for: .appleFoundation)
            } label: {
                HStack(spacing: 8) {
                    switch testState {
                    case .idle:    Image(systemName: "play.circle"); Text("Test on-device model")
                    case .running: ProgressView().controlSize(.small); Text("Testing…")
                    case .ok:      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("Working")
                    case .failed(let m): Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange); Text(m).lineLimit(2)
                    }
                }
            }
        } header: {
            Text("Apple Foundation Models (macOS 27)")
        } footer: {
            Text("Requires Apple Intelligence to be enabled on this device. Siri AI can trigger task actions through native App Intents. ChatGPT backup provides optional cloud fallback when configured.")
        }
    }

    private var behaviorSection: some View {
        Section {
            Toggle(isOn: $autoEnrich) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-enrich new tasks").fontWeight(.medium)
                    Text("Run enrichment automatically when you save a new task.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(Color.appAccent)

            Toggle(isOn: $showEnrichButtons) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show \"Enrich\" button").fontWeight(.medium)
                    Text("Adds a per-task Enrich button to the editor.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(Color.appAccent)
        } header: {
            Text("Behavior")
        }
    }

    private var usageSection: some View {
        Section {
            if !ledger.persistenceIsHealthy {
                Label(
                    "Usage history could not be trusted. A configured spend cap is paused until you clear usage history and recovery succeeds.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(Tokens.Color.warning)
            }
            HStack {
                Text("Tokens this month")
                Spacer()
                Text("\(ledger.thisMonthTokens)")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            HStack {
                Text("Estimated cost")
                Spacer()
                Text(String(format: "$%.4f", ledger.thisMonthCostUSD))
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            HStack {
                Text("Monthly budget")
                Spacer()
                Picker("", selection: $maxMonthlyCostUSD) {
                    Text("Unlimited").tag(0.0)
                    Text("$5").tag(5.0)
                    Text("$10").tag(10.0)
                    Text("$20").tag(20.0)
                    Text("$50").tag(50.0)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 140)
            }
            if maxMonthlyCostUSD > 0 {
                HStack {
                    Text("Remaining")
                    Spacer()
                    Text(String(format: "$%.4f", max(0, maxMonthlyCostUSD - ledger.thisMonthCostUSD)))
                        .foregroundStyle(
                            ledger.thisMonthCostUSD >= maxMonthlyCostUSD
                                ? Tokens.Color.warning
                                : .secondary
                        )
                        .monospacedDigit()
                }
            }
            Button(role: .destructive) {
                usagePersistenceError = ledger.clear()
                    ? nil
                    : "Usage history could not be fully cleared. Try again before using a spend cap."
            } label: {
                Label("Clear usage history", systemImage: "trash")
            }
            if let usagePersistenceError {
                Text(usagePersistenceError)
                    .font(.caption)
                    .foregroundStyle(Tokens.Color.warning)
            }
        } header: {
            Text("Usage")
        } footer: {
            Text("Estimates use published list prices and provider-reported token counts. Apple Foundation and Ollama are free. If usage cannot be read or written, a configured spend cap fails closed.")
        }
    }

    private var footerLegalSection: some View {
        Section {
            Text("Per-task: open any task and set 'Exclude from AI' to hide it from enrichment.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Google Sign-In

    private var googleSignInSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(googleSignedIn ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        googleSignedIn
                            ? (GoogleOAuth.isConfigured
                                ? "Signed in with Google"
                                : "Google authorization stored")
                            : "Not signed in"
                    )
                        .font(.subheadline).fontWeight(.medium)
                    Text(
                        googleSignedIn
                            ? (GoogleOAuth.isConfigured
                                ? "Gemini calls are made on your Google account."
                                : "This build's OAuth configuration is invalid, but you can still remove the stored local token.")
                            : "Sign in to use your Google account quota instead of an API key."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if googleSignedIn {
                Button(role: .destructive) {
                    let removed = OAuthCoordinator.shared.signOut(provider: .gemini)
                    if removed {
                        googleSignedIn = false
                    }
                    googleAuthError = removed
                        ? nil
                        : "Couldn't remove the local Google token. Try signing out again."
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                Button {
                    Task { await signInWithGoogle() }
                } label: {
                    HStack(spacing: 8) {
                        if googleSigningIn {
                            ProgressView().controlSize(.small)
                            Text("Signing in…")
                        } else {
                            Image(systemName: "g.circle.fill")
                            Text("Sign in with Google")
                        }
                    }
                }
                .disabled(googleSigningIn || !GoogleOAuth.isConfigured)
            }

            if let err = googleAuthError {
                Text(err)
                    .font(.caption).foregroundStyle(.orange)
            }

            if !GoogleOAuth.isConfigured {
                Text("Google OAuth is not configured for this build. The API-key path below still works.")
                    .font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Google account")
        } footer: {
            Text("OAuth authorizes only the configured Generative Language API scope. It does not grant AuGenda access to Gmail, Drive, Calendar, or other Google data. Tokens are stored in this device's Keychain and are not synced. Sign out removes only the local token; revoke AuGenda's grant separately in Google Account → Security → Third-party access.")
        }
    }

    private func signInWithGoogle() async {
        googleSigningIn = true
        googleAuthError = nil
        defer { googleSigningIn = false }
        do {
            _ = try await GoogleOAuth.authorize()
            googleSignedIn = true
        } catch let error as OAuthError {
            googleAuthError = error.errorDescription
        } catch {
            googleAuthError = "Unexpected error during sign-in."
        }
    }

    // MARK: - Subscription disclosure (Claude / OpenAI)

    @ViewBuilder
    private func subscriptionDisclosureSection(for provider: AIProvider) -> some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(disclosureTitle(for: provider))
                        .font(.subheadline).fontWeight(.medium)
                    Text(disclosureBody(for: provider))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let url = consoleURL(for: provider) {
                Link(destination: url) {
                    Label("Open \(provider.displayName) console", systemImage: "arrow.up.right.square")
                }
            }
        } header: {
            Text("Why no \"Sign in with \(provider.displayName)\"?")
        }
    }

    private func disclosureTitle(for provider: AIProvider) -> String {
        switch provider {
        case .claude:  return "Claude Pro / Max ≠ API access"
        case .openai:  return "ChatGPT Plus / Pro ≠ API access"
        default:       return "Sign-in not available"
        }
    }

    private func disclosureBody(for provider: AIProvider) -> String {
        switch provider {
        case .claude:
            return "Your Claude.ai subscription pays for the Claude.ai web/desktop apps. It does not include API quota and there's no third-party OAuth flow. To use Claude in AuGenda, get an API key from console.anthropic.com (separate billing)."
        case .openai:
            return "Your ChatGPT subscription pays for the ChatGPT web/desktop/mobile apps. It does not include API quota and there's no third-party OAuth flow. To use ChatGPT in AuGenda, get an API key from platform.openai.com (separate billing)."
        default:
            return "This provider doesn't expose a third-party sign-in flow. Use the API key above."
        }
    }

    private func consoleURL(for provider: AIProvider) -> URL? {
        switch provider {
        case .claude:    return URL(string: "https://console.anthropic.com/")
        case .openai:    return URL(string: "https://platform.openai.com/api-keys")
        case .gemini:    return URL(string: "https://aistudio.google.com/apikey")
        case .deepseek:  return URL(string: "https://platform.deepseek.com/api_keys")
        case .mistral:   return URL(string: "https://console.mistral.ai/api-keys/")
        case .perplexity:return URL(string: "https://www.perplexity.ai/settings/api")
        case .grok:      return URL(string: "https://console.x.ai/")
        default:         return nil
        }
    }

    // MARK: - Personalization

    private var personalizationSection: some View {
        Section {
            if !personalization.persistenceIsHealthy {
                Label(
                    "Stored AI memory could not be trusted. It will not be overwritten until you clear memory or reset personalization successfully.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(Tokens.Color.warning)
            }
            // About-me note
            VStack(alignment: .leading, spacing: 6) {
                Text("About you")
                    .font(.subheadline).fontWeight(.medium)
                TextEditor(text: $personalization.aboutMe)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topLeading) {
                        if personalization.aboutMe.isEmpty {
                            Text("e.g. \"AuDHD, sensory-sensitive to fluorescent light, mornings are best for focus, dread phone calls but fine with email.\"")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                Text("Sent on every enrichment so the AI has context about you — without needing a real account login.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            // Tone picker
            Picker("Tone", selection: $personalization.tone) {
                ForEach(PersonalizationTone.allCases) { t in
                    Text(t.displayName).tag(t)
                }
            }

            // Interest inference toggle
            Toggle(isOn: $personalization.allowInterestInference) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let AI estimate interest level")
                        .fontWeight(.medium)
                    Text(personalization.allowInterestInference
                         ? "On — AI proposes interest based on your About-you note and history."
                         : "Off — interest stays private; AI never guesses it.")
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(Color.appAccent)

            // Memory layer
            Toggle(isOn: $personalization.memoryEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send recent enrichment history").fontWeight(.medium)
                    Text("Last \(personalization.memoryDepth) tasks shared so the AI sees patterns over time.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(Color.appAccent)

            if personalization.memoryEnabled {
                Stepper(value: $personalization.memoryDepth, in: 1...20) {
                    Text("Memory depth: \(personalization.memoryDepth)")
                }
                HStack {
                    Text("Currently remembered")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(personalization.memory.count)")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Button(role: .destructive) {
                    personalizationPersistenceError = personalization.clearMemory()
                        ? nil
                        : "Recent AI memory could not be fully cleared. Try again."
                } label: {
                    Label("Clear memory", systemImage: "eraser")
                }
            }

            Button(role: .destructive) {
                personalizationPersistenceError = personalization.resetAll()
                    ? nil
                    : "Personalization could not be fully reset. Try again."
            } label: {
                Label("Reset personalization", systemImage: "arrow.counterclockwise")
            }
            if let personalizationPersistenceError {
                Text(personalizationPersistenceError)
                    .font(.caption)
                    .foregroundStyle(Tokens.Color.warning)
            }
        } header: {
            Text("Personalization")
        } footer: {
            Text("Personalization is stored on this device. When enabled, it is included in enrichment input: Apple processes it on device, Ollama sends it to your configured host, and cloud providers receive it under their own terms. Reset removes the local copy.")
        }
    }

    // MARK: - Actions

    private func promptForStaleConsentIfNeeded() {
        guard aiEnabled,
              let provider = activeProvider,
              !AIConsentPolicy.hasCurrentConsent(for: provider) else {
            return
        }
        pendingProvider = provider
        showDisclosure = true
    }

    private func syncKeyState() {
        guard let provider = activeProvider else {
            apiKeyExists = false
            return
        }
        apiKeyExists = KeychainStore.hasKey(for: provider)
        apiKeyDraft = ""
    }

    private func saveKey(for provider: AIProvider) {
        do {
            try KeychainStore.set(apiKeyDraft, for: provider)
            apiKeyDraft = ""
            apiKeyExists = KeychainStore.hasKey(for: provider)
            testState = .idle
        } catch {
            testState = .failed(message: "Couldn't save key")
        }
    }

    private func removeKey(for provider: AIProvider) {
        do {
            try KeychainStore.remove(for: provider)
            apiKeyExists = false
            testState = .idle
        } catch {
            testState = .failed(message: "Couldn't remove key")
        }
    }

    private func startTest(for provider: AIProvider) {
        testTask?.cancel()
        testTask = Task {
            await runTest(for: provider)
        }
    }

    private func runTest(for provider: AIProvider) async {
        testState = .running
        guard let enricher = AIEnricherRegistry.enricher(for: provider) else {
            testState = .failed(message: "No adapter")
            return
        }
        let available = await enricher.isAvailable()
        guard !Task.isCancelled else {
            testState = .idle
            return
        }
        if provider == .gemini {
            googleSignedIn = GoogleOAuth.hasLocalSession
        }
        if available {
            testState = .ok
        } else {
            if provider == .deepseek,
               DeepSeekEnricher.configuredModel(from: deepSeekModel) == nil {
                testState = .failed(message: "Model required")
            } else {
                testState = .failed(message: "Couldn’t authenticate or connect")
            }
        }
    }

    // MARK: - Local state

    private enum TestState: Equatable {
        case idle
        case running
        case ok
        case failed(message: String)
    }
}

#Preview {
    NavigationStack {
        AIEnrichmentSettingsView()
    }
}
