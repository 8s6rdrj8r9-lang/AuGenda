// AppContainer.swift
// AUDHD Agenda App

import Foundation
import CoreData
import OSLog
import SwiftData

private let persistenceLogger = Logger(
    subsystem: "com.augenda.AuGenda",
    category: "PersistenceStartup"
)

// MARK: - Schema Versioning

enum AuGendaSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [
        AgendaItem.self, SubTask.self, AgendaTask.self, TaskStep.self,
        InboxItem.self, UserPreferences.self, Block.self, BlockTask.self,
        BundleTemplate.self, BundleTemplateItem.self, AttachedBundle.self,
        AttachedBundleItem.self, Profile.self, ProfilePreferences.self
    ]
}

enum AuGendaSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] = [
        AgendaItem.self, SubTask.self, AgendaTask.self, TaskStep.self,
        InboxItem.self, UserPreferences.self, Block.self, BlockTask.self,
        BundleTemplate.self, BundleTemplateItem.self, AttachedBundle.self,
        AttachedBundleItem.self, Profile.self, ProfilePreferences.self,
        FocusSession.self, TaskRelationship.self, Note.self
    ]
}

enum AuGendaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AuGendaSchemaV1.self, AuGendaSchemaV2.self]
    }
    
    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }
    
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: AuGendaSchemaV1.self,
        toVersion: AuGendaSchemaV2.self
    )
}

/// The production startup boundary is explicit so a failed persistent store
/// can never be mistaken for an empty, writable account.
enum PersistenceStartupState {
    case ready(ModelContainer)
    case failed(PersistenceStartupFailure)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

struct PersistenceStartupFailure: Error, Identifiable {
    let diagnosticCode: String

    var id: String { diagnosticCode }

    var supportSummary: String {
        """
        AuGenda could not open its local data store.
        Diagnostic code: \(diagnosticCode)
        Store class: application-local
        """
    }
}

enum AppContainer {

    /// Shared schema — keep in sync across every container variant below.
    private static var schemaModels: [any PersistentModel.Type] {
        AuGendaSchemaV2.models
    }

    /// Build the app's file-backed local store. Failure is returned to the
    /// launch UI; production must never substitute an in-memory container.
    @MainActor
    static func makePersistentLocalStartupState() -> PersistenceStartupState {
        startupState(using: makePersistentLocalContainer)
    }

    /// Injection seam used by persistence-startup tests. Keeping failure
    /// conversion here also ensures logs contain only an opaque diagnostic
    /// code and store class, never a path or user-controlled content.
    @MainActor
    static func startupState(
        using factory: () throws -> ModelContainer
    ) -> PersistenceStartupState {
        do {
            return .ready(try factory())
        } catch {
            let failure = PersistenceStartupFailure(
                diagnosticCode: diagnosticCode(for: error)
            )
            persistenceLogger.fault(
                "Persistent store unavailable; code=\(failure.diagnosticCode, privacy: .public) store=application-local"
            )
            return .failed(failure)
        }
    }

    @MainActor
    private static func makePersistentLocalContainer() throws -> ModelContainer {
        let schema = Schema(schemaModels)

        #if os(macOS)
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let config = ModelConfiguration(
            schema: schema,
            url: try macOSStoreURL(applicationSupport: support),
            cloudKitDatabase: .none
        )
        #else
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        #endif

        return try ModelContainer(
            for: schema,
            migrationPlan: AuGendaMigrationPlan.self,
            configurations: [config]
        )
    }

    /// Unsandboxed Mac apps share Application Support. SwiftData's default
    /// filename can therefore point at another app's database. Inspect only
    /// metadata before retaining a legacy AuGenda store; never mutate or move
    /// an unrelated store. Unreadable legacy metadata remains a startup error.
    static func macOSStoreURL(applicationSupport: URL) throws -> URL {
        let directory = applicationSupport.appendingPathComponent("ensdev.AuGenda", isDirectory: true)
        let dedicated = directory.appendingPathComponent("AuGenda.store")
        let legacy = applicationSupport.appendingPathComponent("default.store")
        let files = FileManager.default

        if files.fileExists(atPath: dedicated.path) { return dedicated }
        if files.fileExists(atPath: legacy.path) {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType, at: legacy,
                options: [NSReadOnlyPersistentStoreOption: true]
            )
            guard let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data],
                  !hashes.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let legacyEntities: Set<String> = [
                "AgendaItem", "AgendaTask", "InboxItem", "UserPreferences",
                "Profile", "ProfilePreferences", "Block", "TaskStep"
            ]
            if !legacyEntities.isDisjoint(with: hashes.keys) { return legacy }
        }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        return dedicated
    }

    private static func diagnosticCode(for error: Error) -> String {
        let code = UInt32(truncatingIfNeeded: (error as NSError).code)
        return String(format: "AUG-PERSIST-%08X", code)
    }

    static func makeTestContainer() -> ModelContainer {
        let schema = Schema(schemaModels)

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        do {
            return try ModelContainer(for: schema, migrationPlan: AuGendaMigrationPlan.self, configurations: [config])
        } catch {
            fatalError("Failed to create in-memory model container: \(error)")
        }
    }

    @MainActor
    static var preview: ModelContainer = {
        let container = makeTestContainer()
        SampleData.populate(context: container.mainContext)
        return container
    }()
}


// MARK: - UserPreferences

@Model
final class UserPreferences {

    var clientID: UUID = UUID()
    var updatedAt: Date = Date.now
    var currentEnergyLevel: Int = 3
    var lowEFMaxFriction: Int = 2
    var focusSessionMinutes: Int = 25
    var breakMinutes: Int = 10
    var notificationStyle: String = "standard"
    var watchComplicationMode: String = "next-task"
    var theme: String = "system"
    var minimalMode: Bool = false

    init() {
        self.clientID = UUID()
        self.updatedAt = .now
    }
}


// MARK: - Sample Data

enum SampleData {

    @MainActor
    static func populate(context: ModelContext) {
        let prefs = UserPreferences()
        prefs.currentEnergyLevel = 2
        context.insert(prefs)

        // Sample profiles
        let coordinator = Profile(name: "Arthur", role: .coordinator, neurotypes: [.adhd, .autism], sortOrder: 0)
        let coordPrefs = ProfilePreferences.makePreset(for: [.adhd, .autism])
        coordPrefs.currentEnergyLevel = 2
        coordinator.preferences = coordPrefs
        context.insert(coordinator)
        context.insert(coordPrefs)

        let partner = Profile(name: "Partner", role: .adult, neurotypes: [.autism], sortOrder: 1)
        let partnerPrefs = ProfilePreferences.makePreset(for: [.autism])
        partner.preferences = partnerPrefs
        context.insert(partner)
        context.insert(partnerPrefs)

        let child = Profile(name: "Kid", role: .child, neurotypes: [.adhd], sortOrder: 2)
        let childPrefs = ProfilePreferences.makePreset(for: [.adhd])
        childPrefs.largeTouchTargets = true
        child.preferences = childPrefs
        context.insert(child)
        context.insert(childPrefs)

        let items: [(String, Int, Int, String)] = [
            ("Morning meds", 1, 1, "home"),
            ("Review agenda", 2, 2, "focus"),
            ("Tile grouting — bathroom", 4, 3, "home"),
            ("Call re: PWD paperwork", 3, 2, "phone"),
            ("Order grout sealer", 2, 1, "computer")
        ]

        for (index, (title, friction, energy, contextTag)) in items.enumerated() {
            let item = AgendaItem(
                title: title,
                scheduledDate: Calendar.current.date(
                    byAdding: .hour, value: index, to: .now) ?? .now,
                priority: index == 0 ? 2 : 0,
                frictionLevel: friction,
                energyRequired: energy,
                contextTag: contextTag
            )
            context.insert(item)
        }

        let tasks: [(String, Int, Int, Int)] = [
            ("Research grout sealers", 2, 1, 4),
            ("Email landlord re: window repair", 4, 2, 2),
            ("Set up watch complications", 2, 1, 5),
            ("Tolerance break plan", 1, 1, 3)
        ]

        for (title, friction, energy, interest) in tasks {
            let task = AgendaTask(
                title: title,
                frictionLevel: friction,
                energyRequired: energy,
                estimatedMinutes: 20,
                interestLevel: interest
            )
            context.insert(task)
        }

        // Sample inbox items — unprocessed brain dumps
        let inboxCaptures: [(String, InboxItemSource)] = [
            ("Need to call the pharmacy about the prescription refill — they said call back after 2pm", .textCapture),
            ("idea for the balcony: get one of those folding tables so we can eat outside when the weather is good", .voiceCapture),
            ("check if dentist appointment is this thursday or next", .textCapture)
        ]
        for (capture, source) in inboxCaptures {
            let item = InboxItem(rawCapture: capture, source: source)
            context.insert(item)
        }
    }
}
