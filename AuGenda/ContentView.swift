// ContentView.swift
// AUDHD Agenda App

import SwiftUI
import SwiftData
import Combine

// MARK: - NDCopy
// Resolves UI copy strings based on the active profile's task language style.
// Keeps PDA-mode language changes centralised rather than scattered across views.

struct NDCopy {
    let style: TaskLanguageStyle

    var addItemTitle: String {
        switch style {
        case .choiceOnly: return "You could add something…"
        case .simple:     return "Add task"
        case .standard:   return "New item"
        }
    }

    var emptyStateMessage: String {
        switch style {
        case .choiceOnly: return "Nothing needs doing right now."
        case .simple:     return "Nothing today"
        case .standard:   return "Nothing scheduled today"
        }
    }

    var frictionPrompt: String {
        switch style {
        case .choiceOnly: return "How does this feel?"
        case .simple:     return "How hard?"
        case .standard:   return "Friction level"
        }
    }

    static func from(_ profileManager: ActiveProfileManager) -> NDCopy {
        NDCopy(style: profileManager.activePreferences?.taskLanguageStyle ?? .standard)
    }
}

// MARK: - Root App View

struct ContentView: View {

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationManager: NotificationManager
    #if canImport(WatchConnectivity)
    @EnvironmentObject private var watchManager: WatchConnectivityManager
    #endif
    @EnvironmentObject private var blockManager: BlockManager
    @EnvironmentObject private var profileManager: ActiveProfileManager

    @State private var selectedTab: AppTab = .today

    /// Routes the .today tab to the new HomeDashboardView (the five-zone
    /// adaptive surface). Default ON as of Session 7. Users can switch
    /// back to the legacy TodayView via Settings → Experiments.
    @AppStorage("home.dashboard.useNewHome") private var useNewHomeDashboard: Bool = true

    // Onboarding is now sequenced from RootView (see AuGendaApp.swift) so the
    // three first-launch sheets — ProfileSetup → CognitiveStateSelector →
    // OnboardingView — fire serially via a single .sheet(item:) routed by a
    // FirstLaunchStep enum. Removed from ContentView to avoid sheet-binding
    // races that were skipping the capacity selector.

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground
                .ignoresSafeArea()

            ErrorBanner()

            TabView(selection: $selectedTab) {

                Group {
                    if useNewHomeDashboard {
                        HomeDashboardView()
                    } else {
                        TodayView()
                    }
                }
                    .tabItem {
                        Label("Today", systemImage: "calendar.day.timeline.left")
                    }
                    .tag(AppTab.today)

                BlockListView()
                    .tabItem {
                        Label("Blocks", systemImage: "square.grid.2x2.fill")
                    }
                    .tag(AppTab.blocks)

                TaskBacklogView()
                    .tabItem {
                        Label("Tasks", systemImage: "checklist")
                    }
                    .tag(AppTab.tasks)

                FocusView()
                    .tabItem {
                        Label("Focus", systemImage: "timer")
                    }
                    .tag(AppTab.focus)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                    .tag(AppTab.settings)
            }
            .tint(Color.appAccent)
        }
        .environment(\.appFont, profileManager.activeFont)
        // Root-level density injection — the single source for every
        // @Environment(\.densityMode) reader in the tree (e.g. PrimaryAgendaCard,
        // MomentumTaskCard in AuDHDNDComponents), not just Home's subtree.
        // Reading effectiveDensity here establishes SwiftData @Observable
        // tracking on densityPinnedRaw + currentEnergyLevel, so the root
        // re-renders and re-injects when either changes.
        .environment(\.densityMode, profileManager.activePreferences?.effectiveDensity ?? .functional)
        .environment(\.uiScale, profileManager.activePreferences?.uiScale ?? 1.0)
        // No .preferredColorScheme — the app follows the system's
        // light/dark setting. All view-level colours go through the
        // adaptive `Color.app*` helpers (defined in AuDHDComponents.swift)
        // which switch to slate900/white for backgrounds and slate900/
        // slate600 for text on the trait-collection change.
        // The watch keeps its true-black background per spec §10 —
        // that's an OLED-power and design-intent choice, not a system
        // appearance thing.
        .onAppear {
            setupOnLaunch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agendaItemCompleted)) { note in
            handleCompleteAction(note.userInfo)
        }
        .onReceive(NotificationCenter.default.publisher(for: .agendaItemSnoozed)) { note in
            handleSnoozeAction(note.userInfo)
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectTab)) { note in
            guard let index = note.userInfo?["index"] as? Int else { return }
            let tabs: [AppTab] = [.today, .blocks, .tasks, .focus, .settings]
            if tabs.indices.contains(index) { selectedTab = tabs[index] }
        }
    }

    // MARK: - Launch setup

    private func setupOnLaunch() {
        #if canImport(WatchConnectivity)
        watchManager.modelContext = modelContext
        watchManager.sendSyncSnapshot()
        #endif
        Swift.Task {
            await notificationManager.requestAuthorization()
        }
    }

    // MARK: - Notification action handlers

    private func handleCompleteAction(_ userInfo: [AnyHashable: Any]?) {
        guard let idString = userInfo?["clientID"] as? String,
              let uuid = UUID(uuidString: idString)
        else { return }

        let descriptor = FetchDescriptor<AgendaItem>(
            predicate: #Predicate { $0.clientID == uuid }
        )
        guard let item = (try? modelContext.fetch(descriptor))?.first else { return }
        ActivityLog.recordCompletion()
        item.isComplete = true
        item.completedAt = .now
        item.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
        }
        #if canImport(WatchConnectivity)
        watchManager.sendSyncSnapshot()
        #endif
    }

    private func handleSnoozeAction(_ userInfo: [AnyHashable: Any]?) {
        guard let idString = userInfo?["clientID"] as? String,
              let uuid = UUID(uuidString: idString),
              let minutes = userInfo?["minutes"] as? Int
        else { return }

        let descriptor = FetchDescriptor<AgendaItem>(
            predicate: #Predicate { $0.clientID == uuid }
        )
        guard let item = (try? modelContext.fetch(descriptor))?.first else { return }
        ActivityLog.recordSnooze()
        notificationManager.snooze(item: item, minutes: minutes)
        item.snoozedUntil = Date.now.addingTimeInterval(Double(minutes) * 60)
        item.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
        }
        #if canImport(WatchConnectivity)
        watchManager.sendSyncSnapshot()
        #endif
    }
}

// MARK: - App Tab

enum AppTab: Hashable {
    case today, blocks, tasks, focus, settings
}

// MARK: - Today View

struct TodayView: View {

    @EnvironmentObject private var profileManager: ActiveProfileManager

    @Query(
        filter: #Predicate<AgendaItem> { !$0.isComplete },
        sort: \AgendaItem.scheduledDate
    )
    private var agendaItems: [AgendaItem]

    @State private var showAddItem = false
    @State private var showEnergyCheck = false
    @State private var showHousehold = false

    // MARK: Computed

    private var activeProfile: Profile? { profileManager.activeProfile }
    private var activeProfileID: UUID? { profileManager.activeProfile?.clientID }
    private var activePrefs: ProfilePreferences? { profileManager.activePreferences }

    private var lowEFMode: Bool {
        guard activePrefs?.energyTrackingEnabled == true else { return false }
        return (activePrefs?.currentEnergyLevel ?? 3) <= 2
    }

    private var visibleItems: [AgendaItem] {
        let now = Date.now
        let endOfDay = Calendar.current.endOfDay(for: now)
        let maxFriction = activePrefs?.lowEFMaxFriction ?? 2

        return agendaItems.filter { item in
            // Snoozed items hidden
            if let snoozedUntil = item.snoozedUntil, snoozedUntil > now { return false }
            // Must be today
            guard item.scheduledDate <= endOfDay else { return false }
            // Low EF: only surface tasks at or below threshold
            if lowEFMode, item.frictionLevel > maxFriction { return false }
            // Assignment filter: show items for active profile or unassigned legacy items
            if let assignedID = item.assignedToProfileID {
                return assignedID == activeProfileID
            }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    EnergyBannerView()
                        .padding(.horizontal)
                        .padding(.top, 8)

                    if lowEFMode {
                        LowEFModeHeader(frictionLabel: activePrefs?.frictionLabel ?? .friction)
                            .padding(.horizontal)
                            .padding(.top, 12)
                    }

                    // Child profiles get a simplified card layout
                    Group {
                        if activeProfile?.role == .child {
                            ChildAgendaList(items: visibleItems)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(visibleItems) { item in
                                    AgendaItemRowView(item: item)
                                        .padding(.horizontal)
                                }
                                if visibleItems.isEmpty {
                                    EmptyAgendaView(copy: NDCopy.from(profileManager))
                                        .padding(.top, 40)
                                }
                            }
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Today")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: {
                    #if os(iOS)
                    return .navigationBarLeading
                    #else
                    return .automatic
                    #endif
                }()) {
                    ProfileQuickSwitchButton()
                }
                ToolbarItem(placement: {
                    #if os(iOS)
                    return .navigationBarTrailing
                    #else
                    return .primaryAction
                    #endif
                }()) {
                    HStack(spacing: 4) {
                        // Household overview — coordinator only
                        if activeProfile?.role == .coordinator {
                            Button { showHousehold = true } label: {
                                Image(systemName: "person.3.fill")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                        // Add item — hidden for child profiles
                        if activeProfile?.role != .child {
                            Button { showAddItem = true } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddItem) {
                AddAgendaItemView(isPresented: $showAddItem)
                    .presentationDetents([.large])
            #if os(iOS)
            .presentationDragIndicator(.visible)
            #endif
            }
            .navigationDestination(isPresented: $showHousehold) {
                HouseholdOverviewView()
            }
            .sheet(isPresented: $showEnergyCheck) {
                EnergyCheckView(isPresented: $showEnergyCheck)
                    .presentationDetents([.medium])
            #if os(iOS)
            .presentationDragIndicator(.visible)
            #endif
            }
        }
        // Prompt energy check-in once per launch if tracking is on
        .onAppear {
            if activePrefs?.energyTrackingEnabled == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showEnergyCheck = true
                }
            }
        }
        .onChange(of: profileManager.activeProfile?.clientID) {
            // Re-prompt when switching profiles within the same session
            if activePrefs?.energyTrackingEnabled == true {
                showEnergyCheck = true
            }
        }
    }
}

// MARK: - Agenda Item Row

struct AgendaItemRowView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appFont) private var appFont
    @EnvironmentObject private var notificationManager: NotificationManager
    @Query(sort: \Profile.sortOrder) private var allProfiles: [Profile]
    #if canImport(WatchConnectivity)
    @EnvironmentObject private var watchManager: WatchConnectivityManager
    #endif

    let item: AgendaItem

    @State private var showSnoozeMenu: Bool = false

    /// Profile that assigned this item to the current user (nil = self-assigned)
    private var assignedByProfile: Profile? {
        guard let id = item.assignedByProfileID else { return nil }
        return allProfiles.first { $0.clientID == id }
    }

    var body: some View {
        HStack(spacing: 14) {

            Button {
                completeItem()
            } label: {
                Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isComplete ? Color.appAccent : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.app(.body, scheme: appFont))
                    .fontWeight(.medium)
                    .foregroundStyle(item.isComplete ? .secondary : .primary)
                    .strikethrough(item.isComplete)

                HStack(spacing: 8) {
                    Text(item.scheduledDate.formatted(.dateTime.hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    FrictionDots(level: item.frictionLevel)

                    if !item.contextTag.isEmpty {
                        Text(item.contextTag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.secondary)
                    }

                    // Attribution: show assigner's avatar + name when assigned by someone else
                    if let assigner = assignedByProfile {
                        HStack(spacing: 4) {
                            ProfileAvatarView(profile: assigner, size: 14)
                            Text("from \(assigner.name)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            Button {
                showSnoozeMenu = true
            } label: {
                Image(systemName: "zzz")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .confirmationDialog("Snooze for…", isPresented: $showSnoozeMenu) {
                Button("5 minutes") { snooze(minutes: 5) }
                Button("15 minutes") { snooze(minutes: 15) }
                Button("30 minutes") { snooze(minutes: 30) }
                Button("Cancel", role: .cancel) {}
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(priorityColor.opacity(0.4), lineWidth: item.priority >= 2 ? 1.5 : 0)
        )
    }

    private var priorityColor: Color {
        switch item.priority {
        case 2: return .red
        case 1: return .orange
        default: return .clear
        }
    }

    private func completeItem() {
        ActivityLog.recordCompletion()
        withAnimation(.spring(duration: 0.3)) {
            item.isComplete = true
            item.completedAt = .now
            item.updatedAt = .now
        }
        notificationManager.cancelNotifications(for: item)
        do {
            try modelContext.save()
        } catch {
            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
        }
        #if canImport(WatchConnectivity)
        watchManager.sendSyncSnapshot()
        #endif
    }

    private func snooze(minutes: Int) {
        ActivityLog.recordSnooze()
        notificationManager.snooze(item: item, minutes: minutes)
        item.snoozedUntil = Date.now.addingTimeInterval(Double(minutes) * 60)
        item.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
        }
        #if canImport(WatchConnectivity)
        watchManager.sendSyncSnapshot()
        #endif
    }
}

// MARK: - Friction Dots

struct FrictionDots: View {
    let level: Int  // 1–5: how hard starting feels (1 = effortless, 5 = very hard)

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { dot in
                Circle()
                    .fill(dot <= level ? frictionColor : Color.appBorder.opacity(0.5))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityLabel("Friction \(level) of 5")
    }

    private var frictionColor: Color {
        switch level {
        case 1, 2: return Tokens.Color.success   // easy: green
        case 3:    return Tokens.Color.info       // medium: blue
        case 4:    return Tokens.Color.warning    // hard: amber
        default:   return Tokens.Color.warning    // very hard: amber (not red)
        }
    }
}

// MARK: - Energy Banner

struct EnergyBannerView: View {

    @EnvironmentObject private var profileManager: ActiveProfileManager
    @Environment(\.modelContext) private var modelContext
    @State private var showCheck = false

    private var prefs: ProfilePreferences? { profileManager.activePreferences }
    private var level: Int { prefs?.currentEnergyLevel ?? 3 }

    var body: some View {
        Button { showCheck = true } label: {
            HStack {
                Image(systemName: energyIcon)
                    .foregroundStyle(energyColor)
                Text(energyLabel)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(energyColor)
                Spacer()
                Text("tap to update")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(energyColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showCheck) {
            EnergyCheckView(isPresented: $showCheck)
                .presentationDetents([.medium])
            #if os(iOS)
            .presentationDragIndicator(.visible)
            #endif
        }
    }

    private var energyIcon: String {
        switch level {
        case 1: return "battery.0percent"
        case 2: return "battery.25percent"
        case 3: return "battery.50percent"
        case 4: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var energyLabel: String {
        switch level {
        case 1: return "Survival mode"
        case 2: return "Low energy"
        case 3: return "Moderate"
        case 4: return "Good"
        default: return "High functioning"
        }
    }

    private var energyColor: Color {
        switch level {
        case 1, 2: return .orange
        case 3: return .yellow
        default: return .green
        }
    }
}

// MARK: - Low EF Mode Header

struct LowEFModeHeader: View {
    var frictionLabel: FrictionLabel = .friction

    var body: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(.orange)
            Text("Low EF mode — showing low-\(frictionLabel.rawValue) tasks only")
                .font(.caption)
                .foregroundStyle(.orange)
            Spacer()
        }
        .padding(10)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Energy Check View

struct EnergyCheckView: View {

    @Binding var isPresented: Bool
    @EnvironmentObject private var profileManager: ActiveProfileManager
    @Environment(\.modelContext) private var modelContext

    private var prefs: ProfilePreferences? { profileManager.activePreferences }

    var body: some View {
        VStack(spacing: Tokens.Spacing.lg) {
            if let profile = profileManager.activeProfile {
                HStack(spacing: Tokens.Spacing.sm) {
                    ProfileAvatarView(profile: profile, size: 28)
                    Text("How's your energy, \(profile.name)?")
                        .font(Tokens.Typography.h2)
                }
                .padding(.top, Tokens.Spacing.lg)
            } else {
                Text("How's your energy right now?")
                    .font(Tokens.Typography.h2)
                    .padding(.top, Tokens.Spacing.lg)
            }

            // Honesty: the energy→surface claim is only true when nothing is
            // pinned. Under a pin, say so plainly and offer the one inline way
            // out (Unpin → the existing densityPinned clear path).
            if let pinned = prefs?.densityPinned {
                VStack(spacing: Tokens.Spacing.sm) {
                    Text("Capacity is pinned to \(pinned.label) — energy is recorded but won't change the view.")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Unpin") { clearPin() }
                        .font(Tokens.Typography.label)
                        .foregroundStyle(Color.appAccent)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, Tokens.Spacing.base)
            } else {
                Text("This adjusts what gets surfaced today.")
                    .font(Tokens.Typography.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: Tokens.Spacing.sm) {
                ForEach(EnergyLevel.allCases) { level in
                    Button {
                        setEnergy(level.rawValue)
                    } label: {
                        HStack {
                            Text(level.emoji)
                            Text(level.label)
                                .font(Tokens.Typography.body)
                                .fontWeight(.medium)
                            Spacer()
                            if prefs?.currentEnergyLevel == level.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                        .padding(Tokens.Spacing.base)
                        .background(
                            prefs?.currentEnergyLevel == level.rawValue
                                ? Color.appAccent.opacity(0.15)
                                : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: Tokens.Border.radiusMedium)
                        )
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Tokens.Spacing.base)

            Button("Done") { isPresented = false }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)
                .padding(.bottom, Tokens.Spacing.base)
        }
        .padding(.horizontal, Tokens.Spacing.base)
    }

    private func setEnergy(_ level: Int) {
        guard let prefs else { return }
        prefs.currentEnergyLevel = level
        prefs.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
        }
        // Record so the OrientationAnchor's stale-energy hint can clear.
        EnergyCheckInTracker.record()
    }

    /// Clear an explicit pin so energy resumes driving the view — the same
    /// clear path the density picker's "Auto" uses (densityPinned = nil).
    private func clearPin() {
        guard let prefs else { return }
        prefs.densityPinned = nil
        do {
            try modelContext.save()
        } catch {
            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
        }
    }
}

enum EnergyLevel: Int, CaseIterable, Identifiable {
    case survival = 1, low = 2, moderate = 3, good = 4, high = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .survival: return "Survival mode"
        case .low: return "Low — keep it simple"
        case .moderate: return "Moderate"
        case .good: return "Good"
        case .high: return "High functioning"
        }
    }

    var emoji: String {
        switch self {
        case .survival: return "🪫"
        case .low: return "🔋"
        case .moderate: return "⚡️"
        case .good: return "✨"
        case .high: return "🚀"
        }
    }
}

// MARK: - Focus View

struct FocusView: View {

    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var profileManager: ActiveProfileManager

    private var activePrefs: ProfilePreferences? { profileManager.activePreferences }
    private var duration: Int { activePrefs?.focusSessionMinutes ?? 25 }
    private var hyperfocusGuard: Bool { activePrefs?.hyperfocusGuard ?? false }

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                if notificationManager.focusSessionActive,
                   let endsAt = notificationManager.focusSessionEndsAt {
                    VStack(spacing: 12) {
                        Text("Focus session active")
                            .font(.headline)
                        Text("Ends \(endsAt.formatted(.relative(presentation: .named)))")
                            .foregroundStyle(.secondary)
                        if hyperfocusGuard {
                            Label("Hyperfocus guard on", systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Button("End Session") {
                            notificationManager.endFocusSession()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                } else {
                    VStack(spacing: 16) {
                        Text("Start a focus session")
                            .font(.headline)
                        Button("Start \(duration) min session") {
                            notificationManager.startFocusSession(durationMinutes: duration)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appAccent)
                        if hyperfocusGuard {
                            Label("Session will end at \(duration) min — no extension", systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
            .navigationTitle("Focus")
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {

    @EnvironmentObject private var profileManager: ActiveProfileManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]
    @State private var showAddProfile = false

    /// Mirrors the same key as ContentView's @AppStorage.
    @AppStorage("home.dashboard.useNewHome") private var useNewHomeDashboard: Bool = true

    // Read-only mirrors of the AI Enrichment keys so the AI row on the
    // main Settings list can show on/off + the active provider's name
    // without navigating in.
    @AppStorage("ai.enabled") private var aiEnrichmentEnabled: Bool = false
    @AppStorage("ai.activeProvider") private var aiActiveProviderRaw: String = ""

    private var activeAIProviderLabel: String {
        AIProvider(rawValue: aiActiveProviderRaw)?.displayName ?? "no provider chosen"
    }

    @State private var showEraseConfirm = false

    /// Toggle binding for notificationPrivacyStrict — lives on the active
    /// profile's preferences, so the value is per-user and syncs via CloudKit.
    private var privateNotificationsBinding: Binding<Bool> {
        Binding(
            get: { profileManager.activePreferences?.notificationPrivacyStrict ?? true },
            set: { newValue in
                profileManager.activePreferences?.notificationPrivacyStrict = newValue
                profileManager.activePreferences?.updatedAt = .now
                do {
                    try modelContext.save()
                } catch {
                    ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Experiments ──
                Section {
                    Toggle(isOn: $useNewHomeDashboard) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Adaptive Home dashboard")
                                .fontWeight(.medium)
                            Text(useNewHomeDashboard ? "On — Today tab uses the five-zone surface." : "Off — Today tab uses the legacy list.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Experiments")
                } footer: {
                    Text("Density adapts to your energy level; pin a capacity mode via the badge on the dashboard. Toggle off to revert to the simpler legacy list.")
                }

                // ── AI Enrichment ──
                // Off by default; navigates into the dedicated settings
                // screen where the user opts in + picks a provider.
                Section {
                    NavigationLink {
                        AIEnrichmentSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.warmEmber)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Enrichment")
                                    .fontWeight(.medium)
                                Text(aiEnrichmentEnabled
                                     ? "On — \(activeAIProviderLabel)"
                                     : "Off — no task data leaves your device")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Assistive")
                } footer: {
                    Text("Auto-fill task metadata (difficulty axes, sub-tasks, time estimates) using on-device or cloud AI. Opt-in, off by default.")
                }

                // ── Focus History ──
                Section {
                    NavigationLink {
                        FocusSessionHistoryView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.bar")
                                .foregroundStyle(Color.appAccent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Focus History")
                                    .fontWeight(.medium)
                                Text("Past sessions and patterns")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("Focus") }

                // ── Privacy ──
                Section {
                    Toggle(isOn: privateNotificationsBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Private notification previews")
                                .fontWeight(.medium)
                            Text("Replace task titles and notes on the lock screen with generic copy.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        showEraseConfirm = true
                    } label: {
                        Label("Erase all data on this device", systemImage: "trash")
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Task content is stored privately in your iCloud account. Notifications fire on this device only and can be redacted for lock-screen safety. Erasing removes local data; if you also want iCloud copies gone, go to Settings → iCloud → Manage Storage → AuGenda.")
                }

                // Profiles section — each row navigates to per-profile settings
                Section {
                    ForEach(profiles) { profile in
                        if let prefs = profile.preferences {
                            NavigationLink {
                                ProfileSettingsView(prefs: prefs, profile: profile)
                            } label: {
                                HStack(spacing: 14) {
                                    ProfileAvatarView(
                                        profile: profile,
                                        size: 40,
                                        showRing: profileManager.activeProfile?.clientID == profile.clientID
                                    )
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(profile.name)
                                                .fontWeight(.medium)
                                            if profileManager.activeProfile?.clientID == profile.clientID {
                                                Text("active")
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(Color.appAccent.opacity(0.15), in: Capsule())
                                                    .foregroundStyle(Color.appAccent)
                                            }
                                        }
                                        Text(profile.role.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        deleteProfiles(at: indexSet)
                    }

                    Button {
                        showAddProfile = true
                    } label: {
                        Label("Add profile", systemImage: "plus.circle")
                            .foregroundStyle(Color.appAccent)
                    }
                } header: {
                    Text("Profiles")
                } footer: {
                    Text("Each profile has its own neurotype settings, font, and preferences. Swipe left to delete.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .confirmationDialog(
                "Erase all data?",
                isPresented: $showEraseConfirm,
                titleVisibility: .visible
            ) {
                Button("Erase everything", role: .destructive) { eraseAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes every task, block, profile, and preference on this device — plus your saved AI API keys, any Google sign-in, and your AI personalization profile. iCloud copies sync back unless you also remove the AuGenda iCloud container in System Settings. This cannot be undone.")
            }
            .sheet(isPresented: $showAddProfile) {
                ProfileSetupView(isPresented: $showAddProfile)
                    .presentationDetents([.large])
            #if os(iOS)
            .presentationDragIndicator(.visible)
            #endif
            }
        }
    }

    // MARK: - Erase

    /// Wipes every SwiftData entity on this device, every secret in the
    /// Keychain (API keys + OAuth tokens), the AI personalization profile
    /// and usage ledger, and every UserDefaults key the app reads or writes,
    /// then re-seeds a fresh default profile so the app boots cleanly.
    /// iCloud copies are NOT touched (CloudKit deletion requires a per-record
    /// loop the user would have to confirm; the footer copy instructs them to
    /// use System Settings).
    private func eraseAllData() {
        // 1. Delete SwiftData entities. @Relationship cascade rules take care
        //    of children, but we list parents explicitly for clarity.
        do {
            try modelContext.delete(model: AgendaItem.self)
            try modelContext.delete(model: AgendaTask.self)
            try modelContext.delete(model: InboxItem.self)
            try modelContext.delete(model: SubTask.self)
            try modelContext.delete(model: TaskStep.self)
            try modelContext.delete(model: Block.self)
            try modelContext.delete(model: BlockTask.self)
            try modelContext.delete(model: BundleTemplate.self)
            try modelContext.delete(model: BundleTemplateItem.self)
            try modelContext.delete(model: AttachedBundle.self)
            try modelContext.delete(model: AttachedBundleItem.self)
            try modelContext.delete(model: ProfilePreferences.self)
            try modelContext.delete(model: Profile.self)
            try modelContext.delete(model: UserPreferences.self)
            try modelContext.delete(model: FocusSession.self)
            try modelContext.delete(model: TaskRelationship.self)
            try modelContext.delete(model: Note.self)
            try modelContext.save()
        } catch {
            ErrorBannerController.shared.show("Could not erase all data: \(error.localizedDescription)")
            return
        }

        // 2. Wipe every secret + AI-derived artefact. "Erase all data" must
        //    leave no credentials or personal profile behind — these never
        //    lived in SwiftData, so step 1 doesn't reach them.
        for provider in AIProvider.allCases {
            try? KeychainStore.remove(for: provider)   // API keys
            OAuthCoordinator.shared.signOut(provider: provider)  // OAuth tokens
        }
        // about-me, tone, interest opt-in, and the on-disk memory JSON
        PersonalizationStore.shared.resetAll()
        // spend history (ai-usage-ledger.json in Application Support)
        AIUsageLedger.shared.clear()

        // 3. Clear every UserDefaults key we use — including AI config.
        let defaults = UserDefaults.standard
        for key in [
            "activity.snoozes", "activity.completions",
            "energy.lastCheckIn",
            "irp.lastItemID", "irp.lastItemTitle",
            "irp.lastActiveDate", "irp.lastContextLabel",
            "density.advisor.dismissedUntilTS",
            "home.dashboard.useNewHome",
            "home.dashboard.density.pinned",
            "activeProfileID",
            "morningSetup.lastDate",
            // AI enrichment config (keys/tokens handled in step 2 above)
            "ai.enabled", "ai.activeProvider", "ai.autoEnrichNewTasks",
            "ai.showEnrichButtons",
            "ai.ollama.host", "ai.ollama.model"
        ] {
            defaults.removeObject(forKey: key)
        }

        // 4. Reset the in-memory active-profile pointer and re-seed defaults.
        profileManager.activeProfile = nil
        profileManager.seedDefaultsIfNeeded()
    }

    // MARK: - Delete

    private func deleteProfiles(at indexSet: IndexSet) {
        // Guard: must always keep at least one profile
        guard profiles.count > 1 else { return }

        for index in indexSet {
            let profile = profiles[index]
            let isDeletingActive = profileManager.activeProfile?.clientID == profile.clientID

            modelContext.delete(profile)

            // If we just deleted the active profile, switch to the first remaining one
            if isDeletingActive {
                let remaining = profiles.enumerated()
                    .filter { $0.offset != index }
                    .map { $0.element }
                if let next = remaining.first {
                    profileManager.switchTo(next)
                }
            }
        }
        do {
            try modelContext.save()
        } catch {
            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
        }
    }
}

// MARK: - Add Agenda Item View

struct AddAgendaItemView: View {

    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var profileManager: ActiveProfileManager
    @Query(sort: \Profile.sortOrder) private var profiles: [Profile]

    /// Pre-assign to a specific profile (used from HouseholdOverviewView)
    var preAssignedProfileID: UUID? = nil

    /// Editing mode — when non-nil the form populates from this item on
    /// appear and updates it in place on save instead of inserting a new one.
    var existingItem: AgendaItem? = nil

    @State private var title = ""
    @State private var scheduledDate: Date = .now
    @State private var frictionLevel = 3
    @State private var priority = 0
    @State private var contextTag = ""
    @State private var assignedToProfileID: UUID? = nil

    // Six-axis difficulty model — three of these are NEW dimensions added
    // for the difficulty rank engine. Hidden behind a disclosure so the
    // basic form stays simple. See memory/task_difficulty_and_ai_enrichment.md
    @State private var energyRequired = 2
    @State private var interestLevel = 3
    @State private var sensoryLoad = 0
    @State private var socialLoad = 0
    @State private var initiationCost = 0
    @State private var specialInterest = false
    @State private var excludeFromAI = false
    @State private var showMoreDimensions = false

    // AI enrichment local UI state
    @State private var enrichState: EnrichState = .idle
    @State private var enrichmentNote: String? = nil
    @AppStorage("ai.enabled") private var aiEnabled: Bool = false
    @AppStorage("ai.activeProvider") private var activeProviderRaw: String = ""
    @AppStorage("ai.showEnrichButtons") private var showEnrichButtons: Bool = true
    @AppStorage("ai.autoEnrichNewTasks") private var autoEnrich: Bool = false

    private var activeProfile: Profile? { profileManager.activeProfile }
    private var copy: NDCopy { NDCopy.from(profileManager) }
    private var frictionLabelName: String { copy.frictionPrompt }

    /// AI enrichment is offered only when:
    ///   1. The master switch is on
    ///   2. The user has picked a provider
    ///   3. The Show-Enrich-Buttons toggle is on
    ///   4. This task isn't flagged excludeFromAI
    ///   5. There's a non-empty title to enrich
    private var canOfferEnrichment: Bool {
        aiEnabled
        && !activeProviderRaw.isEmpty
        && showEnrichButtons
        && !excludeFromAI
        && !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private enum EnrichState: Equatable {
        case idle
        case running
        case applied(summary: String)
        case failed(message: String)
    }

    /// Live difficulty rank preview — re-computed as the user moves sliders.
    private var previewRank: Int {
        DifficultyEngine.rank(
            friction:       frictionLevel,
            energy:         energyRequired,
            sensoryLoad:    sensoryLoad,
            socialLoad:     socialLoad,
            initiationCost: initiationCost,
            interest:       interestLevel
        )
    }

    private var previewBand: DifficultyBand { DifficultyBand(rank: previewRank) }

    /// Only show the assignment section if the active profile can assign and there are other profiles
    private var canShowAssignment: Bool {
        (activeProfile?.canAssignTasks == true) && profiles.count > 1
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing?", text: $title)
                        .font(.body)
                }

                Section("When") {
                    DatePicker("Time", selection: $scheduledDate, displayedComponents: [.hourAndMinute, .date])
                }

                Section(frictionLabelName) {
                    Picker(frictionLabelName, selection: $frictionLevel) {
                        Text("1 — Easy start").tag(1)
                        Text("2 — Low").tag(2)
                        Text("3 — Moderate").tag(3)
                        Text("4 — High wall").tag(4)
                        Text("5 — Very hard").tag(5)
                    }
                    .pickerStyle(.menu)
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        Text("Normal").tag(0)
                        Text("High").tag(1)
                        Text("Urgent").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Context") {
                    TextField("e.g. home, phone, computer", text: $contextTag)
                }

                // AI enrich button — only shown when AI is enabled AND a
                // provider is selected AND this task isn't excluded.
                if canOfferEnrichment {
                    Section {
                        Button {
                            Task { await runEnrich() }
                        } label: {
                            HStack(spacing: 10) {
                                switch enrichState {
                                case .idle:
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(Color.warmEmber)
                                    Text("Enrich with AI")
                                        .foregroundStyle(.primary)
                                case .running:
                                    ProgressView().controlSize(.small)
                                    Text("Enriching…")
                                        .foregroundStyle(.secondary)
                                case .applied(let summary):
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Filled in").foregroundStyle(.primary)
                                        Text(summary).font(.caption).foregroundStyle(.secondary)
                                    }
                                case .failed(let msg):
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text(msg).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .disabled(enrichState == .running)
                    } footer: {
                        if let note = enrichmentNote {
                            Text(note).font(.caption2).foregroundStyle(.secondary)
                        } else if let provider = AIProvider(rawValue: activeProviderRaw) {
                            Text("Sends the title to \(provider.displayName) and fills in the dimensions below. Your assigned interest level is not sent.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                // More dimensions — collapsed by default. Surfaces the three
                // newer axes (sensory / social / initiation) plus energy +
                // interest. Live difficulty band preview at the bottom.
                Section {
                    DisclosureGroup(isExpanded: $showMoreDimensions) {
                        VStack(alignment: .leading, spacing: 18) {
                            dimensionSlider(
                                title: "Energy required",
                                tooltip: "Cognitive + physical cost. 1 = low, 4 = high.",
                                value: $energyRequired,
                                range: 1...4
                            )
                            dimensionSlider(
                                title: "Interest",
                                tooltip: "How engaged you are. Higher interest absorbs difficulty.",
                                value: $interestLevel,
                                range: 1...5
                            )
                            dimensionSlider(
                                title: "Sensory load",
                                tooltip: "Noise, light, smell, crowd exposure. 0 = none, 3 = severe.",
                                value: $sensoryLoad,
                                range: 0...3
                            )
                            dimensionSlider(
                                title: "Social load",
                                tooltip: "Synchronous communication weight. 0 = solo, 3 = unknown caller.",
                                value: $socialLoad,
                                range: 0...3
                            )
                            dimensionSlider(
                                title: "Initiation cost",
                                tooltip: "First-step / dread weight, independent of execution effort.",
                                value: $initiationCost,
                                range: 0...3
                            )

                            Toggle(isOn: $specialInterest) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Special interest").font(.subheadline)
                                    Text("Bypasses difficulty filter — always shown.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .tint(Color.warmEmber)

                            Toggle(isOn: $excludeFromAI) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Exclude from AI enrichment")
                                        .font(.subheadline)
                                    Text("Hides the Enrich button on this task. Auto-enrich skips it.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .tint(Color.appAccent)

                            // Live difficulty preview
                            HStack(spacing: 10) {
                                Image(systemName: "scope")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Difficulty: \(previewBand.label)")
                                        .font(.subheadline).fontWeight(.medium)
                                    Text(previewBand.description)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                Color.secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                        }
                        .padding(.vertical, 6)
                    } label: {
                        HStack {
                            Text("More dimensions")
                            Spacer()
                            Text(previewBand.label)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if canShowAssignment {
                    Section("Assign to") {
                        ForEach(profiles) { profile in
                            Button {
                                assignedToProfileID = profile.clientID
                            } label: {
                                HStack(spacing: 12) {
                                    ProfileAvatarView(profile: profile, size: 28)
                                    Text(profile.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if assignedToProfileID == profile.clientID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.appAccent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(existingItem == nil ? "New item" : "Edit item")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingItem == nil ? "Add" : "Save") { saveAndDismiss() }
                        .disabled(title.isEmpty)
                }
            }
        }
        .onAppear { hydrate() }
    }

    private func hydrate() {
        if let existing = existingItem {
            // Populate state from existing item — edit mode
            title = existing.title
            scheduledDate = existing.scheduledDate
            frictionLevel = existing.frictionLevel
            priority = existing.priority
            contextTag = existing.contextTag
            assignedToProfileID = existing.assignedToProfileID ?? activeProfile?.clientID

            // Six-axis difficulty fields
            energyRequired   = existing.energyRequired
            interestLevel    = existing.interestLevel
            sensoryLoad      = existing.sensoryLoad
            socialLoad       = existing.socialLoad
            initiationCost   = existing.initiationCost
            specialInterest  = existing.specialInterest
            excludeFromAI    = existing.excludeFromAI
        } else {
            // Fresh form — creation mode
            assignedToProfileID = preAssignedProfileID ?? activeProfile?.clientID
        }
    }

    /// Call the active AI provider with the current title + neurotype
    /// context, then apply any returned fields to state. Interest level
    /// is never written even if the provider sends one — interest stays
    /// the user's.
    private func runEnrich() async {
        guard AIUsageLedger.shared.canEnrich() else {
            ErrorBannerController.shared.show("AI enrichment paused — monthly budget reached")
            return
        }
        guard let provider = AIProvider(rawValue: activeProviderRaw),
              let enricher = AIEnricherRegistry.enricher(for: provider) else {
            enrichState = .failed(message: "No provider configured.")
            return
        }

        let neurotypes: [String] = activeProfile?.neurotypes.map(\.rawValue) ?? []
        let density: String? = profileManager.activePreferences?.effectiveDensity.rawValue

        // Snapshot personalization (about-me + tone + memory + interest
        // opt-in). Nil when the user hasn't set anything — providers
        // behave as cold-context in that case.
        let personalization = await MainActor.run {
            PersonalizationStore.shared.snapshot()
        }

        let context = EnrichmentContext(
            rawTitle: title.trimmingCharacters(in: .whitespaces),
            userNote: contextTag.isEmpty ? nil : contextTag,
            neurotypes: neurotypes,
            currentDensity: density,
            personalization: personalization
        )

        enrichState = .running
        do {
            let result = try await enricher.enrich(context: context)
            apply(result)
            await MainActor.run {
                AIUsageLedger.shared.record(result)
                // Memory layer — record what just happened so the next
                // enrichment has continuity. Uses the final difficulty
                // band, not the AI's guess, so memory reflects what the
                // user actually ended up with.
                PersonalizationStore.shared.recordEnrichment(
                    title: title,
                    band: DifficultyBand(rank: previewRank)
                )
            }
            let band = DifficultyBand(rank: previewRank).label
            enrichState = .applied(summary: "Difficulty: \(band) · review below.")
        } catch let error as AIEnricherError {
            enrichState = .failed(message: error.errorDescription ?? "Failed")
        } catch {
            enrichState = .failed(message: "Unexpected error.")
        }
    }

    /// Apply non-nil enrichment fields to local state. Interest is only
    /// written when the user opted into AI inference; otherwise the
    /// enrichment's interest field is guaranteed nil by the adapters'
    /// defense-in-depth strip.
    private func apply(_ enrichment: TaskEnrichment) {
        if let v = enrichment.title, !v.isEmpty { title = v }
        if let v = enrichment.friction        { frictionLevel  = v }
        if let v = enrichment.energy          { energyRequired = v }
        if let v = enrichment.sensoryLoad     { sensoryLoad    = v }
        if let v = enrichment.socialLoad      { socialLoad     = v }
        if let v = enrichment.initiationCost  { initiationCost = v }
        if let v = enrichment.interest        { interestLevel  = v }   // honored only when opt-in is on
        if let v = enrichment.contextTag, !v.isEmpty { contextTag = v }
        // Expand "More dimensions" so the user can immediately see what
        // changed. They can collapse it again after reviewing.
        showMoreDimensions = true
    }

    private func saveAndDismiss() {
        if let existing = existingItem {
            // Edit in place — preserve clientID, notes, completion state, etc.
            existing.title = title
            existing.scheduledDate = scheduledDate
            existing.priority = priority
            existing.frictionLevel = frictionLevel
            existing.contextTag = contextTag
            existing.assignedToProfileID = assignedToProfileID
            existing.updatedAt = .now

            // Six-axis difficulty fields
            existing.energyRequired   = energyRequired
            existing.interestLevel    = interestLevel
            existing.sensoryLoad      = sensoryLoad
            existing.socialLoad       = socialLoad
            existing.initiationCost   = initiationCost
            existing.specialInterest  = specialInterest
            existing.excludeFromAI    = excludeFromAI

            // Reschedule notifications so the new time is reflected
            notificationManager.cancelNotifications(for: existing)
            notificationManager.scheduleNotifications(for: existing)
            do {
                try modelContext.save()
            } catch {
                ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
            }
        } else {
            let item = AgendaItem(
                title: title,
                scheduledDate: scheduledDate,
                priority: priority,
                frictionLevel: frictionLevel,
                contextTag: contextTag
            )
            item.energyRequired  = energyRequired
            item.interestLevel   = interestLevel
            item.sensoryLoad     = sensoryLoad
            item.socialLoad      = socialLoad
            item.initiationCost  = initiationCost
            item.specialInterest = specialInterest
            item.excludeFromAI   = excludeFromAI
            item.assignedToProfileID = assignedToProfileID
            // Mark the creator only when assigning to someone else
            if assignedToProfileID != activeProfile?.clientID {
                item.assignedByProfileID = activeProfile?.clientID
            }
            modelContext.insert(item)
            do {
                try modelContext.save()
            } catch {
                ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
            }
            notificationManager.scheduleNotifications(for: item)
        }
        isPresented = false
    }

    /// Compact slider row used for each of the six axes. Title on top, range
    /// label trailing, slider below. Tooltip kept terse so the form doesn't
    /// turn into a reading exercise.
    @ViewBuilder
    private func dimensionSlider(
        title: String,
        tooltip: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline).fontWeight(.medium)
                Spacer()
                Text("\(value.wrappedValue) / \(range.upperBound)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .tint(Color.appAccent)
            Text(tooltip).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Empty State

struct EmptyAgendaView: View {
    var copy: NDCopy = NDCopy(style: .standard)

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(copy.emptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Child Agenda List
// Simplified task display for child profiles — larger targets, no friction dots, no snooze.

struct ChildAgendaList: View {

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationManager: NotificationManager
    #if canImport(WatchConnectivity)
    @EnvironmentObject private var watchManager: WatchConnectivityManager
    #endif

    let items: [AgendaItem]

    var body: some View {
        LazyVStack(spacing: 10) {
            if items.isEmpty {
                VStack(spacing: 14) {
                    Text("🎉")
                        .font(.system(size: 48))
                    Text("Nothing to do!")
                        .font(.title3).fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)
            } else {
                ForEach(items) { item in
                    ChildItemCard(item: item)
                        .padding(.horizontal)
                }
            }
        }
    }
}

private struct ChildItemCard: View {

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationManager: NotificationManager
    #if canImport(WatchConnectivity)
    @EnvironmentObject private var watchManager: WatchConnectivityManager
    #endif

    let item: AgendaItem
    @State private var tapped = false

    var body: some View {
        Button { complete() } label: {
            HStack(spacing: 16) {
                // Large, easy-to-hit completion circle
                Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 32))
                    .foregroundStyle(item.isComplete ? .green : Color.appAccent)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.title3).fontWeight(.semibold)
                        .foregroundStyle(item.isComplete ? .secondary : .primary)
                        .strikethrough(item.isComplete)

                    Text(item.scheduledDate.formatted(.dateTime.hour().minute()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(18)
            .background(
                item.isComplete
                    ? Color.green.opacity(0.08)
                    : Color.appAccent.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        item.isComplete ? Color.green.opacity(0.3) : Color.appAccent.opacity(0.15),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(tapped ? 0.96 : 1)
        .animation(.spring(duration: 0.2), value: tapped)
    }

    private func complete() {
        ActivityLog.recordCompletion()
        tapped = true
        withAnimation(.spring(duration: 0.3)) {
            item.isComplete = true
            item.completedAt = .now
            item.updatedAt = .now
        }
        notificationManager.cancelNotifications(for: item)
        do {
            try modelContext.save()
        } catch {
            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
        }
        #if canImport(WatchConnectivity)
        watchManager.sendSyncSnapshot()
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { tapped = false }
    }
}

// MARK: - Color Extensions
//
// Adaptive Color.app* extensions live in AuDHDComponents.swift (single source
// of truth so both old views and the new design system see the same colors).
// The duplicate definition that used to be here was removed to fix
// "ambiguous use of 'appBackground'" macOS compile errors.

// MARK: - Calendar Extension

extension Calendar {
    func endOfDay(for date: Date) -> Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return self.date(byAdding: components, to: startOfDay(for: date)) ?? date
    }
}
