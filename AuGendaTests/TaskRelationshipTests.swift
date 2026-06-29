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
}
