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
#if os(iOS)
import UIKit
#endif

// MARK: - Task Detail View

struct TaskDetailView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileManager: ActiveProfileManager

    let task: AgendaTask

    @State private var showJustStart = false
    @State private var showEdit = false
    @State private var completedAnimation = false

    // AI enrichment
    @AppStorage("ai.enabled") private var aiEnabled: Bool = false
    @AppStorage("ai.showEnrichButtons") private var showEnrichButtons: Bool = true
    @AppStorage("ai.activeProvider") private var activeProviderRaw: String = ""
    @StateObject private var personalization = PersonalizationStore.shared

    @State private var isEnriching = false
    @State private var pendingEnrichment: TaskEnrichment? = nil
    @State private var showEnrichmentPreview = false
    @State private var enrichmentError: String? = nil

    /// Resolves the friction label text from the active profile's language preference.
    private var frictionLabelText: String {
        switch profileManager.activePreferences?.frictionLabel ?? .friction {
        case .friction: return "Start friction"
        case .effort:   return "Effort level"
        case .energy:   return "Energy cost"
        }
    }

    private var canEnrich: Bool {
        aiEnabled && showEnrichButtons && !task.excludeFromAI && !activeProviderRaw.isEmpty
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

                        // AI enrichment
                        if canEnrich {
                            Button {
                                Task { await runEnrichment() }
                            } label: {
                                HStack(spacing: 8) {
                                    if isEnriching {
                                        ProgressView().controlSize(.small)
                                        Text("Enriching…")
                                    } else {
                                        Image(systemName: "sparkles")
                                        Text("Enrich with AI")
                                    }
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.purple)
                            }
                            .buttonStyle(.plain)
                            .disabled(isEnriching)
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
                ToolbarItem(placement: {
                    #if os(iOS)
                    return .navigationBarLeading
                    #else
                    return .cancellationAction
                    #endif
                }()) {
                    Button {
                        showEdit = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
                ToolbarItem(placement: {
                    #if os(iOS)
                    return .navigationBarTrailing
                    #else
                    return .primaryAction
                    #endif
                }()) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showJustStart) {
                JustStartView(task: task)
                    .presentationDetents([.medium])
            #if os(iOS)
            .presentationDragIndicator(.visible)
            #endif
            }
            .sheet(isPresented: $showEdit) {
                AddTaskView(isPresented: $showEdit, editingTask: task)
                #if os(iOS)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                #endif
            }
            .sheet(isPresented: $showEnrichmentPreview, onDismiss: { pendingEnrichment = nil }) {
                if let enrichment = pendingEnrichment {
                    EnrichmentPreviewSheet(
                        task: task,
                        enrichment: enrichment,
                        allowInterestInference: personalization.allowInterestInference,
                        onApply: {
                            applyEnrichment(enrichment)
                            showEnrichmentPreview = false
                        },
                        onDismiss: { showEnrichmentPreview = false }
                    )
                    #if os(iOS)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                    #endif
                }
            }
            .alert(
                "Enrichment failed",
                isPresented: Binding(
                    get: { enrichmentError != nil },
                    set: { if !$0 { enrichmentError = nil } }
                ),
                presenting: enrichmentError
            ) { _ in
                Button("OK", role: .cancel) { enrichmentError = nil }
            } message: { msg in
                Text(msg)
            }
        }
    }

    // MARK: - Actions

    @MainActor
    private func runEnrichment() async {
        guard let provider = AIProvider(rawValue: activeProviderRaw),
              let enricher = AIEnricherRegistry.enricher(for: provider) else { return }

        isEnriching = true

        let neurotypes = profileManager.activeProfile?.neurotypes.map(\.displayName) ?? []
        let prefs = profileManager.activePreferences
        let mode: DensityMode = prefs?.densityPinned
            ?? DensityMode.autoFrom(energyLevel: prefs?.currentEnergyLevel ?? 3)
        let personalizationContext = personalization.snapshot()

        let context = EnrichmentContext(
            rawTitle: task.title,
            userNote: task.notes.isEmpty ? nil : task.notes,
            neurotypes: neurotypes,
            currentDensity: mode.rawValue,
            personalization: personalizationContext
        )

        do {
            let result = try await enricher.enrich(context: context)
            pendingEnrichment = result
            showEnrichmentPreview = true
        } catch {
            enrichmentError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }

        isEnriching = false
    }

    private func applyEnrichment(_ enrichment: TaskEnrichment) {
        if let t = enrichment.title, !t.isEmpty { task.title = t }
        if let desc = enrichment.taskDescription, !desc.isEmpty, task.notes.isEmpty {
            task.notes = desc
        }
        if let f = enrichment.friction      { task.frictionLevel   = f }
        if let e = enrichment.energy        { task.energyRequired  = e }
        if let s = enrichment.sensoryLoad   { task.sensoryLoad     = s }
        if let c = enrichment.socialLoad    { task.socialLoad      = c }
        if let i = enrichment.initiationCost { task.initiationCost = i }
        if let n = enrichment.interest, personalization.allowInterestInference {
            task.interestLevel = n
        }
        if let mins = enrichment.estimatedMinutes { task.estimatedMinutes = mins }
        if let ctx = enrichment.contextTag, !ctx.isEmpty { task.contextTag = ctx }

        if let subTasks = enrichment.subTasks, !subTasks.isEmpty {
            let existingCount = task.steps?.count ?? 0
            for (i, stepTitle) in subTasks.enumerated() {
                let step = TaskStep(title: stepTitle, sortOrder: existingCount + i)
                step.parentTask = task
                modelContext.insert(step)
            }
        }

        task.updatedAt = .now
        try? modelContext.save()
        personalization.recordEnrichment(title: task.title, band: task.difficultyBand)
    }

    private func markComplete() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        #endif
        withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
            completedAnimation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                completedAnimation = false
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            ActivityLog.recordCompletion()
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


// MARK: - Enrichment Preview Sheet

struct EnrichmentPreviewSheet: View {

    let task: AgendaTask
    let enrichment: TaskEnrichment
    let allowInterestInference: Bool
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                // Confidence row
                if let conf = enrichment.confidence {
                    Section {
                        HStack {
                            Text("AI confidence")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(conf * 100))%")
                                .fontWeight(.medium)
                                .monospacedDigit()
                                .foregroundStyle(conf >= 0.7 ? .green : conf >= 0.4 ? .orange : .red)
                        }
                    }
                }

                // Field changes
                let changes = changeItems
                if !changes.isEmpty {
                    Section("Proposed changes") {
                        ForEach(changes, id: \.label) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Text(item.label)
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 110, alignment: .leading)
                                Spacer(minLength: 0)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(item.after)
                                        .fontWeight(.medium)
                                    if let before = item.before {
                                        Text(before)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                            .strikethrough()
                                    }
                                }
                            }
                        }
                    }
                }

                // Sub-tasks
                if let subTasks = enrichment.subTasks, !subTasks.isEmpty {
                    Section("Suggested steps (\(subTasks.count) new)") {
                        ForEach(subTasks, id: \.self) { step in
                            Label(step, systemImage: "circle")
                                .foregroundStyle(.primary)
                        }
                    }
                }

                // Description (only shown when current notes are empty)
                if let desc = enrichment.taskDescription, !desc.isEmpty, task.notes.isEmpty {
                    Section("Suggested notes") {
                        Text(desc)
                            .foregroundStyle(.secondary)
                    }
                }

                if changes.isEmpty
                    && (enrichment.subTasks ?? []).isEmpty
                    && (enrichment.taskDescription == nil || !task.notes.isEmpty) {
                    Section {
                        Text("No changes suggested — task metadata looks accurate.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("AI Proposal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        onApply()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss", action: onDismiss)
                }
            }
        }
    }

    private struct ChangeItem {
        let label: String
        let before: String?
        let after: String
    }

    private var changeItems: [ChangeItem] {
        var items: [ChangeItem] = []
        if let t = enrichment.title, !t.isEmpty, t != task.title {
            items.append(.init(label: "Title", before: task.title, after: t))
        }
        if let f = enrichment.friction, f != task.frictionLevel {
            items.append(.init(label: "Friction", before: "\(task.frictionLevel)", after: "\(f)"))
        }
        if let e = enrichment.energy, e != task.energyRequired {
            items.append(.init(label: "Energy", before: "\(task.energyRequired)", after: "\(e)"))
        }
        if let s = enrichment.sensoryLoad, s != task.sensoryLoad {
            items.append(.init(label: "Sensory load", before: "\(task.sensoryLoad)", after: "\(s)"))
        }
        if let c = enrichment.socialLoad, c != task.socialLoad {
            items.append(.init(label: "Social load", before: "\(task.socialLoad)", after: "\(c)"))
        }
        if let i = enrichment.initiationCost, i != task.initiationCost {
            items.append(.init(label: "Initiation cost", before: "\(task.initiationCost)", after: "\(i)"))
        }
        if let n = enrichment.interest, n != task.interestLevel, allowInterestInference {
            items.append(.init(label: "Interest", before: "\(task.interestLevel)", after: "\(n)"))
        }
        if let mins = enrichment.estimatedMinutes, mins != task.estimatedMinutes {
            items.append(.init(label: "Est. time",
                               before: "\(task.estimatedMinutes)m", after: "\(mins)m"))
        }
        if let ctx = enrichment.contextTag, !ctx.isEmpty, ctx != task.contextTag {
            items.append(.init(label: "Context",
                               before: task.contextTag.isEmpty ? nil : task.contextTag,
                               after: ctx))
        }
        return items
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
    let task: AgendaTask

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
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
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
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            dismiss()
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)

                        Button("Keep going") {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
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
            #if os(iOS)
            .presentationDragIndicator(.visible)
            #endif
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
