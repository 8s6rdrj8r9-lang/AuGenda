import XCTest
import SwiftData
@testable import AuGenda

final class FocusSessionTests: XCTestCase {
    
    @MainActor
    func testFocusSessionCreation() {
        let session = FocusSession(plannedDurationMinutes: 45, taskTitle: "Test task")
        XCTAssertEqual(session.plannedDurationMinutes, 45)
        XCTAssertEqual(session.taskTitle, "Test task")
        XCTAssertEqual(session.state, .active)
        XCTAssertFalse(session.isOverdue)
    }
    
    @MainActor
    func testFocusSessionCompletion() {
        let session = FocusSession(plannedDurationMinutes: 25)
        session.startTime = Date.now.addingTimeInterval(-120) // 2 minutes ago
        session.state = .completed
        session.endTime = .now
        session.wasCompleted = true
        XCTAssertTrue(session.wasCompleted)
        XCTAssertGreaterThan(session.actualDurationMinutes, 0)
    }
    
    @MainActor
    func testFocusSessionOverdue() {
        let session = FocusSession(plannedDurationMinutes: 1)
        session.startTime = Date.now.addingTimeInterval(-120)
        XCTAssertTrue(session.isOverdue)
    }
}
