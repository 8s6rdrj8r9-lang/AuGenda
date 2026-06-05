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

    // Active provider (rawValue). Empty until the user picks one.
    @AppStorage("ai.activeProvider") private var activeProviderRaw: String = ""

    // Auto-enrich new tasks on save. OFF by default even after AI enabled.
    @AppStorage("ai.autoEnrichNewTasks") private var autoEnrich: Bool = false

    // Whether the per-task "Enrich" button is shown anywhere. ON by default
    // once AI is enabled — gives the user manual triggers without auto.
    @AppStorage("ai.showEnrichButtons") private var showEnrichButtons: Bool = true

    // Soft cap (USD per month) — surfaces a banner, doesn't hard-stop.
    @AppStorage("ai.softCapUSD") private var softCapUSD: Double = 5.0

    // Ollama-specific config (only used if Ollama is the active provider).
    @AppStorage("ai.ollama.host")  private var ollamaHost: String = "http://localhost:11434"
    @AppStorage("ai.ollama.model") private var ollamaModel: String = "llama3.1:8b"

    // Local UI state
    @State private var apiKeyDraft: String = ""
    @State private var apiKeyExists: Bool = false
    @State private var testState: TestState = .idle
    @State private var showAdvancedProviders: Bool = false
    @State private var pendingProvider: AIProvider? = nil  // disclosure prompt
    @State private var showDisclosure: Bool = false

    @StateObject private var ledger = AIUsageLedger.shared
    @StateObject private var personalization = PersonalizationStore.shared

    // Google OAuth UI state — separate from the generic test-state so the
    // sign-in button can update independently of the test button.
    @State private var googleSigningIn: Bool = false
    @State private var googleAuthError: String? = nil

    private var activeProvider: AIProvider? {
        AIProvider(rawValue: activeProviderRaw)
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
        .onAppear { syncKeyState() }
        .onChange(of: activeProviderRaw) { _, _ in syncKeyState(); testState = .idle }
        .alert(
            "Confirm provider",
            isPresented: $showDisclosure,
            presenting: pendingProvider
        ) { provider in
            Button("Use \(provider.displayName)") {
                activeProviderRaw = provider.rawValue
            }
            Button("Cancel", role: .cancel) {
                pendingProvider = nil
            }
        } message: { provider in
            Text(provider.consentDisclosure)
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
        } footer: {
            Text("AI enrichment auto-fills task metadata (difficulty axes, sub-tasks, time estimate) from your task title. Off by default. Even after enabling, no data leaves your device until you pick a provider AND enrich a task.")
        }
    }

    private var providerPickerSection: some View {
        Section {
            // Primary providers
            ForEach(AIProvider.allCases.filter { !$0.isAdvanced }) { provider in
                providerRow(provider)
            }

            // Advanced disclosure
            DisclosureGroup(isExpanded: $showAdvancedProviders) {
                ForEach(AIProvider.allCases.filter(\.isAdvanced)) { provider in
                    providerRow(provider)
                }
            } label: {
                HStack {
                    Text("Advanced providers").foregroundStyle(.secondary)
                    Spacer()
                }
            }
        } header: {
            Text("Provider")
        } footer: {
            Text("On-device and self-hosted providers never send your task data to a third-party cloud. Cloud providers require an API key, which is stored in the Keychain on this device only.")
        }
    }

    private func providerRow(_ provider: AIProvider) -> some View {
        Button {
            // If different provider, show disclosure first.
            if provider.rawValue != activeProviderRaw {
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
                Task { await runTest(for: provider) }
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
            .disabled(!apiKeyExists)
        } header: {
            Text("API key")
        } footer: {
            Text("Your key is stored in the device Keychain. It is not synced to iCloud, and not visible to anyone else with access to your Apple ID. Remove it any time.")
        }
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
                Task { await runTest(for: .ollama) }
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
            Text("Point this at your Ollama server. On a Mac running Ollama locally, use http://localhost:11434. From an iPhone on the same Wi-Fi, use http://<mac-name>.local:11434.")
        }
    }

    private var appleFoundationInfoSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                Text("On-device model. No API key, no setup.")
                    .font(.subheadline)
            }
            Button {
                Task { await runTest(for: .appleFoundation) }
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
            Text("Apple Foundation Models")
        } footer: {
            Text("Requires Apple Intelligence to be enabled on this device. Supported devices: iPhone 15 Pro and later, Apple silicon Macs, Apple Watch Series 10 and later.")
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
                Text("Soft cap warning")
                Spacer()
                Stepper(value: $softCapUSD, in: 0.5...50, step: 0.5) {
                    Text(String(format: "$%.1f/mo", softCapUSD))
                        .foregroundStyle(.secondary)
                }
            }
            Button(role: .destructive) {
                ledger.clear()
            } label: {
                Label("Clear usage history", systemImage: "trash")
            }
        } header: {
            Text("Usage")
        } footer: {
            Text("Estimates use published list prices. Apple Foundation and Ollama are free; cloud usage is rounded up.")
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
                    .foregroundStyle(GoogleOAuth.isSignedIn ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(GoogleOAuth.isSignedIn ? "Signed in with Google" : "Not signed in")
                        .font(.subheadline).fontWeight(.medium)
                    Text(GoogleOAuth.isSignedIn
                         ? "Gemini calls are made on your Google account."
                         : "Sign in to use your Google account quota instead of an API key.")
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if GoogleOAuth.isSignedIn {
                Button(role: .destructive) {
                    OAuthCoordinator.shared.signOut(provider: .gemini)
                    // Trigger re-render
                    googleAuthError = nil
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
                Text("⚠️ Google OAuth client not configured for this build. See GoogleOAuth.swift TestFlight checklist. The API-key path below still works.")
                    .font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Google account")
        } footer: {
            Text("OAuth signs Gemini calls with your Google account, so usage counts against your account's quota and the AI can be (in future) connected to your other Google data. Tokens are stored in your device Keychain — not synced.")
        }
    }

    private func signInWithGoogle() async {
        googleSigningIn = true
        googleAuthError = nil
        defer { googleSigningIn = false }
        do {
            _ = try await OAuthCoordinator.shared.authorize(config: GoogleOAuth.providerConfig)
            // Successful — keychain has tokens. View re-renders via state.
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
                    personalization.clearMemory()
                } label: {
                    Label("Clear memory", systemImage: "eraser")
                }
            }

            Button(role: .destructive) {
                personalization.resetAll()
            } label: {
                Label("Reset personalization", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Personalization")
        } footer: {
            Text("Personalization data lives on this device only. About-you text, tone, and memory are sent to your active AI provider on each enrichment call, never to Apple or anyone else. Erasing personalization here removes it from this device.")
        }
    }

    // MARK: - Actions

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

    private func runTest(for provider: AIProvider) async {
        testState = .running
        guard let enricher = AIEnricherRegistry.enricher(for: provider) else {
            testState = .failed(message: "No adapter")
            return
        }
        let available = await enricher.isAvailable()
        if available {
            testState = .ok
        } else {
            testState = .failed(message: provider.requiresAPIKey ? "Not configured" : "Not available")
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
