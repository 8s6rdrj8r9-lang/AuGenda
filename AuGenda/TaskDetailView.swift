// TaskDetailView.swift
// AUDHD Agenda App
//
// Full task detail sheet:
// - Metadata: estimate, friction, interest, energy, context, flags
// - Waiting-on indicator (prominent yellow banner)
// - Steps list with per-step completion
// - "Just Start" button for high-friction tasks → JustStartView
// - Quick complete action

import SwiftUI
import SwiftData

// MARK: - Task Detail View

struct TaskDetailView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileManager: ActiveProfileManager

    let task: Task

    @State private var showJustStart = false
    @State private var showEdit = false
    @State private var completedAnimation = false

    /// Resolves the friction label text from the active profile's language preference.
    private var frictionLabelText: String {
        switch profileManager.activePreferences?.frictionLabel ?? .friction {
        case .friction: return "Start friction"
        case .effort:   return "Effort level"
        case .energy:   return "Energy cost"
        }
    }

    private var sortedSteps: [TaskStep] {
        (task.steps ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var completedStepCount: Int {
        sortedSteps.filter { $0.isComplete }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Waiting on banner (if blocked) ──
                    if !task.waitingOn.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.badge.questionmark.fill")
                                .foregroundStyle(.yellow)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Waiting on")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.yellow)
                                Text(task.waitingOn)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.yellow.opacity(0.3), lineWidth: 1)
                        )
                    }

                    // ── Metadata grid ──
                    HStack(spacing: 16) {
                        MetaBadge(
                            icon: "clock",
                            label: "~\(task.totalEstimatedMinutes) min"
                        )
                        MetaBadge(
                            icon: "bolt",
                            label: energyLabel(task.energyRequired)
                        )
                        if !task.contextTag.isEmpty {
                            MetaBadge(icon: "tag", label: task.contextTag)
                        }
                    }

                    // ── Friction + interest visual ──
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(frictionLabelText)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            FrictionDots(level: task.frictionLevel)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Interest")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            InterestPips(level: task.interestLevel)
                        }
                    }

                    // ── Flags ──
                    let flags: [(Bool, String, String, Color)] = [
                        (task.needsBodyDouble, "person.2", "Body double helps", .blue),
                        (task.hyperfocusRisk, "exclamationmark.triangle", "Hyperfocus risk", .orange)
                    ]
                    let activeFlags = flags.filter { $0.0 }
                    if !activeFlags.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(activeFlags, id: \.1) { _, icon, label, color in
                                Label(label, systemImage: icon)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(color.opacity(0.1), in: Capsule())
                                    .foregroundStyle(color)
                            }
                        }
                    }

                    // ── Notes ──
                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }

                    // ── Steps ──
                    if !sortedSteps.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Steps")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(completedStepCount)/\(sortedSteps.count)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            ForEach(sortedSteps) { step in
                                TaskStepRow(step: step) {
                                    try? modelContext.save()
                                }
                            }
                        }
                    }

                    Spacer(minLength: 24)

                    // ── Action buttons ──
                    VStack(spacing: 12) {

                        // Just Start — shown for higher-friction tasks
                        if task.frictionLevel >= 3 && !task.isComplete {
                            Button {
                                showJustStart = true
                            } label: {
                                Label("Just Start", systemImage: "bolt.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(16)
                                    .background(Color.appAccent.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                                    .foregroundStyle(Color.appAccent)
                            }
                            .buttonStyle(.plain)
                        }

                        // Mark complete
                        if !task.isComplete {
                            Button {
                                markComplete()
                            } label: {
                                Label("Mark Complete", systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(16)
                                    .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                            .scaleEffect(completedAnimation ? 1.04 : 1.0)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(task.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showJustStart) {
                JustStartView(task: task)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Actions

    private func markComplete() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
            completedAnimation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                completedAnimation = false
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            task.isComplete = true
            task.completedAt = .now
            task.updatedAt = .now
            try? modelContext.save()
            dismiss()
        }
    }

    private func energyLabel(_ level: Int) -> String {
        switch level {
        case 1: return "low energy"
        case 2: return "med energy"
        default: return "high energy"
        }
    }
}


// MARK: - Meta Badge

struct MetaBadge: View {
    let icon: String
    let label: String

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.secondary)
    }
}


// MARK: - Task Step Row

struct TaskStepRow: View {
    @Environment(\.modelContext) private var modelContext
    let step: TaskStep
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(duration: 0.25)) {
                    step.isComplete.toggle()
                }
                onToggle()
            } label: {
                Image(systemName: step.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(step.isComplete ? Color.appAccent : .secondary)
            }
            .buttonStyle(.plain)

            Text(step.title)
                .font(.subheadline)
                .strikethrough(step.isComplete)
                .foregroundStyle(step.isComplete ? .secondary : .primary)

            Spacer()

            if step.estimatedMinutes > 0 {
                Text("\(step.estimatedMinutes)m")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}


// MARK: - Just Start View

struct JustStartView: View {

    @Environment(\.dismiss) private var dismiss
    let task: Task

    @State private var committed = false
    @State private var startedAt: Date? = nil

    private var firstPendingStep: String {
        task.steps?
            .filter { !$0.isComplete }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first?.title ?? task.title
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if !committed {
                // ── Pre-commit: explain the deal ──
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("Just this one thing")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("You only need to do 2 minutes. That's it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text(firstPendingStep)
                        .font(.title3)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

                    VStack(spacing: 12) {
                        Button {
                            withAnimation(.spring()) {
                                committed = true
                                startedAt = .now
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            Text("I'll try it — 2 minutes")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)

                        Button("Not right now") {
                            dismiss()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .transition(.opacity.combined(with: .move(edge: .bottom)))

            } else {
                // ── Committed: show elapsed timer ──
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("You're doing it")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(firstPendingStep)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if let start = startedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let elapsed = context.date.timeIntervalSince(start)
                            let twoMinutes = elapsed >= 120

                            VStack(spacing: 6) {
                                Text(formatElapsed(elapsed))
                                    .font(.system(size: 56, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(twoMinutes ? .green : Color.appAccent)

                                if twoMinutes {
                                    Text("Two minutes done. Keep going or stop — both are fine.")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                        .multilineTextAlignment(.center)
                                        .transition(.opacity)
                                }
                            }
                        }
                    }

                    HStack(spacing: 14) {
                        Button("That's enough") {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismiss()
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)

                        Button("Keep going") {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            dismiss()
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()
        }
        .padding()
        .presentationDragIndicator(.visible)
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
