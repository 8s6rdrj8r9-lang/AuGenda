// NowView.swift
// AuGenda Watch
//
// The single screen of the watch app. Spec §3, §5, §6.
//
// Crown-scrollable column, stable layout across every visit:
//
//   ┌──────────────────────────────┐
//   │  ANCHOR ROW                  │  ← small tinted glyph + time / routine name
//   │  ┌────────────────────────┐  │
//   │  │  [Recovery card]       │  │  ← injected when InterruptionContext fires
//   │  └────────────────────────┘  │
//   │  ┌────────────────────────┐  │
//   │  │  NOW                   │  │  ← largest type, one primary action
//   │  │  (title, meta whisper) │  │
//   │  │  [ ▶ Start            ]│  │
//   │  └────────────────────────┘  │
//   │  ─── NEXT ──────────────     │  ← quiet — surfaced only when density > survival
//   │   • next task                │
//   │  ─── CAPTURE ────────────    │  ← dictation / Scribble / Siri
//   │   [ 🎙 Capture a thought ]   │
//   └──────────────────────────────┘
//
// Spec §7: Double Tap → primary action via .handGestureShortcut(.primaryAction).
// Spec §8: gentle haptics via .sensoryFeedback.
// Spec §14: VoiceOver labels speak cognitive meaning, not visual properties.

import SwiftUI
import SwiftData
import WatchKit

struct NowView: View {

    // MARK: Environment & data

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @EnvironmentObject private var session: WatchSessionClient

    @Query(
        filter: #Predicate<AgendaItem> { !$0.isComplete },
        sort: \AgendaItem.scheduledDate
    )
    private var upcomingItems: [AgendaItem]

    @Query(
        filter: #Predicate<AgendaTask> { !$0.isComplete && !$0.isAbandoned },
        sort: \AgendaTask.sortOrder
    )
    private var backlogTasks: [AgendaTask]

    @Query private var profiles: [Profile]

    // MARK: State

    /// Tracks the completion-haptic so it fires exactly once per action.
    @State private var lastCompletedID: UUID? = nil
    /// Recovery dismissal — keeps the card hidden after the user acts.
    @State private var recoveryDismissed = false

    // MARK: Derived

    /// The active profile, if SwiftData has seeded one. Watch v1 doesn't
    /// support profile switching — we use the first profile's preferences.
    private var activeProfile: Profile? { profiles.first }
    private var activePrefs: ProfilePreferences? { activeProfile?.preferences }

    private var energyLevel: Int { activePrefs?.currentEnergyLevel ?? 3 }

    /// Watch lives in `.survival` by default (spec §2). Honor the user's
    /// pinned mode if set; otherwise derive from energy.
    private var density: DensityMode {
        if let raw = activePrefs?.densityPinnedRaw,
           !raw.isEmpty,
           let pinned = DensityMode(rawValue: raw) {
            return pinned
        }
        return DensityMode.autoFrom(energyLevel: energyLevel)
    }

    private var visibleItems: [AgendaItem] {
        let now = Date.now
        return upcomingItems.filter { item in
            if let snooze = item.snoozedUntil, snooze > now { return false }
            return true
        }
    }

    private var nowItem: AgendaItem? { visibleItems.first }
    private var nextItem: AgendaItem? { visibleItems.dropFirst().first }

    private var nextCount: Int { max(0, visibleItems.count - 1) }

    private var shouldShowRecovery: Bool {
        !recoveryDismissed
            && nowItem != nil
            && (session.focusSessionActive == false)
            // TODO(watch v2): wire InterruptionContext.shouldShowRecovery
            // through to the watch (currently iOS-only via UserDefaults).
            && false
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchTokens.Spacing.lg) {

                anchorRow

                if shouldShowRecovery {
                    recoveryCard
                        .transition(.opacity)
                }

                nowCard

                if density.watchShowsNext {
                    nextSection
                } else if nextCount > 0 {
                    nextCollapsedCount
                }

                captureSection
            }
            .padding(.horizontal, WatchTokens.Spacing.base)
            .padding(.vertical, WatchTokens.Spacing.md)
        }
        .background(WatchTokens.Color.background.ignoresSafeArea())
        .environment(\.densityMode, density)
        .containerBackground(WatchTokens.Color.background, for: .navigation)
        .onAppear { onAppearSetup() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.requestSync() }
        }
        // Spec §7: Double Tap → primary action.
        .handGestureShortcut(.primaryAction)
    }

    // MARK: - Zone 1: Anchor row

    private var anchorRow: some View {
        HStack(spacing: WatchTokens.Spacing.sm) {
            Image(systemName: anchorIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(anchorTint)
            Text(anchorLabel)
                .font(WatchTokens.Typography.anchorLabel)
                .foregroundStyle(WatchTokens.Color.textSecondary)
            Spacer(minLength: 0)
            Text(Date.now, style: .time)
                .font(WatchTokens.Typography.anchorLabel)
                .foregroundStyle(WatchTokens.Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(anchorLabel) at \(Date.now.formatted(.dateTime.hour().minute()))")
    }

    private var anchorIcon: String {
        if session.focusSessionActive { return "timer" }
        switch density {
        case .survival: return "moon.stars"
        case .low:      return "leaf"
        case .functional: return "sun.max"
        case .high:     return "bolt"
        }
    }

    private var anchorTint: Color {
        if session.focusSessionActive { return WatchTokens.Color.creative }
        switch density {
        case .survival, .low: return WatchTokens.Color.paused
        case .functional:     return WatchTokens.Color.manageable
        case .high:           return WatchTokens.Color.activation
        }
    }

    private var anchorLabel: String {
        if session.focusSessionActive { return "Focusing" }
        return density.label
    }

    // MARK: - Zone 2: Recovery card

    /// Inline recovery card per Spec §3, §6. Currently gated by a stub flag
    /// (`shouldShowRecovery` returns false) until interruption-context state
    /// flows through WatchConnectivity (v2).
    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: WatchTokens.Spacing.sm) {
            HStack(spacing: WatchTokens.Spacing.xs) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WatchTokens.Color.admin)
                Text("Welcome back")
                    .font(WatchTokens.Typography.anchorLabel)
                    .foregroundStyle(WatchTokens.Color.textSecondary)
            }
            if let title = nowItem?.title, !title.isEmpty {
                Text("You were on \(title).")
                    .font(WatchTokens.Typography.nextTitle)
                    .foregroundStyle(WatchTokens.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Got it") { recoveryDismissed = true }
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .padding(WatchTokens.Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchTokens.Color.admin.opacity(0.10), in: RoundedRectangle(cornerRadius: WatchTokens.Border.radiusMedium))
    }

    // MARK: - Zone 3: NOW card

    private var nowCard: some View {
        Group {
            if let item = nowItem {
                NowCard(item: item, onComplete: { complete(item) })
            } else {
                EmptyNowCard()
            }
        }
        .sensoryFeedback(.success, trigger: lastCompletedID)
    }

    // MARK: - Zone 4: NEXT

    private var nextSection: some View {
        VStack(alignment: .leading, spacing: WatchTokens.Spacing.xs) {
            sectionHeader("Next")
            if let item = nextItem {
                NextRow(item: item)
                if nextCount > 1 {
                    Text("+\(nextCount - 1) more")
                        .font(WatchTokens.Typography.metadata)
                        .foregroundStyle(WatchTokens.Color.textTertiary)
                }
            } else if let task = backlogTasks.first {
                NextRow(taskTitle: task.title, contextTag: task.contextTag, frictionLevel: task.frictionLevel)
            } else {
                Text("Nothing queued")
                    .font(WatchTokens.Typography.metadata)
                    .foregroundStyle(WatchTokens.Color.textTertiary)
            }
        }
    }

    /// In Survival mode the NEXT list collapses to a single count line.
    private var nextCollapsedCount: some View {
        HStack(spacing: WatchTokens.Spacing.xs) {
            Image(systemName: "circle.grid.2x1")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(WatchTokens.Color.textTertiary)
            Text("\(nextCount) waiting")
                .font(WatchTokens.Typography.metadata)
                .foregroundStyle(WatchTokens.Color.textTertiary)
        }
        .accessibilityLabel("\(nextCount) more tasks waiting. Lower priority right now.")
    }

    // MARK: - Zone 5: CAPTURE

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: WatchTokens.Spacing.xs) {
            sectionHeader("Capture")
            CaptureButton()
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(WatchTokens.Typography.metadata)
            .foregroundStyle(WatchTokens.Color.textTertiary)
            .accessibilityHidden(true)   // section title is structural, not informational
    }

    // MARK: - Actions

    private func onAppearSetup() {
        WatchAppContainer.seedIfEmpty(modelContext)
        session.modelContext = modelContext
        session.requestSync()
    }

    private func complete(_ item: AgendaItem) {
        withAnimation(WatchTokens.Animation.standardEase(reduce: reduceMotion)) {
            item.isComplete = true
            item.completedAt = .now
            item.updatedAt = .now
        }
        try? modelContext.save()
        lastCompletedID = item.clientID
        session.sendTaskCompleted(clientID: item.clientID)
    }
}

// MARK: - NowCard

/// The NOW block. Largest type, one primary action, thin leading accent
/// (color never a fill — spec §6, §10). The button is the gesture target
/// for Double Tap via .handGestureShortcut(.primaryAction) on the parent.
private struct NowCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: AgendaItem
    let onComplete: () -> Void

    private var tint: Color {
        WatchTint.resolve(frictionLevel: item.frictionLevel, contextTag: item.contextTag)
    }

    var body: some View {
        HStack(alignment: .top, spacing: WatchTokens.Spacing.sm) {
            // Thin leading accent bar — encodes domain without filling.
            RoundedRectangle(cornerRadius: WatchTokens.Border.leadingBar / 2)
                .fill(tint)
                .frame(width: WatchTokens.Border.leadingBar)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: WatchTokens.Spacing.sm) {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(WatchTokens.Typography.nowTitle)
                    .foregroundStyle(WatchTokens.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                metadataWhisper

                Button(action: onComplete) {
                    HStack(spacing: WatchTokens.Spacing.xs) {
                        Image(systemName: "checkmark")
                        Text(ctaLabel)
                            .font(WatchTokens.Typography.actionLabel)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WatchTokens.Spacing.xs)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .accessibilityLabel(accessibilityCTALabel)
            }
        }
        .padding(WatchTokens.Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: WatchTokens.Border.radiusMedium)
                .fill(Color.white.opacity(0.04))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityRootLabel)
    }

    /// Single tiny metadata line — a whisper of Level 3, never a row of icons.
    @ViewBuilder
    private var metadataWhisper: some View {
        if !item.isAllDay {
            HStack(spacing: WatchTokens.Spacing.xs) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                Text(item.scheduledDate, style: .time)
                    .font(WatchTokens.Typography.metadata)
                if !item.contextTag.isEmpty {
                    Text("·")
                        .font(WatchTokens.Typography.metadata)
                    Text(item.contextTag)
                        .font(WatchTokens.Typography.metadata)
                }
            }
            .foregroundStyle(WatchTokens.Color.textSecondary)
        }
    }

    private var ctaLabel: String { "Done" }

    private var accessibilityCTALabel: String { "Mark current task done" }

    private var accessibilityRootLabel: String {
        let frictionPhrase: String
        switch item.frictionLevel {
        case ...2: frictionPhrase = "manageable"
        case 3:    frictionPhrase = "moderate"
        default:   frictionPhrase = "harder to start"
        }
        return "Current task, \(frictionPhrase). \(item.title)."
    }
}

// MARK: - EmptyNowCard

private struct EmptyNowCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: WatchTokens.Spacing.sm) {
            Text("Nothing scheduled")
                .font(WatchTokens.Typography.nowTitle)
                .foregroundStyle(WatchTokens.Color.textPrimary)
            Text("You're free.")
                .font(WatchTokens.Typography.metadata)
                .foregroundStyle(WatchTokens.Color.textSecondary)
        }
        .padding(WatchTokens.Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nothing scheduled right now. You're free.")
    }
}

// MARK: - NextRow

private struct NextRow: View {
    let title: String
    let contextTag: String
    let frictionLevel: Int
    let scheduledDate: Date?

    init(item: AgendaItem) {
        self.title = item.title.isEmpty ? "Untitled" : item.title
        self.contextTag = item.contextTag
        self.frictionLevel = item.frictionLevel
        self.scheduledDate = item.isAllDay ? nil : item.scheduledDate
    }

    init(taskTitle: String, contextTag: String, frictionLevel: Int) {
        self.title = taskTitle.isEmpty ? "Untitled" : taskTitle
        self.contextTag = contextTag
        self.frictionLevel = frictionLevel
        self.scheduledDate = nil
    }

    private var tint: Color {
        WatchTint.resolve(frictionLevel: frictionLevel, contextTag: contextTag)
    }

    var body: some View {
        HStack(spacing: WatchTokens.Spacing.sm) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(WatchTokens.Typography.nextTitle)
                    .foregroundStyle(WatchTokens.Color.textPrimary)
                    .lineLimit(2)
                if let date = scheduledDate {
                    Text(date, style: .time)
                        .font(WatchTokens.Typography.metadata)
                        .foregroundStyle(WatchTokens.Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next: \(title)")
    }
}

// MARK: - CaptureButton

/// Spec §3, §7: instant thought capture. v1 surfaces a TextField so the
/// watch's system dictation / Scribble flow takes over on focus.
private struct CaptureButton: View {
    @Environment(\.modelContext) private var modelContext
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WatchTokens.Spacing.xs) {
            TextField("Capture a thought…", text: $draft, axis: .vertical)
                .lineLimit(1...3)
                .font(WatchTokens.Typography.nextTitle)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(commit)
                .accessibilityLabel("Capture a thought — dictation or Scribble")

            HStack {
                Spacer(minLength: 0)
                Button(action: commit) {
                    HStack(spacing: WatchTokens.Spacing.xs) {
                        Image(systemName: "tray.and.arrow.down")
                        Text("Save")
                            .font(WatchTokens.Typography.metadata)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(WatchTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: WatchTokens.Border.radiusMedium)
                .fill(Color.white.opacity(0.04))
        )
        .sensoryFeedback(.increase, trigger: draft.isEmpty)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = AgendaTask(
            title: trimmed,
            frictionLevel: 3,
            energyRequired: 2,
            estimatedMinutes: 15
        )
        modelContext.insert(task)
        try? modelContext.save()
        draft = ""
        focused = false
        // TODO(watch v2): forward to iPhone for inbox routing once the
        // capture flow on phone supports a watch-originated channel.
        WKInterfaceDevice.current().play(.success)
    }
}
