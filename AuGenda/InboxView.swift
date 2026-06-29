// InboxView.swift
// AuGenda
//
// Mandatory review queue for brain-dump captures.
// AI suggestions are shown for user review — nothing becomes a task
// until the user taps "Add to tasks." User always confirms.

import SwiftUI
import SwiftData

// MARK: - Inbox View

struct InboxView: View {

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileManager: ActiveProfileManager

    @Query(
        filter: #Predicate<InboxItem> { $0.stateRaw == "unprocessed" },
        sort: \InboxItem.createdAt
    )
    private var unprocessed: [InboxItem]

    @State private var reviewItem: InboxItem? = nil
    @State private var showBrainDump: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if unprocessed.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(unprocessed) { item in
                                InboxItemRow(item: item) {
                                    reviewItem = item
                                }
                            }
                            .onDelete { indexSet in
                                for i in indexSet {
                                    unprocessed[i].state = .archived
                                }
                                do {
                                    try modelContext.save()
                                } catch {
                                    ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
                                }
                            }
                        } header: {
                            HStack {
                                Text("Needs review")
                                Spacer()
                                Text("\(unprocessed.count)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.appAccent.opacity(0.15), in: Capsule())
                                    .foregroundStyle(Color.appAccent)
                            }
                        } footer: {
                            Text("Review each capture and tap \"Add to tasks\" to organize it. Swipe left to discard.")
                                .font(.caption)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Inbox")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: {
                    #if os(iOS)
                    return .navigationBarTrailing
                    #else
                    return .primaryAction
                    #endif
                }()) {
                    Button {
                        showBrainDump = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Color.appAccent)
                    }
                    .accessibilityLabel("Brain dump — capture something")
                }
            }
            .sheet(item: $reviewItem) { item in
                InboxItemReviewSheet(item: item)
                    #if os(iOS)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    #endif
            }
            .sheet(isPresented: $showBrainDump) {
                BrainDumpView(isPresented: $showBrainDump)
                    #if os(iOS)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    #endif
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 52))
                .foregroundStyle(.quaternary)

            VStack(spacing: 6) {
                Text("Inbox clear")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text("Brain dumps land here.\nReview them at your own pace.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showBrainDump = true
            } label: {
                Label("Capture something", systemImage: "square.and.pencil")
                    .fontWeight(.medium)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.appAccent.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.appAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(32)
    }
}

// MARK: - Inbox Item Row

struct InboxItemRow: View {
    let item: InboxItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: item.source == .voiceCapture
                          ? "mic.fill" : "text.bubble.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text(item.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if item.hasAISuggestions {
                        Label("AI ready", systemImage: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(Color.warmEmber)
                            .labelStyle(.iconOnly)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }

                Text(item.rawCapture)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.source == .voiceCapture ? "Dictated" : "Captured") note: \(item.rawCapture)")
        .accessibilityHint(item.hasAISuggestions
            ? "AI suggestions ready. Opens review to add to tasks."
            : "Opens review to add to tasks.")
    }
}

// MARK: - Inbox Item Review Sheet

struct InboxItemReviewSheet: View {

    let item: InboxItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileManager: ActiveProfileManager

    // Editable fields pre-filled from AI suggestions if present
    @State private var title: String = ""
    @State private var frictionLevel: Int = 3
    @State private var energyRequired: Int = 2
    @State private var initiationCost: Int = 0
    @State private var sensoryLoad: Int = 0
    @State private var socialLoad: Int = 0
    @State private var contextTag: String = ""
    @State private var showDifficultyDetail: Bool = false

    @State private var enrichState: ReviewEnrichState = .idle

    @AppStorage("ai.enabled") private var aiEnabled: Bool = false
    @AppStorage("ai.activeProvider") private var activeProviderRaw: String = ""
    @AppStorage("ai.showEnrichButtons") private var showEnrichButtons: Bool = true

    private enum ReviewEnrichState: Equatable {
        case idle
        case running
        case done(summary: String)
        case failed(message: String)
    }

    private var canEnrich: Bool {
        aiEnabled
            && !activeProviderRaw.isEmpty
            && showEnrichButtons
            && !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var previewRank: Int {
        DifficultyEngine.rank(
            friction: frictionLevel,
            energy: energyRequired,
            sensoryLoad: sensoryLoad,
            socialLoad: socialLoad,
            initiationCost: initiationCost,
            interest: 3
        )
    }

    private var previewBand: DifficultyBand { DifficultyBand(rank: previewRank) }

    var body: some View {
        NavigationStack {
            Form {
                // Raw capture — reference only, not editable
                Section {
                    Text(item.rawCapture)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } header: {
                    Label(item.source == .voiceCapture ? "Dictated" : "Captured",
                          systemImage: item.source == .voiceCapture ? "mic.fill" : "text.bubble.fill")
                }

                // Proposed task title
                Section("Task title") {
                    TextField("What needs doing?", text: $title, axis: .vertical)
                        .lineLimit(2...4)
                }

                // AI structure suggestion
                if canEnrich {
                    Section {
                        Button {
                            Task { await runEnrich() }
                        } label: {
                            HStack(spacing: 10) {
                                switch enrichState {
                                case .idle:
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(Color.warmEmber)
                                    Text("Suggest structure")
                                        .foregroundStyle(.primary)
                                case .running:
                                    ProgressView().controlSize(.small)
                                    Text("Working…")
                                        .foregroundStyle(.secondary)
                                case .done(let summary):
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Tokens.Color.success)
                                    Text(summary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                case .failed(let message):
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Tokens.Color.warning)
                                    Text(message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .disabled(enrichState == .running)
                    } footer: {
                        if let provider = AIProvider(rawValue: activeProviderRaw) {
                            Text("Sends the captured text to \(provider.displayName). You review all suggestions before anything is saved.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // Difficulty dimensions (collapsed by default — review should be fast)
                Section {
                    DisclosureGroup(isExpanded: $showDifficultyDetail) {
                        VStack(spacing: 16) {
                            inlineSlider(
                                label: "Friction",
                                value: $frictionLevel,
                                range: 1...5,
                                hint: "How hard is starting? 1 = easy, 5 = wall"
                            )
                            inlineSlider(
                                label: "Energy",
                                value: $energyRequired,
                                range: 1...4,
                                hint: "Cognitive + physical cost"
                            )
                            inlineSlider(
                                label: "Initiation cost",
                                value: $initiationCost,
                                range: 0...3,
                                hint: "Dread / first-step paralysis, independent of effort"
                            )
                            TextField("Context tag (e.g. phone, home)", text: $contextTag)
                                .font(.subheadline)

                            HStack(spacing: 8) {
                                Image(systemName: "scope")
                                    .foregroundStyle(.secondary)
                                Text("Difficulty: \(previewBand.label)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(.vertical, 6)
                    } label: {
                        HStack {
                            Text("Difficulty")
                            Spacer()
                            Text(previewBand.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Review")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { discard() }
                        .foregroundStyle(.red)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to tasks") { organize() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { hydrate() }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func inlineSlider(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline).fontWeight(.medium)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .tint(Color.appAccent)
            Text(hint).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Hydrate

    private func hydrate() {
        // Prefer AI suggestions over raw text for the editable title.
        title          = item.aiSuggestedTitle ?? item.rawCapture
        frictionLevel  = item.aiSuggestedFriction      ?? 3
        energyRequired = item.aiSuggestedEnergy        ?? 2
        initiationCost = item.aiSuggestedInitiationCost ?? 0
        sensoryLoad    = item.aiSuggestedSensoryLoad   ?? 0
        socialLoad     = item.aiSuggestedSocialLoad    ?? 0
        contextTag     = item.aiSuggestedContextTag    ?? ""

        // If AI already ran, show the difficulty section open so the
        // user can see and adjust what was suggested.
        if item.hasAISuggestions { showDifficultyDetail = true }
    }

    // MARK: - Actions

    private func organize() {
        let task = AgendaTask(
            title: title.trimmingCharacters(in: .whitespaces),
            frictionLevel: frictionLevel,
            energyRequired: energyRequired,
            estimatedMinutes: 15,
            interestLevel: 3
        )
        task.initiationCost      = initiationCost
        task.sensoryLoad         = sensoryLoad
        task.socialLoad          = socialLoad
        task.contextTag          = contextTag
        task.assignedToProfileID = item.assignedToProfileID
                                   ?? profileManager.activeProfile?.clientID

        modelContext.insert(task)
        item.state = .organized
        item.resolvedTaskID = task.clientID
        do {
            try modelContext.save()
        } catch {
            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
        }
        dismiss()
    }

    private func discard() {
        item.state = .archived
        do {
            try modelContext.save()
        } catch {
            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
        }
        dismiss()
    }

    // MARK: - AI enrichment

    private func runEnrich() async {
        guard AIUsageLedger.shared.canEnrich() else {
            ErrorBannerController.shared.show("AI enrichment paused — monthly budget reached")
            return
        }
        guard let provider = AIProvider(rawValue: activeProviderRaw),
              let enricher = AIEnricherRegistry.enricher(for: provider)
        else {
            enrichState = .failed(message: "No provider configured.")
            return
        }

        let neurotypes = profileManager.activeProfile?.neurotypes.map(\.rawValue) ?? []
        let personalization = await MainActor.run { PersonalizationStore.shared.snapshot() }

        let context = EnrichmentContext(
            rawTitle: item.rawCapture.trimmingCharacters(in: .whitespaces),
            userNote: contextTag.isEmpty ? nil : contextTag,
            neurotypes: neurotypes,
            currentDensity: nil,
            personalization: personalization
        )

        enrichState = .running
        do {
            let result = try await enricher.enrich(context: context)
            await MainActor.run {
                applyEnrichment(result)
                AIUsageLedger.shared.record(result)
            }
            enrichState = .done(summary: "Difficulty: \(previewBand.label) · review below.")
        } catch let error as AIEnricherError {
            enrichState = .failed(message: error.errorDescription ?? "Failed")
        } catch {
            enrichState = .failed(message: "Unexpected error.")
        }
    }

    private func applyEnrichment(_ e: TaskEnrichment) {
        if let v = e.title, !v.isEmpty  { title          = v }
        if let v = e.friction           { frictionLevel   = v }
        if let v = e.energy             { energyRequired  = v }
        if let v = e.sensoryLoad        { sensoryLoad     = v }
        if let v = e.socialLoad         { socialLoad      = v }
        if let v = e.initiationCost     { initiationCost  = v }
        if let v = e.contextTag, !v.isEmpty { contextTag  = v }

        // Cache suggestions on the item so they survive sheet re-entry.
        item.aiSuggestedTitle          = title
        item.aiSuggestedFriction       = frictionLevel
        item.aiSuggestedEnergy         = energyRequired
        item.aiSuggestedInitiationCost = initiationCost
        item.aiSuggestedSensoryLoad    = sensoryLoad
        item.aiSuggestedSocialLoad     = socialLoad
        item.aiSuggestedContextTag     = contextTag.isEmpty ? nil : contextTag
        do {
            try modelContext.save()
        } catch {
            ErrorBannerController.shared.show("Couldn't save: \(error.localizedDescription)")
        }

        // Show the difficulty section so the user sees what was suggested.
        showDifficultyDetail = true
    }
}
