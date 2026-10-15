// FocusSessionView.swift
// AUDHD Agenda App
//
// Full focus session UI:
// - Optional task selection before starting
// - Visual circular countdown ring (live, updates every second)
// - Halfway check-in prompt
// - Hyperfocus warning auto-scheduled for flagged tasks
// - Break phase after session ends (natural or early)
// - Post-break prompt to start another or return to tasks

import Combine
import SwiftUI
import SwiftData

// MARK: - Focus Session View

struct FocusSessionView: View {

    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var profileManager: ActiveProfileManager
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<AgendaTask> { !$0.isComplete && !$0.isAbandoned },
        sort: \AgendaTask.sortOrder
    )
    private var tasks: [AgendaTask]

    @State private var selectedTask: AgendaTask? = nil
    @State private var showTaskPicker = false
    @State private var showInterruptionPicker = false
    @State private var showStopDialog = false
    @State private var showHistory = false
    @State private var inBreak = false
    @State private var breakEndsAt: Date? = nil
    @State private var skipBreakAfterAbandon = false

    // A setup choice applies to this session without changing profile preferences.
    @State private var chosenSessionMinutes: Int?
    private var sessionMinutes: Int {
        chosenSessionMinutes ?? profileManager.activePreferences?.focusSessionMinutes ?? 25
    }
    private var breakMinutes: Int { profileManager.activePreferences?.breakMinutes ?? 10 }

    private var suggestedMinutes: Int? {
        let energy = profileManager.activePreferences?.currentEnergyLevel ?? 3
        let suggested = CognitiveProfile.suggestedFocusLength(
            in: modelContext,
            energyLevel: energy,
            profileID: profileManager.activeProfile?.clientID
        )
        return min(480, max(5, suggested))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                if notificationManager.focusSessionActive {
                    if notificationManager.focusSessionPaused {
                        // ── Paused session ──
                        pausedSessionContent()
                    } else if let endsAt = notificationManager.focusSessionEndsAt {
                        // ── Active session ──
                        activeSessionContent(endsAt: endsAt)
                    } else {
                        ProgressView("Restoring focus session…")
                    }

                } else if inBreak, let breakEnd = breakEndsAt, breakEnd > .now {
                    // ── Break phase ──
                    breakContent(breakEnd: breakEnd)

                } else {
                    // ── Setup / idle ──
                    setupContent()
                }

                Spacer()
            }
            .padding(.horizontal)
            .navigationTitle("Focus")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .sheet(isPresented: $showTaskPicker) {
                FocusTaskPickerSheet(selectedTask: $selectedTask)
                    .presentationDetents([.medium, .large])
            #if os(iOS)
            .presentationDragIndicator(.visible)
            #endif
            }
            .sheet(isPresented: $showInterruptionPicker) {
                InterruptionPickerSheet { reason in
                    notificationManager.recordInterruption(reason: reason)
                }
                #if os(iOS)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                #endif
            }
            .sheet(isPresented: $showHistory) {
                FocusSessionHistoryView(profileID: profileManager.activeProfile?.clientID)
                #if os(iOS)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                #endif
            }
            .confirmationDialog(
                "Stop this focus session?",
                isPresented: $showStopDialog,
                titleVisibility: .visible
            ) {
                Button("Abandon — interrupted", role: .destructive) {
                    abandonSession(reason: "Interrupted before completion")
                }
                Button("Abandon — changed priorities", role: .destructive) {
                    abandonSession(reason: "Changed priorities")
                }
                Button("Keep session", role: .cancel) {}
            } message: {
                Text("Abandoning preserves the session in history without counting it as completed.")
            }
        }
        // When a session ends naturally (focusSessionActive flips to false), start the break
        .onChange(of: notificationManager.focusSessionActive) { wasActive, isActive in
            if wasActive && !isActive && skipBreakAfterAbandon {
                skipBreakAfterAbandon = false
            } else if wasActive && !isActive && !inBreak {
                startBreak()
            }
        }
    }

    // MARK: - Sub-layouts

    @ViewBuilder
    private func activeSessionContent(endsAt: Date) -> some View {
        VStack(spacing: 28) {
            ActiveFocusRing(endsAt: endsAt, totalMinutes: sessionMinutes)

            if let task = selectedTask {
                Text(task.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                Text("Focus session active")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    notificationManager.pauseFocusSession()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .buttonStyle(.bordered)

                Button {
                    notificationManager.endFocusSession()
                    notificationManager.cancelHyperfocusWarning()
                    // Break starts via .onChange above.
                } label: {
                    Label("Finish now", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                showInterruptionPicker = true
            } label: {
                Label("I got interrupted", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .tint(.orange)

            Button("Abandon session", role: .destructive) {
                showStopDialog = true
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func pausedSessionContent() -> some View {
        VStack(spacing: 24) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.appAccent)
                .accessibilityHidden(true)

            Text("Focus session paused")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Paused time is excluded from the session duration.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                notificationManager.resumeFocusSession()
            } label: {
                Label("Resume focus", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(16)
            }
            .buttonStyle(.borderedProminent)

            HStack {
                Button("Finish now") {
                    notificationManager.endFocusSession()
                }
                .buttonStyle(.bordered)

                Button("Abandon", role: .destructive) {
                    showStopDialog = true
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func breakContent(breakEnd: Date) -> some View {
        VStack(spacing: 28) {
            BreakRing(endsAt: breakEnd, totalMinutes: breakMinutes)

            Text("Rest up. You earned it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Skip break") {
                inBreak = false
                breakEndsAt = nil
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            // After break ends naturally — handled by TimelineView in BreakRing calling back,
            // but we check it here too
        }
        .onReceive(
            Timer.publish(every: 5, on: .main, in: .common).autoconnect()
        ) { _ in
            if let end = breakEndsAt, .now >= end {
                inBreak = false
                breakEndsAt = nil
            }
        }
    }

    @ViewBuilder
    private func setupContent() -> some View {
        VStack(spacing: 24) {
            // Task picker row
            Button {
                showTaskPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selectedTask != nil ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.title3)
                        .foregroundStyle(selectedTask != nil ? Color.appAccent : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedTask?.title ?? "Choose a task (optional)")
                            .font(.subheadline)
                            .fontWeight(selectedTask != nil ? .medium : .regular)
                            .foregroundStyle(selectedTask != nil ? .primary : .secondary)
                        if let task = selectedTask {
                            HStack(spacing: 6) {
                                FrictionDots(level: task.frictionLevel)
                                Text("~\(task.totalEstimatedMinutes) min")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            // Duration display
            HStack {
                Label("\(sessionMinutes) min session · \(breakMinutes) min break", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper("Duration", value: Binding(
                    get: { sessionMinutes },
                    set: { chosenSessionMinutes = $0 }
                ), in: 5...480, step: 1)
                .labelsHidden()
                .accessibilityLabel("Focus duration, \(sessionMinutes) minutes")
            }

            if let suggested = suggestedMinutes, suggested != sessionMinutes {
                HStack {
                    Text("Suggested: \(suggested) min (based on your history)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Use \(suggested) min") {
                        chosenSessionMinutes = suggested
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Start button
            Button {
                startSession()
            } label: {
                Text("Start \(sessionMinutes) min focus")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(18)
                    .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)

            Button {
                showHistory = true
            } label: {
                Label("View History", systemImage: "chart.bar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func startSession() {
        notificationManager.startFocusSession(
            durationMinutes: sessionMinutes,
            taskTitle: selectedTask?.title ?? "",
            taskID: selectedTask?.clientID
        )
        if let task = selectedTask, task.hyperfocusRisk {
            notificationManager.scheduleHyperfocusWarning(taskTitle: task.title, afterMinutes: 45)
        }
    }

    private func startBreak() {
        inBreak = true
        breakEndsAt = Date.now.addingTimeInterval(Double(breakMinutes) * 60)
    }

    private func abandonSession(reason: String) {
        skipBreakAfterAbandon = true
        if !notificationManager.abandonFocusSession(reason: reason) {
            skipBreakAfterAbandon = false
        }
    }
}


// MARK: - Active Focus Ring

struct ActiveFocusRing: View {
    let endsAt: Date
    let totalMinutes: Int
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 220
    @ScaledMetric(relativeTo: .largeTitle) private var ringLineWidth: CGFloat = 14

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let totalSeconds = Double(totalMinutes) * 60
            let remaining = max(0, endsAt.timeIntervalSince(context.date))
            let progress = min(1, 1.0 - (remaining / totalSeconds))
            let isUrgent = remaining < 120  // Last 2 min

            ZStack {
                // Track
                Circle()
                    .stroke(Color.appAccent.opacity(0.12), lineWidth: ringLineWidth)

                // Progress arc
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        isUrgent ? Color.orange : Color.appAccent,
                        style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                // Time display
                VStack(spacing: 4) {
                    Text(formatTime(remaining))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(isUrgent ? .orange : .primary)

                    Text("remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: ringSize, height: ringSize)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}


// MARK: - Break Ring

struct BreakRing: View {
    let endsAt: Date
    let totalMinutes: Int
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 200
    @ScaledMetric(relativeTo: .largeTitle) private var ringLineWidth: CGFloat = 14

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let totalSeconds = Double(totalMinutes) * 60
            let remaining = max(0, endsAt.timeIntervalSince(context.date))
            let progress = min(1, 1.0 - (remaining / totalSeconds))

            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.12), lineWidth: ringLineWidth)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                VStack(spacing: 4) {
                    Text(formatTime(remaining))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.green)

                    Text("break")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: ringSize, height: ringSize)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}


// MARK: - Task Picker Sheet

struct FocusTaskPickerSheet: View {

    @Binding var selectedTask: AgendaTask?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<AgendaTask> { !$0.isComplete && !$0.isAbandoned },
        sort: \AgendaTask.sortOrder
    )
    private var tasks: [AgendaTask]

    // Sort by ndPriorityScore descending so the best match is at top
    private var sortedTasks: [AgendaTask] {
        tasks.filter { $0.isActionable(in: modelContext) }
            .sorted { $0.ndPriorityScore > $1.ndPriorityScore }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedTask = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("No specific task")
                                .foregroundStyle(.secondary)
                            Spacer()
                            if selectedTask == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Tasks") {
                    ForEach(sortedTasks) { task in
                        Button {
                            selectedTask = task
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)

                                    HStack(spacing: 8) {
                                        FrictionDots(level: task.frictionLevel)
                                        Text("~\(task.totalEstimatedMinutes) min")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if !task.contextTag.isEmpty {
                                            Text(task.contextTag)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                Spacer()

                                if selectedTask?.clientID == task.clientID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Pick a task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
