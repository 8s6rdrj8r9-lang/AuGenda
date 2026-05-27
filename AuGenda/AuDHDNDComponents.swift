// AuDHDNDComponents.swift
// AuGenda — Neurodivergent-Specific UI Components (Design System Chunk 4)
//
// Components built for AUDHD-specific UX needs:
// - InterruptionContext: UserDefaults-backed session state for recovery
// - InterruptionRecoveryPrompt: "Where were you?" overlay shown after 15+ min away
// - TaskCard: Design-system task row with inline complete, expand, and ND metadata
// - EnergyFilterBanner: Shows current energy filter + quick-change tap
// - HyperfocusWarning: Gentle floating alert at the 45-minute mark during focus sessions

import SwiftUI
import SwiftData

// MARK: - Energy Check-In Tracker (UserDefaults-backed)

/// Tracks when the user last confirmed their energy level. Separate from
/// `ProfilePreferences.updatedAt` (which fires on any preference change).
/// Used by the OrientationAnchor to surface a subtle "stale energy" hint.
enum EnergyCheckInTracker {
    private static let key = "energy.lastCheckIn"
    private static let staleThreshold: TimeInterval = 4 * 60 * 60   // 4 hours

    static var lastCheckIn: Date? {
        let ts = UserDefaults.standard.double(forKey: key)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    /// Call from any code path that sets `currentEnergyLevel` from a deliberate
    /// user action (e.g. EnergyCheckView's selection).
    static func record() {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: key)
    }

    static var isStale: Bool {
        guard let last = lastCheckIn else { return true }
        return Date.now.timeIntervalSince(last) > staleThreshold
    }
}

// MARK: - Activity Log (UserDefaults-backed)

/// Records user-initiated snooze + completion timestamps for the
/// `DensityAdvisor` pattern detector. Per-event-type ring buffers, capped
/// to the last 50 entries each, no SwiftData write per event.
///
/// The log is deliberately fire-and-forget: callers do not need to error-
/// check it, and a missing record is acceptable (the advisor is advisory).
enum ActivityLog {
    private static let defaults = UserDefaults.standard
    private static let snoozesKey = "activity.snoozes"
    private static let completionsKey = "activity.completions"
    private static let cap = 50

    // MARK: Record

    static func recordSnooze() { push(snoozesKey) }
    static func recordCompletion() { push(completionsKey) }

    // MARK: Query

    static func snoozes(inLastMinutes minutes: Int) -> Int {
        count(snoozesKey, sinceMinutes: minutes)
    }

    static func completions(inLastMinutes minutes: Int) -> Int {
        count(completionsKey, sinceMinutes: minutes)
    }

    /// Wipe all activity. Used by tests or for explicit "fresh start" flows.
    static func clear() {
        defaults.removeObject(forKey: snoozesKey)
        defaults.removeObject(forKey: completionsKey)
    }

    // MARK: Internals

    private static func push(_ key: String) {
        var stamps = (defaults.array(forKey: key) as? [Double]) ?? []
        stamps.append(Date.now.timeIntervalSince1970)
        if stamps.count > cap { stamps = Array(stamps.suffix(cap)) }
        defaults.set(stamps, forKey: key)
    }

    private static func count(_ key: String, sinceMinutes minutes: Int) -> Int {
        let threshold = Date.now.addingTimeInterval(-Double(minutes * 60)).timeIntervalSince1970
        let stamps = (defaults.array(forKey: key) as? [Double]) ?? []
        return stamps.filter { $0 >= threshold }.count
    }
}

// MARK: - Interruption Context (UserDefaults-backed)

/// Lightweight, synchronous storage for tracking where the user left off.
/// Stored in UserDefaults so it survives app termination without a SwiftData write.
enum InterruptionContext {

    private static let defaults = UserDefaults.standard

    // MARK: Keys

    private enum Key {
        static let lastItemTitle = "irp.lastItemTitle"
        static let lastActiveDate = "irp.lastActiveDate"
        static let lastContextLabel = "irp.lastContextLabel"
    }

    // MARK: Getters / setters

    static var lastItemTitle: String? {
        get { defaults.string(forKey: Key.lastItemTitle) }
        set { defaults.set(newValue, forKey: Key.lastItemTitle) }
    }

    static var lastActiveDate: Date? {
        get {
            let ts = defaults.double(forKey: Key.lastActiveDate)
            return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        }
        set {
            defaults.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Key.lastActiveDate)
        }
    }

    static var lastContextLabel: String? {
        get { defaults.string(forKey: Key.lastContextLabel) }
        set { defaults.set(newValue, forKey: Key.lastContextLabel) }
    }

    // MARK: Helpers

    /// Call on any meaningful user action (tapping a task, navigating, etc.)
    static func recordActivity(itemTitle: String? = nil, contextLabel: String = "browsing tasks") {
        lastActiveDate = .now
        if let title = itemTitle { lastItemTitle = title }
        lastContextLabel = contextLabel
    }

    /// Wipes all stored context after the user acts on the recovery prompt.
    static func clear() {
        defaults.removeObject(forKey: Key.lastItemTitle)
        defaults.set(0, forKey: Key.lastActiveDate)
        defaults.removeObject(forKey: Key.lastContextLabel)
    }

    /// Whether to show the recovery prompt (15+ minutes away).
    static var shouldShowRecovery: Bool {
        guard let last = lastActiveDate else { return false }
        return Date.now.timeIntervalSince(last) > 15 * 60
    }

    /// Human-friendly description of how long the user was away.
    static var gapDescription: String {
        guard let last = lastActiveDate else { return "a while" }
        let minutes = Int(Date.now.timeIntervalSince(last) / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        return hours == 1 ? "about an hour" : "\(hours) hours"
    }
}

// MARK: - Interruption Recovery Prompt

/// Full-screen overlay shown when the user returns after a long break.
/// Helps re-orient without executive friction — no decisions required to dismiss.
///
/// Usage:
/// ```swift
/// @State private var showRecovery = InterruptionContext.shouldShowRecovery
///
/// .overlay {
///     InterruptionRecoveryPrompt(isShowing: $showRecovery) {
///         // onResume: scroll to last item, highlight it
///     } onFresh: {
///         // onFresh: collapse completed, scroll to top
///     } onReorient: {
///         // onReorient: open SmartSuggest / energy check-in
///     }
/// }
/// ```
struct InterruptionRecoveryPrompt: View {
    @Binding var isShowing: Bool
    var onResume: () -> Void
    var onFresh: () -> Void
    var onReorient: () -> Void

    private var gap: String { InterruptionContext.gapDescription }
    private var lastItem: String? { InterruptionContext.lastItemTitle }

    var body: some View {
        if isShowing {
            ZStack {
                // Dimmed background — tap outside to dismiss
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismiss(onResume)
                    }

                // Card
                VStack(spacing: Tokens.Spacing.xl) {

                    // Header
                    VStack(spacing: Tokens.Spacing.sm) {
                        Text("👋")
                            .font(.system(size: 40))

                        Text("Welcome back")
                            .font(Tokens.Typography.h2)
                            .fontWeight(.bold)
                            .foregroundColor(Color.appTextPrimary)

                        Text("You were away for \(gap).")
                            .font(Tokens.Typography.body)
                            .foregroundColor(Color.appTextSecondary)
                    }
                    .multilineTextAlignment(.center)

                    // Last-item reminder
                    if let item = lastItem {
                        HStack(spacing: Tokens.Spacing.base) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(Tokens.Color.info)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                                Text("Last thing:")
                                    .font(Tokens.Typography.caption)
                                    .foregroundColor(Color.appTextSecondary)
                                Text(item)
                                    .font(Tokens.Typography.body)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color.appTextPrimary)
                                    .lineLimit(2)
                            }

                            Spacer()
                        }
                        .padding(Tokens.Spacing.base)
                        .background(Tokens.Color.info.opacity(0.08))
                        .cornerRadius(Tokens.Border.radiusMedium)
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Border.radiusMedium)
                                .strokeBorder(Tokens.Color.info.opacity(0.2), lineWidth: Tokens.Border.widthDefault)
                        )
                    }

                    // Actions
                    VStack(spacing: Tokens.Spacing.md) {
                        AuDHDButton("Resume where I left off", icon: "arrow.clockwise", style: .primary) {
                            dismiss(onResume)
                        }

                        AuDHDButton("Help me figure out what to do", icon: "sparkles", style: .secondary) {
                            dismiss(onReorient)
                        }

                        AuDHDButton("Start fresh", style: .tertiary) {
                            dismiss(onFresh)
                        }
                    }
                }
                .padding(Tokens.Spacing.xl)
                .frame(maxWidth: 380)
                .background(Color.appBackground)
                .cornerRadius(Tokens.Border.radiusLarge)
                .shadow(
                    color: Tokens.Shadow.elevated.color,
                    radius: Tokens.Shadow.elevated.radius,
                    x: Tokens.Shadow.elevated.x,
                    y: Tokens.Shadow.elevated.y
                )
                .padding(.horizontal, Tokens.Spacing.lg)
            }
            .transition(.opacity)
            .animation(Tokens.Animation.standardEase(), value: isShowing)
        }
    }

    private func dismiss(_ action: () -> Void) {
        InterruptionContext.clear()
        withAnimation(Tokens.Animation.standardEase()) {
            isShowing = false
        }
        action()
    }
}

// MARK: - Task Card

/// Design-system task row for AgendaItem. Replaces AgendaItemRowView.
///
/// - Tap the checkmark: instantly marks complete
/// - Tap the row body: expands to show notes + subtasks + actions
/// - Priority is shown as a colored left border accent
/// - ND metadata row: friction dots, energy dots, context tag
///
/// Usage:
/// ```swift
/// ForEach(items) { item in
///     TaskCard(item: item)
/// }
/// ```
struct TaskCard: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var notificationManager: NotificationManager
    #if canImport(WatchConnectivity)
    @EnvironmentObject private var watchManager: WatchConnectivityManager
    #endif

    let item: AgendaItem

    @State private var isExpanded = false
    @State private var showSnoozeMenu = false

    var body: some View {
        HStack(spacing: 0) {
            // Priority accent bar (left edge)
            priorityBar

            // Main content
            VStack(spacing: 0) {
                // Summary row (always visible)
                summaryRow

                // Expanded detail (collapse by default)
                if isExpanded {
                    Divider()
                        .padding(.horizontal, Tokens.Spacing.base)

                    expandedDetail
                }
            }
        }
        .background(Color.appBackground)
        .cornerRadius(Tokens.Border.radiusMedium)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Border.radiusMedium)
                .strokeBorder(Color.appBorder, lineWidth: Tokens.Border.widthDefault)
        )
        .shadow(
            color: Tokens.Shadow.subtle.color,
            radius: Tokens.Shadow.subtle.radius,
            x: Tokens.Shadow.subtle.x,
            y: Tokens.Shadow.subtle.y
        )
        .opacity(item.isComplete ? 0.55 : 1.0)
        .animation(Tokens.Animation.standardEase(), value: isExpanded)
        .confirmationDialog("Snooze for…", isPresented: $showSnoozeMenu) {
            Button("5 minutes")  { snooze(minutes: 5) }
            Button("15 minutes") { snooze(minutes: 15) }
            Button("30 minutes") { snooze(minutes: 30) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Sub-views

    private var priorityBar: some View {
        Rectangle()
            .fill(priorityAccentColor)
            .frame(width: item.priority >= 1 ? 4 : 0)
            // Parent's .cornerRadius clips this bar at the card edges automatically
    }

    private var summaryRow: some View {
        HStack(spacing: Tokens.Spacing.base) {
            // Checkmark (44pt touch target)
            Button {
                completeItem()
            } label: {
                Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(item.isComplete ? Tokens.Color.success : Color.appBorder)
                    .frame(width: Tokens.Spacing.touchMinimum, height: Tokens.Spacing.touchMinimum)
            }
            .buttonStyle(.plain)

            // Title + metadata
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                Text(item.title.isEmpty ? "Untitled task" : item.title)
                    .font(Tokens.Typography.body)
                    .fontWeight(.medium)
                    .foregroundColor(Color.appTextPrimary)
                    .strikethrough(item.isComplete, color: Color.appTextSecondary)
                    .lineLimit(2)

                // ND metadata row
                HStack(spacing: Tokens.Spacing.md) {
                    // Scheduled time
                    if !item.isAllDay {
                        Label(item.scheduledDate.formatted(.dateTime.hour().minute()),
                              systemImage: "clock")
                            .font(Tokens.Typography.caption)
                            .foregroundColor(Color.appTextSecondary)
                            .labelStyle(.titleAndIcon)
                    }

                    // Friction dots
                    FrictionDots(level: item.frictionLevel)

                    // Energy dots
                    EnergyDots(level: item.energyRequired)

                    // Context tag
                    if !item.contextTag.isEmpty {
                        Text(item.contextTag)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, Tokens.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Color.appBackgroundSecondary)
                            .cornerRadius(Tokens.Border.radiusSmall)
                            .foregroundColor(Color.appTextSecondary)
                    }
                }
            }

            Spacer(minLength: 0)

            // Expand chevron
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.appTextSecondary)
                .frame(width: Tokens.Spacing.touchMinimum, height: Tokens.Spacing.touchMinimum)
        }
        .padding(.horizontal, Tokens.Spacing.base)
        .padding(.vertical, Tokens.Spacing.md)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Tokens.Animation.standardSpring()) {
                isExpanded.toggle()
                if isExpanded {
                    // Record the context when user expands a task
                    InterruptionContext.recordActivity(
                        itemTitle: item.title,
                        contextLabel: "reviewing task"
                    )
                }
            }
        }
    }

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.base) {

            // Notes (if any)
            if !item.notes.isEmpty {
                Text(item.notes)
                    .font(Tokens.Typography.body)
                    .foregroundColor(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Subtasks (if any)
            let subtasks = (item.subTasks ?? []).sorted { $0.sortOrder < $1.sortOrder }
            if !subtasks.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                    Text("Subtasks")
                        .font(Tokens.Typography.label)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.appTextSecondary)

                    ForEach(subtasks) { sub in
                        SubtaskRow(subtask: sub)
                    }
                }
            }

            // Action row: snooze + (body double badge)
            HStack(spacing: Tokens.Spacing.md) {
                Button {
                    showSnoozeMenu = true
                } label: {
                    Label("Snooze", systemImage: "zzz")
                        .font(Tokens.Typography.label)
                        .foregroundColor(Color.appTextSecondary)
                }
                .buttonStyle(.plain)

                if item.needsBodyDouble {
                    Label("Body double", systemImage: "person.wave.2.fill")
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Tokens.Color.info)
                        .padding(.horizontal, Tokens.Spacing.sm)
                        .padding(.vertical, Tokens.Spacing.xs)
                        .background(Tokens.Color.info.opacity(0.1))
                        .cornerRadius(Tokens.Border.radiusSmall)
                }

                Spacer()

                // Due date (if different from scheduled)
                if let due = item.dueDate {
                    Text("Due \(due.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(Tokens.Typography.caption)
                        .foregroundColor(dueDateColor(due))
                }
            }
        }
        .padding(Tokens.Spacing.base)
    }

    // MARK: - Helpers

    private var priorityAccentColor: Color {
        switch item.priority {
        case 2: return Tokens.Color.warning          // urgent: amber
        case 1: return Tokens.Color.info             // high: blue
        default: return Color.clear                  // normal: no bar
        }
    }

    private func dueDateColor(_ due: Date) -> Color {
        let days = Calendar.current.dateComponents([.day], from: .now, to: due).day ?? 0
        if days < 0  { return Tokens.Color.warning }  // overdue
        if days <= 1 { return Tokens.Color.warning }  // today or tomorrow
        return Color.appTextSecondary
    }

    // MARK: - Actions

    private func completeItem() {
        ActivityLog.recordCompletion()
        withAnimation(Tokens.Animation.standardSpring()) {
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
        ActivityLog.recordSnooze()
        notificationManager.snooze(item: item, minutes: minutes)
        item.snoozedUntil = Date.now.addingTimeInterval(Double(minutes) * 60)
        item.updatedAt = .now
        try? modelContext.save()
        #if canImport(WatchConnectivity)
        watchManager.sendSyncSnapshot()
        #endif
    }
}

// MARK: - Subtask Row

/// A single subtask row with inline complete toggle.
struct SubtaskRow: View {
    @Environment(\.modelContext) private var modelContext
    let subtask: SubTask

    var body: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Button {
                withAnimation(Tokens.Animation.standardEase()) {
                    subtask.isComplete.toggle()
                    try? modelContext.save()
                }
            } label: {
                Image(systemName: subtask.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(subtask.isComplete ? Tokens.Color.success : Color.appBorder)
            }
            .buttonStyle(.plain)

            Text(subtask.title)
                .font(Tokens.Typography.body)
                .foregroundColor(subtask.isComplete ? Color.appTextSecondary : Color.appTextPrimary)
                .strikethrough(subtask.isComplete, color: Color.appTextSecondary)
                .lineLimit(2)

            Spacer()
        }
    }
}

// MARK: - Energy Dots

/// Visual indicator of how much energy this task requires.
/// Blue dots (not warning color) — energy is neutral info, not a threat.
struct EnergyDots: View {
    let level: Int   // 1–4

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...4, id: \.self) { pip in
                Circle()
                    .fill(pip <= level ? Tokens.Color.info : Color.appBorder.opacity(0.5))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityLabel("Energy required: \(energyLabel)")
    }

    private var energyLabel: String {
        switch level {
        case 1: return "low"
        case 2: return "medium"
        case 3: return "high"
        default: return "very high"
        }
    }
}

// MARK: - Energy Filter Banner

/// Compact sticky banner showing the active energy filter.
/// Lets the user see what's being shown/hidden and tap to adjust.
///
/// Usage:
/// ```swift
/// VStack(spacing: 0) {
///     EnergyFilterBanner(energyLevel: $currentEnergyLevel)
///     taskList
/// }
/// ```
struct EnergyFilterBanner: View {
    @Binding var energyLevel: Int
    var filteredOutCount: Int = 0    // How many tasks are hidden by this filter
    var onTap: (() -> Void)? = nil   // Optional override; default opens the EnergyCheckIn

    @State private var showCheckIn = false

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            // Energy pips
            HStack(spacing: 3) {
                ForEach(1...4, id: \.self) { pip in
                    Circle()
                        .fill(pip <= energyLevel ? energyColor : Color.appBorder)
                        .frame(width: 7, height: 7)
                }
            }

            // Label
            VStack(alignment: .leading, spacing: 0) {
                Text("Energy: \(energyLabel)")
                    .font(Tokens.Typography.label)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.appTextPrimary)

                if filteredOutCount > 0 {
                    Text("\(filteredOutCount) task\(filteredOutCount == 1 ? "" : "s") hidden")
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Color.appTextSecondary)
                }
            }

            Spacer()

            // Tap to change
            Button {
                if let customTap = onTap {
                    customTap()
                } else {
                    showCheckIn.toggle()
                }
            } label: {
                Text("Change")
                    .font(Tokens.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Tokens.Color.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Tokens.Spacing.base)
        .padding(.vertical, Tokens.Spacing.sm)
        .background(energyColor.opacity(0.08))
        .overlay(
            Rectangle()
                .fill(energyColor.opacity(0.3))
                .frame(height: 2),
            alignment: .bottom
        )
        .sheet(isPresented: $showCheckIn) {
            EnergyCheckInSheet(energyLevel: $energyLevel)
                #if os(iOS)
                .presentationDetents([.height(240)])
                #endif
        }
    }

    private var energyColor: Color {
        switch energyLevel {
        case 1, 2: return Tokens.Color.warning
        case 3:    return Tokens.Color.info
        default:   return Tokens.Color.success
        }
    }

    private var energyLabel: String {
        switch energyLevel {
        case 1: return "Survival"
        case 2: return "Low"
        case 3: return "Good"
        default: return "High"
        }
    }
}

// MARK: - Energy Check-In Sheet

/// Compact sheet for adjusting energy level (shown from EnergyFilterBanner).
private struct EnergyCheckInSheet: View {
    @Binding var energyLevel: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Tokens.Spacing.lg) {
            Text("How's your energy right now?")
                .font(Tokens.Typography.h3)
                .fontWeight(.semibold)
                .foregroundColor(Color.appTextPrimary)

            EnergyCheckInCard(selectedLevel: $energyLevel) {
                dismiss()
            }

            Text("Tasks above your energy level will be hidden.")
                .font(Tokens.Typography.caption)
                .foregroundColor(Color.appTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Tokens.Spacing.xl)
        .background(Color.appBackground)
    }
}

// MARK: - Energy Filter Logic

/// Shared filtering logic for AgendaItem lists. Apply consistently across all views.
enum EnergyFilter {

    /// Returns only tasks the user can reasonably start at their current energy level.
    /// - frictionLevel: how hard starting feels (1–5). At low energy, surface only easy tasks.
    /// - energyRequired: raw energy cost (1–4). Match to current level.
    static func apply(_ items: [AgendaItem], energyLevel: Int) -> [AgendaItem] {
        items.filter { item in
            item.frictionLevel <= max(energyLevel, 2) &&   // always show if friction ≤ 2
            item.energyRequired <= energyLevel
        }
    }

    /// Count of tasks hidden by current energy filter.
    static func hiddenCount(_ items: [AgendaItem], energyLevel: Int) -> Int {
        items.count - apply(items, energyLevel: energyLevel).count
    }

    /// Sort by urgency (priority) desc, then friction asc — most actionable first.
    /// For a smarter sort on AgendaTask, use AgendaTask.ndPriorityScore instead.
    static func sorted(_ items: [AgendaItem]) -> [AgendaItem] {
        items.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.frictionLevel < $1.frictionLevel
        }
    }
}

// MARK: - Hyperfocus Warning

/// Gentle floating overlay shown after extended focus sessions.
/// Appears at the 45-minute mark when hyperfocusGuard is enabled.
/// NOT alarming — soft amber, dismissible, with a snooze option.
///
/// Controlled by the parent (FocusSessionView or ContentView):
/// ```swift
/// .overlay(alignment: .top) {
///     HyperfocusWarning(
///         isShowing: $showHyperfocusWarning,
///         minutesElapsed: elapsedMinutes
///     ) {
///         // onContinue: user acknowledges, hides for 10 min
///         showHyperfocusWarning = false
///     } onTakeBreak: {
///         // onTakeBreak: end session
///         notificationManager.endFocusSession()
///     }
/// }
/// ```
struct HyperfocusWarning: View {
    @Binding var isShowing: Bool
    var minutesElapsed: Int = 45
    var onContinue: () -> Void
    var onTakeBreak: () -> Void

    var body: some View {
        if isShowing {
            VStack(spacing: 0) {
                HStack(spacing: Tokens.Spacing.base) {
                    // Icon
                    Image(systemName: "timer.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(Tokens.Color.warning)

                    // Message
                    VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                        Text("Still going — \(minutesElapsed) minutes in")
                            .font(Tokens.Typography.label)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.appTextPrimary)

                        Text("Take a moment to check in with yourself.")
                            .font(Tokens.Typography.caption)
                            .foregroundColor(Color.appTextSecondary)
                    }

                    Spacer()

                    // Dismiss (keep going)
                    Button {
                        withAnimation(Tokens.Animation.standardEase()) {
                            isShowing = false
                        }
                        onContinue()
                    } label: {
                        Text("Keep going")
                            .font(Tokens.Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Tokens.Color.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Tokens.Spacing.lg)
                .padding(.vertical, Tokens.Spacing.base)
                .background(Color.appBackground)
                .overlay(
                    Rectangle()
                        .fill(Tokens.Color.warning.opacity(0.6))
                        .frame(height: 3),
                    alignment: .bottom
                )

                // Take a break (secondary action)
                Button {
                    withAnimation(Tokens.Animation.standardEase()) {
                        isShowing = false
                    }
                    onTakeBreak()
                } label: {
                    Text("Take a break now")
                        .font(Tokens.Typography.caption)
                        .foregroundColor(Tokens.Color.warning)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Tokens.Spacing.sm)
                        .background(Tokens.Color.warning.opacity(0.08))
                }
                .buttonStyle(.plain)
            }
            .shadow(
                color: Tokens.Shadow.elevated.color,
                radius: Tokens.Shadow.elevated.radius,
                x: Tokens.Shadow.elevated.x,
                y: Tokens.Shadow.elevated.y
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(Tokens.Animation.standardSpring(), value: isShowing)
        }
    }
}

// MARK: - Preview

#Preview("InterruptionRecoveryPrompt") {
    @Previewable @State var show = true

    Color.appBackground
        .ignoresSafeArea()
        .overlay {
            InterruptionRecoveryPrompt(
                isShowing: $show,
                onResume: { print("resume") },
                onFresh: { print("fresh") },
                onReorient: { print("reorient") }
            )
        }
}

#Preview("EnergyFilterBanner + HyperfocusWarning") {
    @Previewable @State var energy = 3
    @Previewable @State var showHyperfocus = true

    VStack(spacing: 0) {
        EnergyFilterBanner(energyLevel: $energy, filteredOutCount: 3)

        Spacer()

        HyperfocusWarning(
            isShowing: $showHyperfocus,
            minutesElapsed: 47,
            onContinue: { showHyperfocus = false },
            onTakeBreak: { showHyperfocus = false }
        )
    }
    .background(Color.appBackground)
}

/// Preview host for TaskCard — wraps the SwiftData container setup so the
/// `#Preview` body stays inside the ViewBuilder context (no explicit `return`).
private struct TaskCardPreviewHost: View {
    let container: ModelContainer
    let item1: AgendaItem
    let item2: AgendaItem
    let item3: AgendaItem

    init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let c = try! ModelContainer(for: AgendaItem.self, SubTask.self, configurations: config)

        let i1 = AgendaItem(title: "Reply to Jane's email about the project timeline",
                            frictionLevel: 2, energyRequired: 1, contextTag: "phone")
        i1.notes = "She asked about Q3 delivery dates. Check Notion first."
        c.mainContext.insert(i1)

        let i2 = AgendaItem(title: "Write up the Monday standup status report")
        i2.priority = 2
        i2.frictionLevel = 4
        i2.energyRequired = 3
        i2.needsBodyDouble = true
        c.mainContext.insert(i2)

        let i3 = AgendaItem(title: "Completed task example")
        i3.isComplete = true
        i3.completedAt = .now
        c.mainContext.insert(i3)

        self.container = c
        self.item1 = i1
        self.item2 = i2
        self.item3 = i3
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Spacing.lg) {
                TaskCard(item: item1)
                TaskCard(item: item2)
                TaskCard(item: item3)
            }
            .padding(Tokens.Spacing.lg)
        }
        .background(Color.appBackground)
        .modelContainer(container)
        .environmentObject(NotificationManager.shared)
    }
}

#Preview("TaskCard") {
    TaskCardPreviewHost()
}


// MARK: - Task Surface Data
//
// Common surface fields shared between AgendaItem (schedule-anchored) and
// AgendaTask (backlog). Lets Home cards be model-agnostic without forcing
// each model into a protocol — the cards just render what they're given.

struct TaskSurfaceData {
    let title: String
    let scheduledDate: Date?     // nil → unscheduled / all-day
    let dueDate: Date?
    let frictionLevel: Int
    let energyRequired: Int
    let estimatedMinutes: Int
    let contextTag: String
    let needsBodyDouble: Bool
    let hyperfocusRisk: Bool
    let priority: Int            // 0 normal, 1 high, 2 urgent
}

extension TaskSurfaceData {
    init(from item: AgendaItem) {
        self.title           = item.title
        self.scheduledDate   = item.isAllDay ? nil : item.scheduledDate
        self.dueDate         = item.dueDate
        self.frictionLevel   = item.frictionLevel
        self.energyRequired  = item.energyRequired
        self.estimatedMinutes = 15  // AgendaItem doesn't store an estimate; reasonable default
        self.contextTag      = item.contextTag
        self.needsBodyDouble = item.needsBodyDouble
        self.hyperfocusRisk  = false  // AgendaItem doesn't track this flag
        self.priority        = item.priority
    }

    init(from task: AgendaTask) {
        self.title           = task.title
        self.scheduledDate   = task.scheduledDate
        self.dueDate         = task.dueDate
        self.frictionLevel   = task.frictionLevel
        self.energyRequired  = task.energyRequired
        self.estimatedMinutes = task.totalEstimatedMinutes
        self.contextTag      = task.contextTag
        self.needsBodyDouble = task.needsBodyDouble
        self.hyperfocusRisk  = task.hyperfocusRisk
        self.priority        = task.priority
    }
}


// MARK: - Primary Agenda Card
//
// Hero card for the Primary Action Zone on Home. Heavy title, optional time,
// one prominent CTA. Density-adaptive: in survival/low modes the metadata
// row collapses to nothing; in functional/high it shows the full dot row.
//
// Caller wires up both onTap (open detail) and onCTA (start/complete) since
// semantics vary by what kind of subject is being presented.

struct PrimaryAgendaCard: View {
    @Environment(\.densityMode) private var density

    let surface: TaskSurfaceData
    let ctaLabel: String
    var ctaIcon: String? = "play.fill"
    var onTap: () -> Void = {}
    var onCTA: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {

            // ── Title ─────────────────────────────────────────────
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                Text(surface.title.isEmpty ? "Untitled" : surface.title)
                    .font(Tokens.Typography.h1)
                    .foregroundColor(Color.appTextPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let timeLabel = timeLabel {
                    Text(timeLabel)
                        .font(Tokens.Typography.h3)
                        .foregroundColor(Color.appTextSecondary)
                }
            }

            // ── Metadata row (density-gated) ──────────────────────
            if density.showsFullMetadata {
                HStack(spacing: Tokens.Spacing.md) {
                    if !surface.contextTag.isEmpty {
                        Text(surface.contextTag)
                            .font(Tokens.Typography.caption)
                            .foregroundColor(Color.appTextSecondary)
                    }

                    if surface.needsBodyDouble {
                        Label("Body double", systemImage: "person.wave.2.fill")
                            .font(Tokens.Typography.caption)
                            .foregroundColor(Tokens.Color.info)
                            .labelStyle(.titleAndIcon)
                    }

                    if surface.hyperfocusRisk {
                        Label("Hyperfocus", systemImage: "exclamationmark.triangle.fill")
                            .font(Tokens.Typography.caption)
                            .foregroundColor(Tokens.Color.warning)
                            .labelStyle(.titleAndIcon)
                    }

                    Spacer(minLength: 0)

                    FrictionDots(level: surface.frictionLevel)
                    EnergyDots(level: surface.energyRequired)
                }
                .opacity(0.85)
            }

            // ── Primary CTA ───────────────────────────────────────
            Button(action: onCTA) {
                HStack(spacing: Tokens.Spacing.sm) {
                    if let icon = ctaIcon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(ctaLabel)
                        .font(Tokens.Typography.label)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Tokens.Spacing.touchMinimum)
                .background(Color.appAccent)
                .foregroundColor(.black)
                .cornerRadius(Tokens.Border.radiusLarge)
            }
            .buttonStyle(.plain)
        }
        .padding(Tokens.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Border.radiusLarge))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var timeLabel: String? {
        if let scheduled = surface.scheduledDate {
            return scheduled.formatted(.dateTime.hour().minute()) + " · ~\(surface.estimatedMinutes)m"
        }
        return "~\(surface.estimatedMinutes)m"
    }
}


// MARK: - Momentum Task Card
//
// Density-adaptive secondary card for the Momentum Surface. Visually similar
// to AgendaTaskCard (TaskBacklogView) but consumes the abstracted surface
// data so it can represent either AgendaItem or AgendaTask uniformly.

struct MomentumTaskCard: View {
    @Environment(\.densityMode) private var density

    let surface: TaskSurfaceData
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 0) {
                if surface.priority > 0 {
                    Rectangle()
                        .fill(priorityColor)
                        .frame(width: 3)
                }

                VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {

                    // Title row
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.sm) {
                        Text(surface.title.isEmpty ? "Untitled" : surface.title)
                            .font(Tokens.Typography.h3)
                            .fontWeight(.bold)
                            .foregroundColor(Color.appTextPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)

                        if let timeLabel = compactTimeLabel {
                            Text(timeLabel)
                                .font(Tokens.Typography.caption)
                                .foregroundColor(Color.appTextSecondary)
                        }
                    }

                    // Status row (density-gated)
                    if density.showsFullMetadata {
                        HStack(spacing: Tokens.Spacing.sm) {
                            if !surface.contextTag.isEmpty {
                                Text(surface.contextTag)
                                    .font(Tokens.Typography.caption)
                                    .foregroundColor(Color.appTextSecondary)
                            }

                            if surface.needsBodyDouble {
                                Image(systemName: "person.wave.2.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Tokens.Color.info)
                            }

                            if surface.hyperfocusRisk {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Tokens.Color.warning)
                            }

                            Spacer(minLength: 0)

                            FrictionDots(level: surface.frictionLevel)
                            EnergyDots(level: surface.energyRequired)

                            if let due = surface.dueDate {
                                Text(due.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(Tokens.Typography.caption)
                                    .foregroundColor(dueDateColor(due))
                            }
                        }
                        .opacity(0.8)
                    }
                }
                .padding(Tokens.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.appBackgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Border.radiusMedium))
        }
        .buttonStyle(.plain)
    }

    private var priorityColor: Color {
        switch surface.priority {
        case 2:  return Tokens.Color.warning
        case 1:  return Tokens.Color.info
        default: return .clear
        }
    }

    private var compactTimeLabel: String? {
        if let scheduled = surface.scheduledDate {
            return scheduled.formatted(.dateTime.hour().minute())
        }
        return "~\(surface.estimatedMinutes)m"
    }

    private func dueDateColor(_ date: Date) -> Color {
        let days = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
        if days < 0  { return Tokens.Color.warning }
        if days <= 1 { return Tokens.Color.warning }
        return Color.appTextSecondary
    }
}


// MARK: - Recovery Context Card
//
// Inline version of InterruptionRecoveryPrompt for the Primary Action Zone.
// Renders "you were here N min ago" + three calm action choices. Unlike the
// modal prompt, this card lives in the content flow and is dismissed by any
// of its actions, not by tap-outside.

struct RecoveryContextCard: View {
    let lastItemTitle: String?
    let gapDescription: String
    let lastContextLabel: String?

    var onResume: () -> Void
    var onReorient: () -> Void
    var onFresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {

            // Header
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Tokens.Color.info)
                Text("You were here \(gapDescription) ago")
                    .font(Tokens.Typography.label)
                    .foregroundColor(Color.appTextSecondary)
            }

            // Last context — the user needs to recognise this
            if let title = lastItemTitle, !title.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    Text(title)
                        .font(Tokens.Typography.h2)
                        .foregroundColor(Color.appTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let ctx = lastContextLabel, !ctx.isEmpty {
                        Text(ctx.capitalized)
                            .font(Tokens.Typography.caption)
                            .foregroundColor(Color.appTextSecondary)
                    }
                }
            } else {
                Text("Welcome back")
                    .font(Tokens.Typography.h2)
                    .foregroundColor(Color.appTextPrimary)
            }

            // Three equal-weight choices
            VStack(spacing: Tokens.Spacing.sm) {
                recoveryButton("Resume where I left off",
                               icon: "arrow.clockwise",
                               primary: true,
                               action: onResume)
                recoveryButton("Help me figure out what to do",
                               icon: "sparkles",
                               primary: false,
                               action: onReorient)
                recoveryButton("Start fresh",
                               icon: nil,
                               primary: false,
                               action: onFresh)
            }
        }
        .padding(Tokens.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Color.info.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Border.radiusLarge))
    }

    @ViewBuilder
    private func recoveryButton(
        _ title: String,
        icon: String?,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Tokens.Spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(Tokens.Typography.label)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: Tokens.Spacing.touchMinimum)
            .padding(.horizontal, Tokens.Spacing.base)
            .background(primary ? Color.appAccent : Color.appBackgroundSecondary)
            .foregroundColor(primary ? .black : Color.appTextPrimary)
            .cornerRadius(Tokens.Border.radiusMedium)
        }
        .buttonStyle(.plain)
    }
}
