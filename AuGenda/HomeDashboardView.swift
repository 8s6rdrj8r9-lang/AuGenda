// HomeDashboardView.swift
// AuGenda — Home Dashboard (Session 2 scaffold)
//
// Implements the five-zone ND-native dashboard from Session 1's strategic spec:
//
//   ┌────────────────────────────────────────────────┐
//   │  ORIENTATION ANCHOR   ← time, profile, energy  │
//   ├────────────────────────────────────────────────┤
//   │  PRIMARY ACTION ZONE  ← the one thing to do    │
//   │                         (recovery / focus /    │
//   │                          block / next item /   │
//   │                          top task / empty)     │
//   ├────────────────────────────────────────────────┤
//   │  MOMENTUM SURFACE     ← scannable secondary    │
//   │   - Today (remaining)                          │
//   │   - For Now (energy-matched, ndPriorityScore)  │
//   │   - Active Block                               │
//   │   - Backlog Spotlight (high capacity only)     │
//   ├────────────────────────────────────────────────┤
//   │  CONTEXTUAL DEPTH     ← tap/long-press         │
//   ├────────────────────────────────────────────────┤
//   │  RECOVERY SURFACE     ← overlay layer          │
//   └────────────────────────────────────────────────┘
//
// Density is derived from `currentEnergyLevel` and may be pinned by the
// user via the anchor's capacity badge. The pinned override is persisted
// per-profile on `ProfilePreferences.densityPinned` (SwiftData + CloudKit
// synced), with a one-time migration from the legacy device-local
// @AppStorage("home.dashboard.density.pinned") key.
//
// NOT yet wired into ContentView's TabView — TodayView remains the default
// for now. Swap `TodayView()` → `HomeDashboardView()` in ContentView when
// the surface has been validated.

import SwiftUI
import SwiftData

// MARK: - Home Dashboard View

struct HomeDashboardView: View {

    // MARK: Dependencies

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var profileManager: ActiveProfileManager
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var blockManager: BlockManager

    // MARK: Data

    @Query(filter: #Predicate<AgendaItem> { !$0.isComplete },
           sort: \AgendaItem.scheduledDate)
    private var allItems: [AgendaItem]

    @Query(filter: #Predicate<AgendaTask> { !$0.isComplete && !$0.isAbandoned },
           sort: \AgendaTask.sortOrder)
    private var allTasks: [AgendaTask]

    @Query(sort: \Block.sortOrder)
    private var allBlocks: [Block]

    /// Completed items — fetched separately for the "completed today" trail.
    @Query(
        filter: #Predicate<AgendaItem> { $0.isComplete },
        sort: [SortDescriptor(\AgendaItem.completedAt, order: .reverse)]
    )
    private var completedItems: [AgendaItem]

    // MARK: State

    /// Recovery flow state — used to dismiss the inline recovery card.
    @State private var recoveryDismissed: Bool = false

    /// Hyperfocus banner state — local-dismissable for a session.
    @State private var hyperfocusWarningDismissed: Bool = false

    @State private var selectedItem: AgendaItem?
    @State private var selectedTask: AgendaTask?
    @State private var selectedBlock: Block?
    @State private var showEnergyCheck: Bool = false
    @State private var showDensityPicker: Bool = false

    // MARK: - Derived

    private var activeProfile: Profile? { profileManager.activeProfile }
    private var activePrefs: ProfilePreferences? { profileManager.activePreferences }
    private var energyLevel: Int { activePrefs?.currentEnergyLevel ?? 3 }

    /// Effective density mode = pinned (per-profile) OR auto-derived from energy.
    private var density: DensityMode {
        if let pinned = activePrefs?.densityPinned {
            return pinned
        }
        return DensityMode.autoFrom(energyLevel: energyLevel)
    }

    private var isDensityPinned: Bool { activePrefs?.densityPinned != nil }

    /// Tasks visible to the active profile (with the unassigned-legacy fallthrough).
    private var profileItems: [AgendaItem] {
        let pid = activeProfile?.clientID
        return allItems.filter { item in
            if let assigned = item.assignedToProfileID { return assigned == pid }
            return true
        }
    }

    private var profileTasks: [AgendaTask] {
        let pid = activeProfile?.clientID
        return allTasks.filter { task in
            if let assigned = task.assignedToProfileID { return assigned == pid }
            return true
        }
    }

    /// Today's not-yet-complete items, filtered by snooze + due-today.
    private var todayItems: [AgendaItem] {
        let now = Date.now
        let endOfDay = Calendar.current.endOfDay(for: now)
        return profileItems.filter { item in
            if let snooze = item.snoozedUntil, snooze > now { return false }
            return item.scheduledDate <= endOfDay
        }
    }

    /// Top-ranked actionable tasks for the For-Now section.
    private var forNowTasks: [AgendaTask] {
        profileTasks
            .filter {
                $0.isActionable &&
                $0.frictionLevel <= max(energyLevel, 2) &&
                $0.energyRequired <= energyLevel
            }
            .sorted { $0.ndPriorityScore > $1.ndPriorityScore }
    }

    /// Today's blocks (sorted by sortOrder).
    private var todayBlocks: [Block] {
        allBlocks.filter { !$0.isComplete }
    }

    /// Tomorrow's scheduled items — used in high-capacity preview.
    private var tomorrowItems: [AgendaItem] {
        let cal = Calendar.current
        guard let tomorrowStart = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) else { return [] }
        let tomorrowEnd = cal.endOfDay(for: tomorrowStart)
        return profileItems.filter { $0.scheduledDate >= tomorrowStart && $0.scheduledDate <= tomorrowEnd }
    }

    /// Items completed today — momentum reinforcement strip (high capacity only).
    private var completedToday: [AgendaItem] {
        let cal = Calendar.current
        let pid = activeProfile?.clientID
        return completedItems
            .filter { item in
                guard let done = item.completedAt, cal.isDateInToday(done) else { return false }
                if let assigned = item.assignedToProfileID { return assigned == pid }
                return true
            }
            .prefix(5)
            .map { $0 }
    }

    /// Backlog spotlight — top 3 by ndPriorityScore, excluding anything already
    /// in the For-Now section and the primary card.
    private var backlogSpotlight: [AgendaTask] {
        let forNowIDs = Set(forNowTasks.map(\.clientID))
        let primaryID: UUID? = {
            if case .topTask(let t) = primaryContent { return t.clientID }
            return nil
        }()
        return profileTasks
            .filter { task in
                task.isActionable
                && !forNowIDs.contains(task.clientID)
                && task.clientID != primaryID
            }
            .sorted { $0.ndPriorityScore > $1.ndPriorityScore }
            .prefix(3)
            .map { $0 }
    }

    private var shouldShowRecovery: Bool {
        !recoveryDismissed && InterruptionContext.shouldShowRecovery
    }

    // MARK: - Hyperfocus elapsed

    private var hyperfocusMinutesElapsed: Int {
        guard notificationManager.focusSessionActive,
              let endsAt = notificationManager.focusSessionEndsAt,
              let sessionMinutes = activePrefs?.focusSessionMinutes
        else { return 0 }
        let startedAt = endsAt.addingTimeInterval(TimeInterval(-sessionMinutes * 60))
        return max(0, Int(Date.now.timeIntervalSince(startedAt) / 60))
    }

    private var shouldShowHyperfocusWarning: Bool {
        !hyperfocusWarningDismissed
            && notificationManager.focusSessionActive
            && hyperfocusMinutesElapsed >= 45
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: zoneSpacing) {

                    OrientationAnchor(
                        energyLevel: energyLevel,
                        density: density,
                        isPinned: isDensityPinned,
                        profileName: activeProfile?.name ?? "",
                        gapDescription: InterruptionContext.shouldShowRecovery
                            ? InterruptionContext.gapDescription
                            : nil,
                        energyStale: EnergyCheckInTracker.isStale,
                        onTapEnergy: { showEnergyCheck = true },
                        onTapCapacity: { showDensityPicker = true }
                    )

                    PrimaryActionZone(
                        content: primaryContent,
                        onOpenItem: { selectedItem = $0 },
                        onOpenTask: { selectedTask = $0 },
                        onResumeRecovery: dismissRecovery,
                        onReorientRecovery: { dismissRecovery(); showEnergyCheck = true },
                        onFreshRecovery: dismissRecovery
                    )
                    .padding(.horizontal, Tokens.Spacing.base)

                    if !density.isMinimalSurface {
                        MomentumSurface(
                            density: density,
                            todayItems: todayItemsExcludingPrimary,
                            forNowTasks: forNowTasksExcludingPrimary,
                            activeBlocks: todayBlocks,
                            backlogSpotlight: backlogSpotlight,
                            tomorrowItems: tomorrowItems,
                            completedToday: completedToday,
                            onTapItem: { selectedItem = $0 },
                            onTapTask: { selectedTask = $0 },
                            onTapBlock: { selectedBlock = $0 }
                        )
                        .padding(.horizontal, Tokens.Spacing.base)
                    }
                }
                .padding(.vertical, Tokens.Spacing.base)
            }
            .navigationTitle("Home")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .environment(\.densityMode, density)
            .background(Color.appBackground)
            .overlay(alignment: .top) {
                if shouldShowHyperfocusWarning {
                    HyperfocusWarning(
                        isShowing: .constant(true),
                        minutesElapsed: hyperfocusMinutesElapsed,
                        onContinue: {
                            withAnimation(Tokens.Animation.standardEase(reduce: reduceMotion)) {
                                hyperfocusWarningDismissed = true
                            }
                        },
                        onTakeBreak: {
                            notificationManager.endFocusSession()
                            withAnimation(Tokens.Animation.standardEase(reduce: reduceMotion)) {
                                hyperfocusWarningDismissed = true
                            }
                        }
                    )
                    .padding(.horizontal, Tokens.Spacing.base)
                }
            }
            .sheet(item: $selectedItem) { item in
                AgendaItemDetailSheet(item: item)
                    #if os(iOS)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    #endif
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
                    #if os(iOS)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    #endif
            }
            .sheet(item: $selectedBlock) { block in
                BlockDetailView(block: block)
                    #if os(iOS)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    #endif
            }
            .sheet(isPresented: $showEnergyCheck) {
                EnergyCheckView(isPresented: $showEnergyCheck)
                    .presentationDetents([.medium])
                    #if os(iOS)
                    .presentationDragIndicator(.visible)
                    #endif
            }
            .sheet(isPresented: $showDensityPicker) {
                DensityPickerSheet(
                    current: density,
                    isPinned: isDensityPinned,
                    onPick: pinDensity,
                    onAuto: clearPinnedDensity
                )
                .presentationDetents([.medium])
            }
        }
        .onAppear {
            migrateLegacyDensityPinIfNeeded()
            InterruptionContext.recordActivity(contextLabel: "home dashboard")
        }
    }

    // MARK: - Primary selection logic
    //
    // Implements the priority order from Session 1 §1.2:
    //   (1) Active focus session → (2) Active scheduled block →
    //   (3) Recovery prompt → (4) Next-scheduled item within 2hr →
    //   (5) Top ndPriorityScore task → (6) Empty.

    private var primaryContent: PrimaryContent {
        // (1) Active focus session
        if notificationManager.focusSessionActive,
           let endsAt = notificationManager.focusSessionEndsAt {
            return .focusSession(endsAt: endsAt)
        }

        // (2) Active block (BlockManager has its own currentBlock)
        if let block = blockManager.currentBlock, !block.isComplete {
            return .activeBlock(block)
        }

        // (3) Recovery prompt
        if shouldShowRecovery {
            return .recovery(
                lastItem: InterruptionContext.lastItemTitle,
                gap: InterruptionContext.gapDescription,
                contextLabel: InterruptionContext.lastContextLabel
            )
        }

        // (4) Next scheduled item within 2hr
        let twoHrs = Date.now.addingTimeInterval(2 * 60 * 60)
        if let next = todayItems.first(where: { $0.scheduledDate <= twoHrs && $0.scheduledDate >= Date.now.addingTimeInterval(-15 * 60) }) {
            return .scheduledItem(next)
        }

        // (5) Top ndPriorityScore task
        if let top = forNowTasks.first ?? profileTasks.sorted(by: { $0.ndPriorityScore > $1.ndPriorityScore }).first {
            return .topTask(top)
        }

        // (6) Empty
        return .empty
    }

    /// Today's items minus whichever one (if any) is in the primary zone — avoids duplication.
    private var todayItemsExcludingPrimary: [AgendaItem] {
        guard case .scheduledItem(let item) = primaryContent else { return todayItems }
        return todayItems.filter { $0.clientID != item.clientID }
    }

    private var forNowTasksExcludingPrimary: [AgendaTask] {
        guard case .topTask(let task) = primaryContent else { return forNowTasks }
        return forNowTasks.filter { $0.clientID != task.clientID }
    }

    // MARK: - Spacing token (varies by density)

    private var zoneSpacing: CGFloat {
        switch density {
        case .survival:   return Tokens.Spacing.xxl
        case .low:        return Tokens.Spacing.xl
        case .functional: return Tokens.Spacing.lg
        case .high:       return Tokens.Spacing.md
        }
    }

    // MARK: - Actions

    private func dismissRecovery() {
        InterruptionContext.clear()
        withAnimation(Tokens.Animation.standardEase(reduce: reduceMotion)) {
            recoveryDismissed = true
        }
    }

    private func pinDensity(_ mode: DensityMode) {
        guard let prefs = activePrefs else { return }
        withAnimation(Tokens.Animation.standardEase(reduce: reduceMotion)) {
            prefs.densityPinned = mode
            try? modelContext.save()
        }
    }

    private func clearPinnedDensity() {
        guard let prefs = activePrefs else { return }
        withAnimation(Tokens.Animation.standardEase(reduce: reduceMotion)) {
            prefs.densityPinned = nil
            try? modelContext.save()
        }
    }

    /// One-time migration from the legacy device-local @AppStorage key to
    /// per-profile `ProfilePreferences.densityPinnedRaw`. Runs on every
    /// dashboard appearance until the legacy key is cleared; safe to call
    /// repeatedly (no-op once the key is gone).
    private static let legacyPinKey = "home.dashboard.density.pinned"

    private func migrateLegacyDensityPinIfNeeded() {
        let defaults = UserDefaults.standard
        let legacy = defaults.string(forKey: Self.legacyPinKey) ?? ""
        guard !legacy.isEmpty else { return }

        // Only adopt the legacy value if the active profile has no pin set yet —
        // a fresh per-profile decision always wins over the device-global one.
        if let prefs = activePrefs, prefs.densityPinnedRaw.isEmpty,
           DensityMode(rawValue: legacy) != nil {
            prefs.densityPinnedRaw = legacy
            prefs.updatedAt = .now
            try? modelContext.save()
        }

        // Clear regardless — we only migrate once. If there's no active
        // profile yet (very first launch), the legacy value is dropped;
        // that's acceptable for a beta surface.
        defaults.removeObject(forKey: Self.legacyPinKey)
    }
}


// MARK: - Primary Content Selection (value type)

/// What the Primary Action Zone renders. Order matches Session 1 priority list.
enum PrimaryContent {
    case focusSession(endsAt: Date)
    case activeBlock(Block)
    case recovery(lastItem: String?, gap: String, contextLabel: String?)
    case scheduledItem(AgendaItem)
    case topTask(AgendaTask)
    case empty
}


// MARK: - Zone 1: Orientation Anchor

private struct OrientationAnchor: View {
    let energyLevel: Int
    let density: DensityMode
    let isPinned: Bool
    let profileName: String
    let gapDescription: String?
    let energyStale: Bool

    let onTapEnergy: () -> Void
    let onTapCapacity: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {

            // Time-of-day phrase
            Text(timeOfDayPhrase)
                .font(Tokens.Typography.h2)
                .foregroundColor(Color.appTextPrimary)

            // Context strip
            HStack(spacing: Tokens.Spacing.md) {

                if !profileName.isEmpty {
                    Text(profileName)
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Color.appTextSecondary)
                }

                // Energy pips (tap → check-in)
                Button(action: onTapEnergy) {
                    HStack(spacing: 4) {
                        HStack(spacing: 3) {
                            ForEach(1...4, id: \.self) { pip in
                                Circle()
                                    .fill(pip <= energyLevel ? Tokens.Color.info : Color.appBorder.opacity(0.5))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        // Stale-energy dot — subtle "this might be out of date"
                        if energyStale {
                            Circle()
                                .fill(Tokens.Color.warning)
                                .frame(width: 5, height: 5)
                                .accessibilityLabel("Energy reading is stale")
                        }
                    }
                    .frame(minHeight: Tokens.Spacing.touchMinimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Energy level \(energyLevel) of 4\(energyStale ? ", stale" : ""). Tap to update.")

                // Capacity badge (tap → density picker)
                Button(action: onTapCapacity) {
                    HStack(spacing: 4) {
                        Text(density.label)
                            .font(Tokens.Typography.caption)
                            .fontWeight(.semibold)
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                        }
                    }
                    .padding(.horizontal, Tokens.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(Color.appAccent.opacity(0.12))
                    .foregroundColor(Color.appAccent)
                    .cornerRadius(Tokens.Border.radiusSmall)
                }
                .buttonStyle(.plain)

                Spacer()

                if let gap = gapDescription {
                    Text("Last here \(gap) ago")
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Color.appTextSecondary)
                }
            }
        }
        .padding(.horizontal, Tokens.Spacing.base)
    }

    private var timeOfDayPhrase: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<22: return "Evening"
        default:      return "Late"
        }
    }
}


// MARK: - Zone 2: Primary Action Zone

private struct PrimaryActionZone: View {
    let content: PrimaryContent

    let onOpenItem: (AgendaItem) -> Void
    let onOpenTask: (AgendaTask) -> Void
    let onResumeRecovery: () -> Void
    let onReorientRecovery: () -> Void
    let onFreshRecovery: () -> Void

    var body: some View {
        switch content {
        case .focusSession(let endsAt):
            FocusSessionPrimaryCard(endsAt: endsAt)

        case .activeBlock(let block):
            ActiveBlockPrimaryCard(block: block)

        case .recovery(let lastItem, let gap, let contextLabel):
            RecoveryContextCard(
                lastItemTitle: lastItem,
                gapDescription: gap,
                lastContextLabel: contextLabel,
                onResume: onResumeRecovery,
                onReorient: onReorientRecovery,
                onFresh: onFreshRecovery
            )

        case .scheduledItem(let item):
            PrimaryAgendaCard(
                surface: TaskSurfaceData(from: item),
                ctaLabel: "Start",
                ctaIcon: "play.fill",
                onTap: { onOpenItem(item) },
                onCTA: { onOpenItem(item) }
            )

        case .topTask(let task):
            PrimaryAgendaCard(
                surface: TaskSurfaceData(from: task),
                ctaLabel: "Open",
                ctaIcon: "arrow.right",
                onTap: { onOpenTask(task) },
                onCTA: { onOpenTask(task) }
            )

        case .empty:
            EmptyPrimaryCard()
        }
    }
}


// MARK: - Primary Card Variants

private struct FocusSessionPrimaryCard: View {
    let endsAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: "timer")
                    .foregroundColor(Tokens.Color.info)
                Text("Focus session in progress")
                    .font(Tokens.Typography.label)
                    .foregroundColor(Color.appTextSecondary)
            }
            Text(endsAt, style: .timer)
                .font(Tokens.Typography.h1)
                .foregroundColor(Color.appTextPrimary)
            Text("Ends \(endsAt.formatted(.dateTime.hour().minute()))")
                .font(Tokens.Typography.caption)
                .foregroundColor(Color.appTextSecondary)
        }
        .padding(Tokens.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Color.info.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Border.radiusLarge))
    }
}

private struct ActiveBlockPrimaryCard: View {
    let block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: block.icon)
                    .foregroundColor(Color.appAccent)
                Text("Active block")
                    .font(Tokens.Typography.label)
                    .foregroundColor(Color.appTextSecondary)
            }
            Text(block.displayName)
                .font(Tokens.Typography.h1)
                .foregroundColor(Color.appTextPrimary)
            Text("\(block.completedTaskCount) of \(block.totalTaskCount) complete")
                .font(Tokens.Typography.caption)
                .foregroundColor(Color.appTextSecondary)
        }
        .padding(Tokens.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Border.radiusLarge))
    }
}

private struct EmptyPrimaryCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            Text("Nothing scheduled")
                .font(Tokens.Typography.h1)
                .foregroundColor(Color.appTextPrimary)
            Text("You're free. Take a breath, or pick something from the backlog.")
                .font(Tokens.Typography.body)
                .foregroundColor(Color.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Border.radiusLarge))
    }
}


// MARK: - Zone 3: Momentum Surface

private struct MomentumSurface: View {
    let density: DensityMode
    let todayItems: [AgendaItem]
    let forNowTasks: [AgendaTask]
    let activeBlocks: [Block]
    let backlogSpotlight: [AgendaTask]
    let tomorrowItems: [AgendaItem]
    let completedToday: [AgendaItem]

    let onTapItem: (AgendaItem) -> Void
    let onTapTask: (AgendaTask) -> Void
    let onTapBlock: (Block) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xl) {

            // ── Today section ──
            if !todayItems.isEmpty {
                MomentumSection(
                    title: "Today",
                    count: todayItems.count
                ) {
                    ForEach(todayItems.prefix(density.momentumCardLimit)) { item in
                        MomentumTaskCard(
                            surface: TaskSurfaceData(from: item),
                            onTap: { onTapItem(item) }
                        )
                    }
                }
            }

            // ── For Now (energy-matched) ──
            if !forNowTasks.isEmpty {
                MomentumSection(
                    title: "For Now",
                    subtitle: "Matched to your energy",
                    count: forNowTasks.count
                ) {
                    ForEach(forNowTasks.prefix(density.momentumCardLimit)) { task in
                        MomentumTaskCard(
                            surface: TaskSurfaceData(from: task),
                            onTap: { onTapTask(task) }
                        )
                    }
                }
            }

            // ── Active blocks / Routines ──
            if !activeBlocks.isEmpty {
                MomentumSection(title: "Routines", count: activeBlocks.count) {
                    ForEach(activeBlocks) { block in
                        BlockSummaryCard(block: block) { onTapBlock(block) }
                    }
                }
            }

            // ── High-capacity only sections ──
            if density.showsExpandedSurface {

                if !backlogSpotlight.isEmpty {
                    MomentumSection(
                        title: "Backlog Spotlight",
                        subtitle: "Top of your queue",
                        count: backlogSpotlight.count
                    ) {
                        ForEach(backlogSpotlight) { task in
                            MomentumTaskCard(
                                surface: TaskSurfaceData(from: task),
                                onTap: { onTapTask(task) }
                            )
                        }
                    }
                }

                if !tomorrowItems.isEmpty {
                    MomentumSection(
                        title: "Tomorrow",
                        subtitle: "A look ahead",
                        count: tomorrowItems.count
                    ) {
                        ForEach(tomorrowItems.prefix(5)) { item in
                            MomentumTaskCard(
                                surface: TaskSurfaceData(from: item),
                                onTap: { onTapItem(item) }
                            )
                        }
                    }
                }

                if !completedToday.isEmpty {
                    MomentumSection(
                        title: "Done today",
                        subtitle: "Momentum reinforcement",
                        count: completedToday.count
                    ) {
                        ForEach(completedToday) { item in
                            CompletedTrailRow(item: item)
                        }
                    }
                }
            }
        }
    }
}


// MARK: - Completed Trail Row (compact "done today" line)

private struct CompletedTrailRow: View {
    let item: AgendaItem

    var body: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(Tokens.Color.success.opacity(0.75))
            Text(item.title)
                .font(Tokens.Typography.body)
                .foregroundColor(Color.appTextSecondary)
                .strikethrough(true, color: Color.appTextSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let done = item.completedAt {
                Text(done.formatted(.dateTime.hour().minute()))
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Color.appTextSecondary)
            }
        }
        .padding(.vertical, Tokens.Spacing.xs)
        .padding(.horizontal, Tokens.Spacing.md)
        .opacity(0.75)
    }
}

private struct MomentumSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let count: Int
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.sm) {
                Text(title)
                    .font(Tokens.Typography.h3)
                    .foregroundColor(Color.appTextPrimary)
                if let sub = subtitle {
                    Text(sub)
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Color.appTextSecondary)
                }
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Color.appTextSecondary)
            }

            VStack(spacing: Tokens.Spacing.md) {
                content
            }
        }
    }
}

private struct BlockSummaryCard: View {
    let block: Block
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Tokens.Spacing.md) {
                Image(systemName: block.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.appAccent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(block.displayName)
                        .font(Tokens.Typography.h3)
                        .fontWeight(.bold)
                        .foregroundColor(Color.appTextPrimary)
                    Text("\(block.completedTaskCount) of \(block.totalTaskCount) done")
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Color.appTextSecondary)
                }

                Spacer()

                if block.currentStreak > 0 {
                    Label("\(block.currentStreak)", systemImage: "flame.fill")
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Tokens.Color.warning)
                }
            }
            .padding(Tokens.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appBackgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Border.radiusMedium))
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Density Picker Sheet

private struct DensityPickerSheet: View {
    let current: DensityMode
    let isPinned: Bool
    let onPick: (DensityMode) -> Void
    let onAuto: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                Text("Capacity")
                    .font(Tokens.Typography.h2)
                    .foregroundColor(Color.appTextPrimary)
                Text("How much can you take on right now?")
                    .font(Tokens.Typography.caption)
                    .foregroundColor(Color.appTextSecondary)
            }

            VStack(spacing: Tokens.Spacing.sm) {
                ForEach(DensityMode.allCases, id: \.self) { mode in
                    Button {
                        onPick(mode)
                        dismiss()
                    } label: {
                        HStack(spacing: Tokens.Spacing.md) {
                            Image(systemName: current == mode ? "circle.inset.filled" : "circle")
                                .foregroundColor(current == mode ? Color.appAccent : Color.appBorder)
                            Text(mode.label)
                                .font(Tokens.Typography.label)
                                .foregroundColor(Color.appTextPrimary)
                            Spacer()
                        }
                        .padding(Tokens.Spacing.base)
                        .frame(minHeight: Tokens.Spacing.touchMinimum)
                        .background(Color.appBackgroundSecondary)
                        .cornerRadius(Tokens.Border.radiusMedium)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isPinned {
                Button {
                    onAuto()
                    dismiss()
                } label: {
                    Text("Use my energy level automatically")
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Color.appAccent)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(Tokens.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground)
    }
}


// MARK: - AgendaItem Detail Sheet
//
// Reached from HomeDashboardView when the user taps an AgendaItem-backed
// card (Primary or Momentum). Calm read-first layout: title, scheduled
// time, notes, friction/energy, subtasks, plus Complete / Snooze / Start
// Focus Session actions. Editing happens elsewhere; this surface is for
// triage and start.

private struct AgendaItemDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var profileManager: ActiveProfileManager

    let item: AgendaItem

    @State private var showSnoozeMenu = false

    private var subtasks: [SubTask] {
        (item.subTasks ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var sessionMinutes: Int {
        profileManager.activePreferences?.focusSessionMinutes ?? 25
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {

                    // ── Title + time ──
                    VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                        Text(item.title.isEmpty ? "Untitled" : item.title)
                            .font(Tokens.Typography.h1)
                            .foregroundColor(Color.appTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !item.isAllDay {
                            Label(
                                item.scheduledDate.formatted(.dateTime.weekday(.abbreviated).hour().minute()),
                                systemImage: "clock"
                            )
                            .font(Tokens.Typography.body)
                            .foregroundColor(Color.appTextSecondary)
                        }
                    }

                    // ── Metadata row ──
                    HStack(spacing: Tokens.Spacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Friction")
                                .font(Tokens.Typography.caption)
                                .foregroundColor(Color.appTextSecondary)
                            FrictionDots(level: item.frictionLevel)
                        }
                        Spacer().frame(width: Tokens.Spacing.md)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Energy")
                                .font(Tokens.Typography.caption)
                                .foregroundColor(Color.appTextSecondary)
                            EnergyDots(level: item.energyRequired)
                        }
                        Spacer()
                        if !item.contextTag.isEmpty {
                            Text(item.contextTag)
                                .font(Tokens.Typography.caption)
                                .padding(.horizontal, Tokens.Spacing.sm)
                                .padding(.vertical, 4)
                                .background(Color.appBackgroundSecondary)
                                .clipShape(Capsule())
                                .foregroundColor(Color.appTextSecondary)
                        }
                    }

                    // ── Flags ──
                    if item.needsBodyDouble {
                        Label("Body double helps", systemImage: "person.wave.2.fill")
                            .font(Tokens.Typography.label)
                            .foregroundColor(Tokens.Color.info)
                    }

                    // ── Notes ──
                    if !item.notes.isEmpty {
                        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                            Text("Notes")
                                .font(Tokens.Typography.label)
                                .foregroundColor(Color.appTextSecondary)
                            Text(item.notes)
                                .font(Tokens.Typography.body)
                                .foregroundColor(Color.appTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Tokens.Spacing.base)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appBackgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Border.radiusMedium))
                    }

                    // ── Subtasks ──
                    if !subtasks.isEmpty {
                        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                            Text("Subtasks")
                                .font(Tokens.Typography.label)
                                .foregroundColor(Color.appTextSecondary)
                            ForEach(subtasks) { sub in
                                SubtaskRow(subtask: sub)
                            }
                        }
                        .padding(Tokens.Spacing.base)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appBackgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Border.radiusMedium))
                    }

                    // ── Primary actions ──
                    VStack(spacing: Tokens.Spacing.sm) {
                        actionButton(
                            title: "Start \(sessionMinutes)-min focus session",
                            icon: "timer",
                            primary: true,
                            action: startFocusSession
                        )

                        HStack(spacing: Tokens.Spacing.sm) {
                            actionButton(
                                title: "Complete",
                                icon: "checkmark.circle",
                                primary: false,
                                action: completeItem
                            )
                            actionButton(
                                title: "Snooze",
                                icon: "zzz",
                                primary: false,
                                action: { showSnoozeMenu = true }
                            )
                        }
                    }
                    .padding(.top, Tokens.Spacing.base)
                }
                .padding(Tokens.Spacing.xl)
            }
            .background(Color.appBackground)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog("Snooze for…", isPresented: $showSnoozeMenu) {
                Button("5 minutes")  { snooze(minutes: 5) }
                Button("15 minutes") { snooze(minutes: 15) }
                Button("30 minutes") { snooze(minutes: 30) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        icon: String,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(Tokens.Typography.label)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Tokens.Spacing.touchMinimum)
            .background(primary ? Color.appAccent : Color.appBackgroundSecondary)
            .foregroundColor(primary ? .black : Color.appTextPrimary)
            .cornerRadius(Tokens.Border.radiusMedium)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func startFocusSession() {
        notificationManager.startFocusSession(durationMinutes: sessionMinutes, taskTitle: item.title)
        InterruptionContext.recordActivity(itemTitle: item.title, contextLabel: "focus session")
        dismiss()
    }

    private func completeItem() {
        item.isComplete = true
        item.completedAt = .now
        item.updatedAt = .now
        notificationManager.cancelNotifications(for: item)
        try? modelContext.save()
        dismiss()
    }

    private func snooze(minutes: Int) {
        notificationManager.snooze(item: item, minutes: minutes)
        item.snoozedUntil = Date.now.addingTimeInterval(Double(minutes) * 60)
        item.updatedAt = .now
        try? modelContext.save()
        dismiss()
    }
}
