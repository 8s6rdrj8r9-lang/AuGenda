// SmartSuggestView.swift
// AUDHD Agenda App
//
// "What can I do right now?" — matches tasks to current energy level
// using ndPriorityScore (interest + priority - friction - energy cost).
// Shows one task at a time with a "give me another" escape hatch.
// Embedded as the "For Now" segment inside TaskBacklogView.

import SwiftUI
import SwiftData

// MARK: - Smart Suggest View

struct SmartSuggestView: View {

    @EnvironmentObject private var profileManager: ActiveProfileManager
    @Query(filter: #Predicate<Task> { !$0.isComplete && !$0.isAbandoned })
    private var allTasks: [Task]

    @State private var skipIndex: Int = 0
    @State private var selectedTask: Task? = nil
    @State private var cardOffset: CGFloat = 0
    @State private var cardOpacity: Double = 1

    private var energyLevel: Int { profileManager.activePreferences?.currentEnergyLevel ?? 3 }
    private var activeProfileID: UUID? { profileManager.activeProfile?.clientID }

    private var eligible: [Task] {
        let profileID = activeProfileID
        return allTasks
            .filter { task in
                // Assignment filter: only show tasks for this profile or unassigned legacy tasks
                let assignedOK: Bool = {
                    if let assignedID = task.assignedToProfileID {
                        return assignedID == profileID
                    }
                    return true
                }()
                return assignedOK &&
                    task.isActionable &&
                    task.frictionLevel <= energyLevel &&
                    task.energyRequired <= energyLevel
            }
            .sorted { $0.ndPriorityScore > $1.ndPriorityScore }
    }

    private var currentTask: Task? {
        guard !eligible.isEmpty else { return nil }
        return eligible[skipIndex % eligible.count]
    }

    var body: some View {
        VStack(spacing: 0) {

            // Context header
            HStack {
                Image(systemName: energyIcon)
                    .foregroundStyle(energyColor)
                Text("At \(energyLabel) energy — \(eligible.count) task\(eligible.count == 1 ? "" : "s") match")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if let task = currentTask {
                SuggestedTaskCard(task: task) {
                    selectedTask = task
                }
                .padding(.horizontal)
                .offset(x: cardOffset)
                .opacity(cardOpacity)

                VStack(spacing: 12) {
                    if eligible.count > 1 {
                        Button("Give me another") {
                            animateToNext()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 20)
                    }

                    Text("Sorted by interest, priority, and friction")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            } else {
                EmptySuggestView(energyLevel: energyLevel)
                    .padding(.top, 60)
            }

            Spacer()
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task)
        }
    }

    // MARK: - Helpers

    private func animateToNext() {
        withAnimation(.easeIn(duration: 0.15)) {
            cardOffset = -40
            cardOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            skipIndex = (skipIndex + 1) % max(1, eligible.count)
            cardOffset = 40
            withAnimation(.easeOut(duration: 0.2)) {
                cardOffset = 0
                cardOpacity = 1
            }
        }
    }

    private var energyLabel: String {
        switch energyLevel {
        case 1: return "survival"
        case 2: return "low"
        case 3: return "moderate"
        case 4: return "good"
        default: return "high"
        }
    }

    private var energyIcon: String {
        switch energyLevel {
        case 1, 2: return "battery.25percent"
        case 3: return "battery.50percent"
        default: return "battery.100percent"
        }
    }

    private var energyColor: Color {
        switch energyLevel {
        case 1, 2: return .orange
        case 3: return .yellow
        default: return .green
        }
    }
}


// MARK: - Suggested Task Card

struct SuggestedTaskCard: View {
    let task: Task
    let onTap: () -> Void

    private var firstPendingStep: TaskStep? {
        task.steps?
            .filter { !$0.isComplete }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {

                // Title
                Text(task.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Metadata row
                HStack(spacing: 14) {
                    Label("~\(task.totalEstimatedMinutes) min", systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    FrictionDots(level: task.frictionLevel)

                    Spacer()

                    if !task.contextTag.isEmpty {
                        Text(task.contextTag)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }

                // First step hint
                if let step = firstPendingStep {
                    Divider()
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(Color.appAccent)
                            .font(.subheadline)
                        Text("Start with: \(step.title)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Flags
                HStack(spacing: 10) {
                    if task.needsBodyDouble {
                        Label("Body double helps", systemImage: "person.2")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.1), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    if task.hyperfocusRisk {
                        Label("Hyperfocus risk", systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.1), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.appAccent.opacity(0.35), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Empty Suggest State

struct EmptySuggestView: View {
    let energyLevel: Int

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Nothing matches right now")
                .font(.headline)
                .foregroundStyle(.primary)

            Text(
                energyLevel <= 2
                    ? "Your energy is low — that's okay. Rest is valid too."
                    : "Try raising your energy level or lowering friction on some tasks."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
    }
}
