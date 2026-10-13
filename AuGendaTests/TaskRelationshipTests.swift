import XCTest
import SwiftData
@testable import AuGenda

final class TaskRelationshipTests: XCTestCase {
    
    @MainActor
    func testRelationshipCreation() {
        let id1 = UUID()
        let id2 = UUID()
        let rel = TaskRelationship(sourceTaskID: id1, targetTaskID: id2, type: .blocks)
        XCTAssertEqual(rel.sourceTaskID, id1)
        XCTAssertEqual(rel.targetTaskID, id2)
        XCTAssertEqual(rel.type, .blocks)
        XCTAssertTrue(rel.isBlocking)
    }
    
    @MainActor
    func testRelationshipTypeRoundTrip() {
        let rel = TaskRelationship(sourceTaskID: UUID(), targetTaskID: UUID(), type: .follows)
        XCTAssertEqual(rel.typeRaw, "follows")
        XCTAssertEqual(rel.type, .follows)
    }
    
    @MainActor
    func testRelatedTypeNotBlocking() {
        let rel = TaskRelationship(sourceTaskID: UUID(), targetTaskID: UUID(), type: .related)
        XCTAssertFalse(rel.isBlocking)
    }

    @MainActor
    func testServiceRejectsMissingAndSelfRelationships() throws {
        let container = AppContainer.makeTestContainer()
        let task = AgendaTask(title: "Only task")
        container.mainContext.insert(task)
        try container.mainContext.save()

        XCTAssertThrowsError(
            try TaskRelationshipService.create(
                sourceTaskID: task.clientID,
                targetTaskID: task.clientID,
                type: .blocks,
                in: container.mainContext
            )
        )
        XCTAssertThrowsError(
            try TaskRelationshipService.create(
                sourceTaskID: task.clientID,
                targetTaskID: UUID(),
                type: .blocks,
                in: container.mainContext
            )
        )
    }

    @MainActor
    func testServiceRejectsDuplicateAndCycle() throws {
        let container = AppContainer.makeTestContainer()
        let first = AgendaTask(title: "First")
        let second = AgendaTask(title: "Second")
        let third = AgendaTask(title: "Third")
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        container.mainContext.insert(third)
        try container.mainContext.save()

        _ = try TaskRelationshipService.create(
            sourceTaskID: first.clientID,
            targetTaskID: second.clientID,
            type: .blocks,
            in: container.mainContext
        )
        XCTAssertThrowsError(
            try TaskRelationshipService.create(
                sourceTaskID: first.clientID,
                targetTaskID: second.clientID,
                type: .blocks,
                in: container.mainContext
            )
        )
        _ = try TaskRelationshipService.create(
            sourceTaskID: second.clientID,
            targetTaskID: third.clientID,
            type: .follows,
            in: container.mainContext
        )
        XCTAssertThrowsError(
            try TaskRelationshipService.create(
                sourceTaskID: third.clientID,
                targetTaskID: first.clientID,
                type: .blocks,
                in: container.mainContext
            )
        )
    }
}
