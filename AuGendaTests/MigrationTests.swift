import XCTest
import SwiftData
@testable import AuGenda

final class MigrationTests: XCTestCase {
    
    @MainActor
    func testV1DataSurvivesV2Migration() {
        // Create a v1-style container (without FocusSession and TaskRelationship)
        let v1Schema = Schema([
            AgendaItem.self, SubTask.self, AgendaTask.self, TaskStep.self,
            InboxItem.self, UserPreferences.self, Block.self, BlockTask.self,
            BundleTemplate.self, BundleTemplateItem.self, AttachedBundle.self,
            AttachedBundleItem.self, Profile.self, ProfilePreferences.self
        ])
        let v1Config = ModelConfiguration(schema: v1Schema, isStoredInMemoryOnly: false)
        
        func createV1AndAddData() {
            guard let v1Container = try? ModelContainer(for: v1Schema, configurations: [v1Config]) else {
                XCTFail("Failed to create v1 container")
                return
            }
            let task = AgendaTask(title: "Legacy task", frictionLevel: 2, energyRequired: 1, estimatedMinutes: 15, contextTag: "home", priority: 0, interestLevel: 3)
            v1Container.mainContext.insert(task)
            do {
                try v1Container.mainContext.save()
            } catch {
                XCTFail("Failed to save v1 context: \(error)")
            }
        }
        createV1AndAddData()
        
        // Now open with v2 schema (which includes FocusSession and TaskRelationship)
        let v2Schema = Schema(AuGendaSchemaV2.models)
        let v2Config = ModelConfiguration(schema: v2Schema, isStoredInMemoryOnly: false)
        guard let v2Container = try? ModelContainer(for: v2Schema, migrationPlan: AuGendaMigrationPlan.self, configurations: [v2Config]) else {
            XCTFail("Failed to create v2 container")
            return
        }
        
        // Verify v1 data is still readable
        let descriptor = FetchDescriptor<AgendaTask>(
            predicate: #Predicate { $0.title == "Legacy task" }
        )
        let tasks = try? v2Container.mainContext.fetch(descriptor)
        XCTAssertEqual(tasks?.count, 1)
        XCTAssertEqual(tasks?.first?.title, "Legacy task")
    }
    
    @MainActor
    func testV2ModelsQueryable() {
        let container = AppContainer.makeTestContainer()
        
        let session = FocusSession(plannedDurationMinutes: 30, taskTitle: "Test")
        container.mainContext.insert(session)
        
        let rel = TaskRelationship(sourceTaskID: UUID(), targetTaskID: UUID(), type: .blocks)
        container.mainContext.insert(rel)
        
        try? container.mainContext.save()
        
        let sessionDesc = FetchDescriptor<FocusSession>()
        let sessions = try? container.mainContext.fetch(sessionDesc)
        XCTAssertEqual(sessions?.count, 1)
        
        let relDesc = FetchDescriptor<TaskRelationship>()
        let rels = try? container.mainContext.fetch(relDesc)
        XCTAssertEqual(rels?.count, 1)
    }
}
