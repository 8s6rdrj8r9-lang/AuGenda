// AuGendaAppIntents.swift
// AuGenda
//
// Siri AI and Spotlight App Intents integration for macOS 27 / iOS 27.
// Exposes cognitive scaffolding actions directly to Siri and system intelligence.

import AppIntents
import Foundation
import SwiftData

// MARK: - App Entity & Entity Query for Siri AI

public struct AgendaTaskEntity: AppEntity {
    public static var defaultQuery = TaskEntityQuery()
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "AuGenda Task"

    public var id: UUID

    @Property(title: "Title")
    public var title: String

    @Property(title: "Friction Level")
    public var frictionLevel: Int

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "Friction \(frictionLevel)/4"
        )
    }

    public init(id: UUID, title: String, frictionLevel: Int) {
        self.id = id
        self.title = title
        self.frictionLevel = frictionLevel
    }
}

public struct TaskEntityQuery: EntityQuery {
    public init() {}

    @MainActor
    public func entities(for identifiers: [UUID]) async throws -> [AgendaTaskEntity] {
        let startup = AppContainer.makePersistentLocalStartupState()
        guard case .ready(let container) = startup else { return [] }
        let context = container.mainContext
        let descriptor = FetchDescriptor<AgendaTask>(
            predicate: #Predicate { identifiers.contains($0.clientID) }
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
        return tasks.map { AgendaTaskEntity(id: $0.clientID, title: $0.title, frictionLevel: $0.frictionLevel) }
    }

    @MainActor
    public func suggestedEntities() async throws -> [AgendaTaskEntity] {
        let startup = AppContainer.makePersistentLocalStartupState()
        guard case .ready(let container) = startup else { return [] }
        let context = container.mainContext
        let descriptor = FetchDescriptor<AgendaTask>(
            predicate: #Predicate { $0.completedAt == nil },
            sortBy: [SortDescriptor(\.frictionLevel, order: .forward)]
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
        return tasks.prefix(10).map { AgendaTaskEntity(id: $0.clientID, title: $0.title, frictionLevel: $0.frictionLevel) }
    }
}

// MARK: - Capture Brain Dump Intent

public struct CaptureBrainDumpIntent: AppIntent {
    public static var title: LocalizedStringResource = "Capture to AuGenda"
    public static var description = IntentDescription("Quickly captures a raw thought or task into AuGenda's Brain Dump inbox.")

    @Parameter(title: "Thought or Task", requestValueDialog: "What would you like to capture?")
    public var text: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$text) in AuGenda")
    }

    public init() {}

    public init(text: String) {
        self.text = text
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let startup = AppContainer.makePersistentLocalStartupState()
        guard case .ready(let container) = startup else {
            return .result(dialog: "AuGenda database is currently unavailable.")
        }
        let context = container.mainContext
        let item = InboxItem()
        item.rawCapture = text
        item.sourceRaw = InboxItemSource.voiceCapture.rawValue
        item.stateRaw = InboxItemState.unprocessed.rawValue
        context.insert(item)
        try context.save()

        return .result(dialog: "Captured \"\(text)\" to your AuGenda inbox.")
    }
}

// MARK: - Complete Task Intent

public struct CompleteTaskIntent: AppIntent {
    public static var title: LocalizedStringResource = "Complete Task in AuGenda"
    public static var description = IntentDescription("Marks an active task as complete in AuGenda.")

    @Parameter(title: "Task")
    public var task: AgendaTaskEntity

    public static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$task) in AuGenda")
    }

    public init() {}

    public init(task: AgendaTaskEntity) {
        self.task = task
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let startup = AppContainer.makePersistentLocalStartupState()
        guard case .ready(let container) = startup else {
            return .result(dialog: "AuGenda database is unavailable.")
        }
        let context = container.mainContext
        let taskID = task.id
        let descriptor = FetchDescriptor<AgendaTask>(
            predicate: #Predicate { $0.clientID == taskID }
        )
        guard let item = (try? context.fetch(descriptor))?.first else {
            return .result(dialog: "Task \"\(task.title)\" not found.")
        }

        item.completedAt = Date.now
        item.updatedAt = Date.now
        try context.save()

        return .result(dialog: "Marked \"\(item.title)\" as completed. Well done!")
    }
}

// MARK: - Get Next Focus Task Intent (With Dependency & Privacy Checks)

public struct GetTopFocusTaskIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get Next Task in AuGenda"
    public static var description = IntentDescription("Retrieves your next priority, unblocked task matching your current energy.")

    @Parameter(title: "Preserve Lock Privacy", default: true)
    public var preservePrivacy: Bool

    public static var parameterSummary: some ParameterSummary {
        Summary("Get next task from AuGenda")
    }

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let startup = AppContainer.makePersistentLocalStartupState()
        guard case .ready(let container) = startup else {
            return .result(dialog: "AuGenda database is currently unavailable.")
        }
        let context = container.mainContext
        let descriptor = FetchDescriptor<AgendaTask>(
            predicate: #Predicate { $0.completedAt == nil },
            sortBy: [
                SortDescriptor(\.frictionLevel, order: .forward),
                SortDescriptor(\.createdAt, order: .forward)
            ]
        )
        let tasks = (try? context.fetch(descriptor)) ?? []

        // EnsDev PRD check: Skip tasks that are currently blocked by incomplete prerequisite tasks
        guard let task = tasks.first(where: { !$0.isBlocked(in: context) }) else {
            return .result(dialog: "You have no unblocked tasks waiting right now. Enjoy your space!")
        }

        let frictionText = task.frictionLevel == 1 ? "low friction" : "friction level \(task.frictionLevel)/4"
        return .result(dialog: "Next up: \"\(task.title)\" (\(frictionText)).")
    }
}

// MARK: - Enrich Task Intent (Siri AI Delegation)

public struct EnrichTaskIntent: AppIntent {
    public static var title: LocalizedStringResource = "Enrich Task with On-Device AI"
    public static var description = IntentDescription("Delegates task breakdown and difficulty structuring to AuGenda's on-device Foundation Model.")

    @Parameter(title: "Task Title", requestValueDialog: "What task do you want to enrich?")
    public var title: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Enrich \(\.$title) in AuGenda")
    }

    public init() {}

    public init(title: String) {
        self.title = title
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let enricher = AIEnricherRegistry.enricher(for: .appleFoundation) else {
            return .result(dialog: "Apple on-device AI is not available on this device.")
        }

        let enrichmentContext = EnrichmentContext(
            rawTitle: title,
            userNote: nil,
            neurotypes: ["AuDHD"],
            currentDensity: "functional",
            personalization: nil
        )

        do {
            let enrichment = try await enricher.enrich(context: enrichmentContext)
            let steps = (enrichment.subTasks ?? []).prefix(3).joined(separator: ", ")
            let summary = steps.isEmpty
                ? "Estimated at \(enrichment.estimatedMinutes ?? 15) minutes, friction \(enrichment.friction ?? 2)/4."
                : "Suggested steps: \(steps). Estimated \(enrichment.estimatedMinutes ?? 15) minutes."
            return .result(dialog: "Enriched \"\(title)\": \(summary)")
        } catch {
            return .result(dialog: "Could not enrich task right now: \(error.localizedDescription)")
        }
    }
}

// MARK: - App Shortcuts Provider

public struct AuGendaShortcuts: AppShortcutsProvider {
    public static var shortcutTileColor: ShortcutTileColor = .teal

    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureBrainDumpIntent(),
            phrases: [
                "Capture in \(.applicationName)",
                "Add to my \(.applicationName) inbox",
                "Brain dump in \(.applicationName)"
            ],
            shortTitle: "Capture to AuGenda",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: GetTopFocusTaskIntent(),
            phrases: [
                "What's my next task in \(.applicationName)?",
                "What should I do next in \(.applicationName)?",
                "Get next task from \(.applicationName)"
            ],
            shortTitle: "Get Next Task",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: [
                "Complete \(\.$task) in \(.applicationName)",
                "Mark \(\.$task) done in \(.applicationName)"
            ],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: EnrichTaskIntent(),
            phrases: [
                "Enrich task in \(.applicationName)",
                "Break down task in \(.applicationName)"
            ],
            shortTitle: "Enrich Task",
            systemImageName: "sparkles"
        )
    }
}
