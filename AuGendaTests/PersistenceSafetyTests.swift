import Foundation
import CoreData
import SwiftData
import Testing
@testable import AuGenda

@MainActor
struct PersistenceSafetyTests {
    private func temporarySupportDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AuGendaStoreRouting-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func unrelatedMacStoreIsPreservedAndDedicatedStorePersists() throws {
        let support = try temporarySupportDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let legacy = support.appendingPathComponent("default.store")
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "FolderViewState"
        entity.managedObjectClassName = "NSManagedObject"
        model.entities = [entity]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType, configurationName: nil, at: legacy
        )
        try coordinator.remove(store)
        let original = try Data(contentsOf: legacy)

        let url = try AppContainer.macOSStoreURL(applicationSupport: support)
        #expect(url == support.appendingPathComponent("ensdev.AuGenda/AuGenda.store"))
        let schema = Schema(AuGendaSchemaV2.models)
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(
                for: schema, migrationPlan: AuGendaMigrationPlan.self, configurations: [config]
            )
            container.mainContext.insert(AgendaTask(title: "Persist across launch"))
            try container.mainContext.save()
        }
        let reopened = try ModelContainer(
            for: schema, migrationPlan: AuGendaMigrationPlan.self, configurations: [config]
        )
        #expect(try reopened.mainContext.fetch(FetchDescriptor<AgendaTask>()).first?.title == "Persist across launch")
        #expect(try Data(contentsOf: legacy) == original)
        #expect(try AppContainer.macOSStoreURL(applicationSupport: support) == url)
    }

    @Test func genuineLegacyMacStoreKeepsItsLocation() throws {
        let support = try temporarySupportDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/AuGendaV1.store")
        let legacy = support.appendingPathComponent("default.store")
        try FileManager.default.copyItem(at: fixture, to: legacy)
        let original = try Data(contentsOf: legacy)
        #expect(try AppContainer.macOSStoreURL(applicationSupport: support) == legacy)
        #expect(try Data(contentsOf: legacy) == original)
    }

    @Test func unreadableLegacyMacStoreDoesNotSilentlyStartFresh() throws {
        let support = try temporarySupportDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let legacy = support.appendingPathComponent("default.store")
        try Data("broken store".utf8).write(to: legacy)
        #expect(throws: (any Error).self) {
            try AppContainer.macOSStoreURL(applicationSupport: support)
        }
        #expect(!FileManager.default.fileExists(atPath: support.appendingPathComponent("ensdev.AuGenda/AuGenda.store").path))
    }

    @Test func startupFailureNeverReturnsAnInMemoryProductionStore() {
        let state = AppContainer.startupState {
            throw NSError(domain: "PersistenceSafetyTests", code: 73)
        }

        switch state {
        case .ready:
            Issue.record("A failed production factory unexpectedly returned a writable store")
        case .failed(let failure):
            #expect(failure.diagnosticCode == "AUG-PERSIST-00000049")
            #expect(failure.supportSummary.contains("application-local"))
        }
    }

    @Test func mutationRollbackRemovesUnsavedInsertAfterSaveFailure() throws {
        let container = AppContainer.makeTestContainer()
        let context = container.mainContext
        context.autosaveEnabled = false

        enum InjectedFailure: Error { case save }
        do {
            try PersistentMutation.commit(
                in: context,
                changes: {
                    context.insert(AgendaTask(title: "Must not survive"))
                },
                save: { _ in throw InjectedFailure.save }
            )
            Issue.record("Injected save failure unexpectedly succeeded")
        } catch {
            #expect(error is InjectedFailure)
        }

        let stored = try context.fetch(FetchDescriptor<AgendaTask>())
        #expect(stored.isEmpty)
    }
}
