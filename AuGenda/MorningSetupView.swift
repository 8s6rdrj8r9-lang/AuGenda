// MorningSetupView.swift
// AuGenda
//
// Daily morning setup wizard — helps Arthur plan his day based on today's energy.
// Shows on first launch of each day (gated by UserDefaults).

import SwiftUI
import SwiftData

struct MorningSetupView: View {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileManager: ActiveProfileManager

    @Query(
        filter: #Predicate<AgendaTask> { !$0.isComplete && !$0.isAbandoned },
        sort: \AgendaTask.sortOrder
    )
    private var allTasks: [AgendaTask]

    @Query(sort: \Block.sortOrder)
    private var allBlocks: [Block]

    @State private var selectedEnergy: Int = 3
    @State private var step: MorningSetupStep = .energy

    enum MorningSetupStep {
        case energy, suggestions, building
    }

    private var actionableTasks: [AgendaTask] {
        allTasks.filter { $0.isActionable }
            .sorted { $0.ndPriorityScore > $1.ndPriorityScore }
    }

    private var topTasks: [AgendaTask] {
        Array(actionableTasks.prefix(3))
    }

    private var suggestedBlocks: [Block] {
        let energy = selectedEnergy
        return allBlocks.filter { !$0.isComplete }
            .prefix(energy >= 4 ? 4 : energy >= 3 ? 3 : 2)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: step == .energy ? 0.33 : step == .suggestions ? 0.66 : 1.0)
                    .tint(Color.appAccent)
                    .padding(.horizontal)
                    .padding(.top, 8)

                ScrollView {
                    VStack(spacing: Tokens.Spacing.xl) {
                        switch step {
                        case .energy:
                            energyStep
                        case .suggestions:
                            suggestionsStep
                        case .building:
                            buildingStep
                        }
                    }
                    .padding(.horizontal, Tokens.Spacing.xl)
                    .padding(.vertical, Tokens.Spacing.lg)
                }
            }
            .navigationTitle("Morning Setup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        markCompleted()
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            selectedEnergy = profileManager.activePreferences?.currentEnergyLevel ?? 3
        }
    }

    // MARK: - Energy Step

    private var energyStep: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xl) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                Text("Good morning")
                    .font(Tokens.Typography.h1)
                    .foregroundColor(Color.appTextPrimary)
                Text("What's your energy today?")
                    .font(Tokens.Typography.body)
                    .foregroundColor(Color.appTextSecondary)
            }

            VStack(spacing: Tokens.Spacing.sm) {
                ForEach(EnergyLevel.allCases) { level in
                    Button {
                        selectedEnergy = level.rawValue
                    } label: {
                        HStack {
                            Text(level.emoji)
                            Text(level.label)
                                .font(Tokens.Typography.body)
                                .fontWeight(.medium)
                            Spacer()
                            if selectedEnergy == level.rawValue {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                        .padding(Tokens.Spacing.base)
                        .background(
                            selectedEnergy == level.rawValue
                                ? Color.appAccent.opacity(0.15)
                                : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: Tokens.Border.radiusMedium)
                        )
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                withAnimation {
                    step = .suggestions
                }
            } label: {
                Text("Next")
                    .font(Tokens.Typography.label)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Tokens.Spacing.base)
                    .background(Color.appAccent, in: RoundedRectangle(cornerRadius: Tokens.Border.radiusLarge))
                    .foregroundColor(.black)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Suggestions Step

    private var suggestionsStep: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xl) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                Text("Plan for today")
                    .font(Tokens.Typography.h1)
                    .foregroundColor(Color.appTextPrimary)
                Text("Based on your energy, here are suggestions.")
                    .font(Tokens.Typography.body)
                    .foregroundColor(Color.appTextSecondary)
            }

            if !suggestedBlocks.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
                    Text("Suggested blocks")
                        .font(Tokens.Typography.label)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.appTextSecondary)

                    ForEach(suggestedBlocks) { block in
                        HStack(spacing: Tokens.Spacing.md) {
                            Image(systemName: block.icon)
                                .foregroundColor(Color.appAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(block.displayName)
                                    .font(Tokens.Typography.body)
                                    .fontWeight(.medium)
                                Text("\(block.totalTaskCount) tasks")
                                    .font(Tokens.Typography.caption)
                                    .foregroundColor(Color.appTextSecondary)
                            }
                            Spacer()
                        }
                        .padding(Tokens.Spacing.base)
                        .background(Color.appBackgroundSecondary, in: RoundedRectangle(cornerRadius: Tokens.Border.radiusMedium))
                    }
                }
            }

            if !topTasks.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
                    Text("Top priorities")
                        .font(Tokens.Typography.label)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.appTextSecondary)

                    ForEach(topTasks) { task in
                        HStack(spacing: Tokens.Spacing.md) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(Tokens.Typography.body)
                                    .fontWeight(.medium)
                                HStack(spacing: 6) {
                                    FrictionDots(level: task.frictionLevel)
                                    Text("~\(task.totalEstimatedMinutes) min")
                                        .font(Tokens.Typography.caption)
                                        .foregroundColor(Color.appTextSecondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(Tokens.Spacing.base)
                        .background(Color.appBackgroundSecondary, in: RoundedRectangle(cornerRadius: Tokens.Border.radiusMedium))
                    }
                }
            }

            Button {
                buildDay()
            } label: {
                Text("Build my day")
                    .font(Tokens.Typography.label)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Tokens.Spacing.base)
                    .background(Color.appAccent, in: RoundedRectangle(cornerRadius: Tokens.Border.radiusLarge))
                    .foregroundColor(.black)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Building Step

    private var buildingStep: some View {
        VStack(spacing: Tokens.Spacing.xl) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(Color.appAccent)

            VStack(spacing: Tokens.Spacing.sm) {
                Text("Your day is set")
                    .font(Tokens.Typography.h1)
                    .foregroundColor(Color.appTextPrimary)
                Text("Energy level saved, top tasks ready.")
                    .font(Tokens.Typography.body)
                    .foregroundColor(Color.appTextSecondary)
            }

            Button {
                markCompleted()
                isPresented = false
            } label: {
                Text("Done")
                    .font(Tokens.Typography.label)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Tokens.Spacing.base)
                    .background(Color.appAccent, in: RoundedRectangle(cornerRadius: Tokens.Border.radiusLarge))
                    .foregroundColor(.black)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func buildDay() {
        guard let prefs = profileManager.activePreferences else { return }
        prefs.currentEnergyLevel = selectedEnergy
        prefs.updatedAt = .now
        do {
            try modelContext.save()
        } catch {
            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
        }
        withAnimation {
            step = .building
        }
    }

    private func markCompleted() {
        UserDefaults.standard.set(Date.now, forKey: "morningSetup.lastDate")
    }
}
