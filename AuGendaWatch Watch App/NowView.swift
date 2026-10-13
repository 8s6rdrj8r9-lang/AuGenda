// NowView.swift
// AuGenda Watch
//
// A single orientation surface backed only by the phone's current,
// active-profile-scoped snapshot. No sample or independent task store is
// presented as synchronized data.

import SwiftUI
import WatchKit

struct NowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: WatchSessionClient

    @State private var lastCompletedID: UUID?
    @State private var lastSnoozedID: UUID?
    @State private var recoveryDismissed = false
    @State private var showingEnergyOptions = false
    @State private var captureDraft = ""

    private var snapshot: WatchSnapshot? { session.freshSnapshot }

    private var density: DensityMode {
        if let raw = snapshot?.densityModeRaw,
           let pinned = DensityMode(rawValue: raw) {
            return pinned
        }
        return .autoFrom(energyLevel: snapshot?.currentEnergyLevel ?? 3)
    }

    private var visibleItems: [WatchAgendaSummary] {
        let now = Date.now
        return snapshot?.agendaItems.filter {
            guard let snoozedUntil = $0.snoozedUntil else { return true }
            return snoozedUntil <= now
        } ?? []
    }

    private var backlogTasks: [WatchBacklogSummary] {
        snapshot?.backlogTasks ?? []
    }

    private var nowItem: WatchAgendaSummary? { visibleItems.first }
    private var nextItem: WatchAgendaSummary? { visibleItems.dropFirst().first }
    private var nextCount: Int {
        max(0, visibleItems.count - 1) + backlogTasks.count
    }

    private var shouldShowRecovery: Bool {
        !recoveryDismissed
            && nowItem != nil
            && !session.focusSessionActive
            && session.pendingRecovery
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchTokens.Spacing.lg) {
                anchorRow

                if !session.rejectedCaptures.isEmpty {
                    rejectedCapturesSection
                }

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
                deliveryStatus
            }
            .padding(.horizontal, WatchTokens.Spacing.base)
            .padding(.vertical, WatchTokens.Spacing.md)
        }
        .background(WatchTokens.Color.background.ignoresSafeArea())
        .environment(\.densityMode, density)
        .containerBackground(WatchTokens.Color.background, for: .navigation)
        .onAppear { session.requestSync() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.requestSync() }
        }
    }

    // MARK: Anchor

    private var anchorRow: some View {
        HStack(spacing: WatchTokens.Spacing.sm) {
            Image(systemName: anchorIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(anchorTint)

            Text(anchorLabel)
                .font(WatchTokens.Typography.anchorLabel)
                .foregroundStyle(WatchTokens.Color.textSecondary)

            Spacer(minLength: 0)

            Button {
                showingEnergyOptions = true
            } label: {
                Image(systemName: "bolt.circle")
                    .foregroundStyle(WatchTokens.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(snapshot?.profileID == nil)
            .accessibilityLabel("Set energy level")
            .confirmationDialog(
                "Set energy level",
                isPresented: $showingEnergyOptions,
                titleVisibility: .visible
            ) {
                ForEach(1...4, id: \.self) { level in
                    Button("Energy \(level)") {
                        _ = session.sendEnergyUpdate(level: level)
                    }
                }
            }

            Text(Date.now, style: .time)
                .font(WatchTokens.Typography.anchorLabel)
                .foregroundStyle(WatchTokens.Color.textSecondary)
        }
        .accessibilityElement(children: .contain)
    }

    private var anchorIcon: String {
        if session.focusSessionActive { return "timer" }
        switch density {
        case .survival: return "moon.stars"
        case .low: return "leaf"
        case .functional: return "sun.max"
        case .high: return "bolt"
        }
    }

    private var anchorTint: Color {
        if session.focusSessionActive { return WatchTokens.Color.creative }
        switch density {
        case .survival, .low: return WatchTokens.Color.paused
        case .functional: return WatchTokens.Color.manageable
        case .high: return WatchTokens.Color.activation
        }
    }

    private var anchorLabel: String {
        if session.focusSessionActive { return "Focusing" }
        return density.label
    }

    // MARK: Recovery

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
        .background(
            WatchTokens.Color.admin.opacity(0.10),
            in: RoundedRectangle(cornerRadius: WatchTokens.Border.radiusMedium)
        )
    }

    // MARK: Now

    private var nowCard: some View {
        Group {
            if let item = nowItem {
                NowCard(
                    item: item,
                    onComplete: { complete(item) },
                    onSnooze: { minutes in snooze(item, minutes: minutes) }
                )
            } else {
                EmptyNowCard(hasFreshSnapshot: session.hasFreshSnapshot)
            }
        }
        .sensoryFeedback(.success, trigger: lastCompletedID)
        .sensoryFeedback(.decrease, trigger: lastSnoozedID)
    }

    // MARK: Next

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
                NextRow(
                    taskTitle: task.title,
                    contextTag: task.contextTag,
                    frictionLevel: task.frictionLevel
                )
            } else {
                Text(session.hasFreshSnapshot ? "Nothing queued" : "Sync needed")
                    .font(WatchTokens.Typography.metadata)
                    .foregroundStyle(WatchTokens.Color.textTertiary)
            }
        }
    }

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

    // MARK: Capture and delivery state

    private var rejectedCapturesSection: some View {
        VStack(alignment: .leading, spacing: WatchTokens.Spacing.xs) {
            sectionHeader("Recovery")
            ForEach(session.rejectedCaptures) { capture in
                RejectedCaptureCard(
                    capture: capture,
                    onRetry: {
                        _ = session.retryRejectedCapture(capture)
                    },
                    onCopy: {
                        captureDraft = capture.title
                        #if os(iOS)
                        UIPasteboard.general.string = capture.title
                        #endif
                        WKInterfaceDevice.current().play(.click)
                    },
                    onDismiss: {
                        session.dismissRejectedCapture(eventID: capture.eventID)
                    }
                )
            }
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: WatchTokens.Spacing.xs) {
            sectionHeader("Capture")
            CaptureButton(draft: $captureDraft)
        }
    }

    @ViewBuilder
    private var deliveryStatus: some View {
        if let error = session.lastDeliveryError {
            Label(error, systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                .font(WatchTokens.Typography.metadata)
                .foregroundStyle(WatchTokens.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if session.pendingMutationCount > 0 {
            Label(
                "\(session.pendingMutationCount) change\(session.pendingMutationCount == 1 ? "" : "s") queued",
                systemImage: "arrow.trianglehead.2.clockwise.rotate.90"
            )
            .font(WatchTokens.Typography.metadata)
            .foregroundStyle(WatchTokens.Color.textSecondary)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(WatchTokens.Typography.metadata)
            .foregroundStyle(WatchTokens.Color.textTertiary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Actions

    private func complete(_ item: WatchAgendaSummary) {
        guard session.sendTaskCompleted(clientID: item.clientID) else { return }
        withAnimation(WatchTokens.Animation.standardEase(reduce: reduceMotion)) {
            lastCompletedID = item.clientID
        }
    }

    private func snooze(_ item: WatchAgendaSummary, minutes: Int) {
        guard session.sendTaskSnoozed(clientID: item.clientID, minutes: minutes) else { return }
        withAnimation(WatchTokens.Animation.standardEase(reduce: reduceMotion)) {
            lastSnoozedID = item.clientID
        }
    }
}

// MARK: - Now card

private struct NowCard: View {
    let item: WatchAgendaSummary
    let onComplete: () -> Void
    let onSnooze: (Int) -> Void
    @State private var showingSnoozeOptions = false

    private var tint: Color {
        WatchTint.resolve(frictionLevel: item.frictionLevel, contextTag: item.contextTag)
    }

    var body: some View {
        HStack(alignment: .top, spacing: WatchTokens.Spacing.sm) {
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

                HStack(spacing: WatchTokens.Spacing.xs) {
                    Button(action: onComplete) {
                        Label("Done", systemImage: "checkmark")
                            .font(WatchTokens.Typography.actionLabel)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .accessibilityLabel("Mark current task done")
                    // Double Tap belongs to the primary action itself.
                    .handGestureShortcut(.primaryAction)

                    Button {
                        showingSnoozeOptions = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Snooze current task")
                    .confirmationDialog(
                        "Snooze current task",
                        isPresented: $showingSnoozeOptions,
                        titleVisibility: .visible
                    ) {
                        Button("5 minutes") { onSnooze(5) }
                        Button("15 minutes") { onSnooze(15) }
                        Button("30 minutes") { onSnooze(30) }
                    }
                }
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
                    Text(item.contextTag)
                }
            }
            .font(WatchTokens.Typography.metadata)
            .foregroundStyle(WatchTokens.Color.textSecondary)
        }
    }

    private var accessibilityRootLabel: String {
        let frictionPhrase: String
        switch item.frictionLevel {
        case ...2: frictionPhrase = "manageable"
        case 3: frictionPhrase = "moderate"
        default: frictionPhrase = "harder to start"
        }
        return "Current task, \(frictionPhrase). \(item.title)."
    }
}

// MARK: - Empty state

private struct EmptyNowCard: View {
    let hasFreshSnapshot: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WatchTokens.Spacing.sm) {
            Text(hasFreshSnapshot ? "Nothing scheduled" : "Sync needed")
                .font(WatchTokens.Typography.nowTitle)
                .foregroundStyle(WatchTokens.Color.textPrimary)
            Text(
                hasFreshSnapshot
                    ? "You're free."
                    : "Open AuGenda on iPhone to sync."
            )
            .font(WatchTokens.Typography.metadata)
            .foregroundStyle(WatchTokens.Color.textSecondary)
        }
        .padding(WatchTokens.Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Next row

private struct NextRow: View {
    let title: String
    let contextTag: String
    let frictionLevel: Int
    let scheduledDate: Date?

    init(item: WatchAgendaSummary) {
        title = item.title.isEmpty ? "Untitled" : item.title
        contextTag = item.contextTag
        frictionLevel = item.frictionLevel
        scheduledDate = item.isAllDay ? nil : item.scheduledDate
    }

    init(taskTitle: String, contextTag: String, frictionLevel: Int) {
        title = taskTitle.isEmpty ? "Untitled" : taskTitle
        self.contextTag = contextTag
        self.frictionLevel = frictionLevel
        scheduledDate = nil
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
                if let scheduledDate {
                    Text(scheduledDate, style: .time)
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

// MARK: - Capture

private struct CaptureButton: View {
    @EnvironmentObject private var session: WatchSessionClient
    @Binding var draft: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WatchTokens.Spacing.xs) {
            TextField("Capture a thought…", text: $draft, axis: .vertical)
                .lineLimit(1...3)
                .font(WatchTokens.Typography.nextTitle)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(commit)
                .disabled(!session.hasFreshSnapshot)
                .accessibilityLabel("Capture a thought — dictation or Scribble")

            HStack {
                Spacer(minLength: 0)
                Button(action: commit) {
                    Label("Save", systemImage: "tray.and.arrow.down")
                        .font(WatchTokens.Typography.metadata)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(
                    !session.hasFreshSnapshot
                        || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(WatchTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: WatchTokens.Border.radiusMedium)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, session.sendCapture(title: trimmed) else { return }
        draft = ""
        focused = false
        WKInterfaceDevice.current().play(.success)
    }
}

// MARK: - Rejected capture card

private struct RejectedCaptureCard: View {
    let capture: RejectedWatchCapture
    let onRetry: () -> Void
    let onCopy: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WatchTokens.Spacing.xs) {
            HStack {
                Label(capture.reason, systemImage: "exclamationmark.triangle.fill")
                    .font(WatchTokens.Typography.metadata)
                    .foregroundStyle(WatchTokens.Color.activation)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WatchTokens.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss rejected capture")
            }

            Text(capture.title)
                .font(WatchTokens.Typography.nextTitle)
                .foregroundStyle(WatchTokens.Color.textPrimary)
                .lineLimit(3)

            HStack(spacing: WatchTokens.Spacing.xs) {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(WatchTokens.Typography.metadata)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTokens.Color.activation)
                .controlSize(.mini)

                Button(action: onCopy) {
                    Label("Copy text", systemImage: "doc.on.doc")
                        .font(WatchTokens.Typography.metadata)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(WatchTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: WatchTokens.Border.radiusMedium)
                .fill(WatchTokens.Color.activation.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: WatchTokens.Border.radiusMedium)
                .strokeBorder(WatchTokens.Color.activation.opacity(0.35), lineWidth: 1)
        )
    }
}
