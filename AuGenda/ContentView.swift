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

    var body: some View {
        ZStack(alignment: .top) {
            Color.appBackground
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {

                TodayView()
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
        .preferredColorScheme(.dark)
        .onAppear {
            setupOnLaunch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agendaItemCompleted)) { note in
            handleCompleteAction(note.userInfo)
        }
        .onReceive(NotificationCenter.default.publisher(for: .agendaItemSnoozed)) { note in
            handleSnoozeAction(note.userInfo)
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
        item.isComplete = true
        item.completedAt = .now
        item.updatedAt = .now
        try? modelContext.save()
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
        notificationManager.snooze(item: item, minutes: minutes)
        item.snoozedUntil = Date.now.addingTimeInterval(Double(minutes) * 60)
        item.updatedAt = .now
        try? modelContext.save()
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
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Today")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ProfileQuickSwitchButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
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
                    .presentationDragIndicator(.visible)
            }
            .navigationDestination(isPresented: $showHousehold) {
                HouseholdOverviewView()
            }
            .sheet(isPresented: $showEnergyCheck) {
                EnergyCheckView(isPresented: $showEnergyCheck)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
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
        withAnimation(.spring(duration: 0.3)) {
            item.isComplete = true
            item.completedAt = .now
            item.updatedAt = .now
        }
        notificationManager.cancelNotifications(for: item)
        try? modelContext.save()
        #if canImport(WatchConnectivity)
        watchManager.sendSyncSnapshot()
        #endif
    }

    private func snooze(minutes: Int) {
        notificationManager.snooze(item: item, minutes: minutes)
        item.snoozedUntil = Date.now.addingTimeInterval(Double(minutes) * 60)
        item.updatedAt = .now
        try? modelContext.save()
        #if canImport(WatchConnectivity)
        watchManager.sendSyncSnapshot()
        #endif
    }
}

// MARK: - Friction Dots

struct FrictionDots: View {
    let level: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { dot in
                Circle()
                    .fill(dot <= level ? frictionColor : Color.secondary.opacity(0.2))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private var frictionColor: Color {
        switch level {
        case 1, 2: return .green
        case 3: return .yellow
        case 4: return .orange
        default: return .red
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
                .presentationDragIndicator(.visible)
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
        VStack(spacing: 24) {
            if let profile = profileManager.activeProfile {
                HStack(spacing: 10) {
                    ProfileAvatarView(profile: profile, size: 28)
                    Text("How's your energy, \(profile.name)?")
                        .font(.title3).fontWeight(.semibold)
                }
                .padding(.top, 24)
            } else {
                Text("How's your energy right now?")
                    .font(.title3).fontWeight(.semibold)
                    .padding(.top, 24)
            }

            Text("This adjusts what gets surfaced today.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(EnergyLevel.allCases) { level in
                    Button {
                        setEnergy(level.rawValue)
                    } label: {
                        HStack {
                            Text(level.emoji)
                            Text(level.label).fontWeight(.medium)
                            Spacer()
                            if prefs?.currentEnergyLevel == level.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                        .padding(14)
                        .background(
                            prefs?.currentEnergyLevel == level.rawValue
                                ? Color.appAccent.opacity(0.15)
                                : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)

            Button("Done") { isPresented = false }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)
                .padding(.bottom, 16)
        }
        .padding(.horizontal)
    }

    private func setEnergy(_ level: Int) {
        guard let prefs else { return }
        prefs.currentEnergyLevel = level
        prefs.updatedAt = .now
        try? modelContext.save()
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

    var body: some View {
        NavigationStack {
            Form {
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
            .navigationTitle("Settings")
            .sheet(isPresented: $showAddProfile) {
                ProfileSetupView(isPresented: $showAddProfile)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
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
        try? modelContext.save()
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

    @State private var title = ""
    @State private var scheduledDate: Date = .now
    @State private var frictionLevel = 3
    @State private var priority = 0
    @State private var contextTag = ""
    @State private var assignedToProfileID: UUID? = nil

    private var activeProfile: Profile? { profileManager.activeProfile }
    private var copy: NDCopy { NDCopy.from(profileManager) }
    private var frictionLabelName: String { copy.frictionPrompt }

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
            .navigationTitle("New item")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { saveAndDismiss() }
                        .disabled(title.isEmpty)
                }
            }
        }
        .onAppear {
            assignedToProfileID = preAssignedProfileID ?? activeProfile?.clientID
        }
    }

    private func saveAndDismiss() {
        let item = AgendaItem(
            title: title,
            scheduledDate: scheduledDate,
            priority: priority,
            frictionLevel: frictionLevel,
            contextTag: contextTag
        )
        item.assignedToProfileID = assignedToProfileID
        // Mark the creator only when assigning to someone else
        if assignedToProfileID != activeProfile?.clientID {
            item.assignedByProfileID = activeProfile?.clientID
        }
        modelContext.insert(item)
        try? modelContext.save()
        notificationManager.scheduleNotifications(for: item)
        isPresented = false
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
        tapped = true
        withAnimation(.spring(duration: 0.3)) {
            item.isComplete = true
            item.completedAt = .now
            item.updatedAt = .now
        }
        notificationManager.cancelNotifications(for: item)
        try? modelContext.save()
        #if canImport(WatchConnectivity)
        watchManager.sendSyncSnapshot()
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { tapped = false }
    }
}

// MARK: - Color Extensions

extension Color {
    #if canImport(UIKit)
    static let appBackground = Color(UIColor.systemBackground)
    #else
    static let appBackground = Color(NSColor.windowBackgroundColor)
    #endif
    static let appAccent = Color.cyan
}

// MARK: - Calendar Extension

extension Calendar {
    func endOfDay(for date: Date) -> Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return self.date(byAdding: components, to: startOfDay(for: date)) ?? date
    }
}
