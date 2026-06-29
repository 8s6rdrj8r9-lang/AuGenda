import XCTest
import SwiftData
import UserNotifications
@testable import AuGenda

final class NotificationManagerTests: XCTestCase {
    
    @MainActor
    func testStartFocusSessionCreatesRecord() {
        let container = AppContainer.makeTestContainer()
        let manager = NotificationManager.shared
        manager.modelContext = container.mainContext
        
        manager.startFocusSession(durationMinutes: 25, taskTitle: "Test task")
        
        let activeRaw = FocusSessionState.active.rawValue
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.stateRaw == activeRaw }
        )
        let sessions = try? container.mainContext.fetch(descriptor)
        XCTAssertEqual(sessions?.count, 1)
        XCTAssertEqual(sessions?.first?.plannedDurationMinutes, 25)
        XCTAssertEqual(sessions?.first?.taskTitle, "Test task")
        
        manager.endFocusSession()
    }
    
    @MainActor
    func testEndFocusSessionMarksCompleted() {
        let container = AppContainer.makeTestContainer()
        let manager = NotificationManager.shared
        manager.modelContext = container.mainContext
        
        manager.startFocusSession(durationMinutes: 15, taskTitle: "Test")
        manager.endFocusSession()
        
        let completedRaw = FocusSessionState.completed.rawValue
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.stateRaw == completedRaw }
        )
        let sessions = try? container.mainContext.fetch(descriptor)
        XCTAssertEqual(sessions?.count, 1)
        XCTAssertTrue(sessions?.first?.wasCompleted == true)
    }
    
    @MainActor
    func testFocusSessionOverdue() {
        let container = AppContainer.makeTestContainer()
        let manager = NotificationManager.shared
        manager.modelContext = container.mainContext
        
        manager.startFocusSession(durationMinutes: 1, taskTitle: "Quick")
        // Simulate time passing by checking the created session directly
        let descriptor = FetchDescriptor<FocusSession>()
        if let session = try? container.mainContext.fetch(descriptor).first {
            session.startTime = Date.now.addingTimeInterval(-120)
            XCTAssertTrue(session.isOverdue)
        }
        manager.endFocusSession()
    }
}
