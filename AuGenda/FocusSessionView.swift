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

import SwiftUI
import SwiftData

// MARK: - Focus Session View

struct FocusSessionView: View {

    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var profileManager: ActiveProfileManager
    @Query(
        filter: #Predicate<Task> { !$0.isComplete && !$0.isAbandoned },
        sort: \Task.sortOrder
    )
    private var tasks: [Task]

    @State private var selectedTask: Task? = nil
    @State private var showTaskPicker = false
    @State private var inBreak = false
    @State private var breakEndsAt: Date? = nil

    private var sessionMinutes: Int { profileManager.activePreferences?.focusSessionMinutes ?? 25 }
    private var breakMinutes: Int { profileManager.activePreferences?.breakMinutes ?? 10 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                if notificationManager.focusSessionActive,
                   let endsAt = notificationManager.focusSessionEndsAt {
                    // ── Active session ──
                    activeSessionContent(endsAt: endsAt)

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
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showTaskPicker) {
                FocusTaskPickerSheet(selectedTask: $selectedTask)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        // When a session ends naturally (focusSessionActive flips to false), start the break
        .onChange(of: notificationManager.focusSessionActive) { wasActive, isActive in
            if wasActive && !isActive && !inBreak {
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

            Button {
                notificationManager.endFocusSession()
                notificationManager.cancelHyperfocusWarning()
                // Break starts via .onChange above
            } label: {
                Text("End early")
                    .font(.subheadline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.red)
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
                NavigationLink(destination: SettingsView()) {
                    Text("adjust")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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
        }
    }

    // MARK: - Actions

    private func startSession() {
        notificationManager.startFocusSession(
            durationMinutes: sessionMinutes,
            taskTitle: selectedTask?.title ?? ""
        )
        if let task = selectedTask, task.hyperfocusRisk {
            notificationManager.scheduleHyperfocusWarning(taskTitle: task.title, afterMinutes: 45)
        }
    }

    private func startBreak() {
        inBreak = true
        breakEndsAt = Date.now.addingTimeInterval(Double(breakMinutes) * 60)
    }
}


// MARK: - Active Focus Ring

struct ActiveFocusRing: View {
    let endsAt: Date
    let totalMinutes: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let totalSeconds = Double(totalMinutes) * 60
            let remaining = max(0, endsAt.timeIntervalSince(context.date))
            let progress = min(1, 1.0 - (remaining / totalSeconds))
            let isUrgent = remaining < 120  // Last 2 min

            ZStack {
                // Track
                Circle()
                    .stroke(Color.appAccent.opacity(0.12), lineWidth: 14)

                // Progress arc
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        isUrgent ? Color.orange : Color.appAccent,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                // Time display
                VStack(spacing: 4) {
                    Text(formatTime(remaining))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isUrgent ? .orange : .primary)

                    Text("remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 220, height: 220)
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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let totalSeconds = Double(totalMinutes) * 60
            let remaining = max(0, endsAt.timeIntervalSince(context.date))
            let progress = min(1, 1.0 - (remaining / totalSeconds))

            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.12), lineWidth: 14)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)

                VStack(spacing: 4) {
                    Text(formatTime(remaining))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.green)

                    Text("break")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 200)
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

    @Binding var selectedTask: Task?
    @Environment(\.dismiss) private var dismiss
    @Query(
        filter: #Predicate<Task> { !$0.isComplete && !$0.isAbandoned },
        sort: \Task.sortOrder
    )
    private var tasks: [Task]

    // Sort by ndPriorityScore descending so the best match is at top
    private var sortedTasks: [Task] {
        tasks.filter { $0.isActionable }
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
