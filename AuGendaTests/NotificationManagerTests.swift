import XCTest
import SwiftData
import UserNotifications
@testable import AuGenda

final class NotificationManagerTests: XCTestCase {
    
    @MainActor
    func testAgendaPrivacyAndStyleFollowOwnerAcrossProfileChanges() throws {
        let container = AppContainer.makeTestContainer()
        let context = container.mainContext
        let manager = NotificationManager.shared
        manager.modelContext = context
        defer { manager.modelContext = nil }
        let profileManager = ActiveProfileManager.shared
        let previousProfile = profileManager.activeProfile
        defer { profileManager.activeProfile = previousProfile }
        let privateOwner = Profile(name: "Private owner")
        privateOwner.preferences = ProfilePreferences()
        privateOwner.preferences?.notificationPrivacyStrict = true
        privateOwner.preferences?.notificationStyle = .minimal
        let otherOwner = Profile(name: "Other owner")
        otherOwner.preferences = ProfilePreferences()
        otherOwner.preferences?.notificationPrivacyStrict = false
        otherOwner.preferences?.notificationStyle = .standard
        context.insert(privateOwner)
        context.insert(otherOwner)
        let now = Date.now
        let item = AgendaItem(title: "Sensitive title", scheduledDate: now.addingTimeInterval(3600))
        item.notes = "Sensitive notes"
        item.assignedToProfileID = privateOwner.clientID
        context.insert(item)
        try context.save()

        for active in [privateOwner, otherOwner] {
            profileManager.activeProfile = active
            let plan = manager.agendaReminderPlan(for: item, at: now)
            XCTAssertEqual(plan.map(\.type), ["attime"])
            XCTAssertEqual(plan.first?.title, "Time for your task")
            XCTAssertEqual(plan.first?.body, "Tap to open")
            let snooze = manager.agendaReminderPlan(
                for: item, at: now, snoozeOverride: now.addingTimeInterval(600)
            )
            XCTAssertEqual(snooze.first?.title, "Snooze reminder")
        }
        item.assignedToProfileID = otherOwner.clientID
        profileManager.activeProfile = privateOwner
        let visible = manager.agendaReminderPlan(for: item, at: now)
        XCTAssertEqual(visible.count, 3)
        XCTAssertEqual(visible.first(where: { $0.type == "attime" })?.body, item.notes)

        // Missing and legacy owners cannot inherit another profile's opt-out.
        for ownerID in [nil, UUID()] as [UUID?] {
            item.assignedToProfileID = ownerID
            let fallback = manager.agendaReminderPlan(for: item, at: now)
            XCTAssertEqual(fallback.map(\.type), ["attime"])
            XCTAssertEqual(fallback.first?.body, "Tap to open")
        }
    }

    @MainActor
    func testReminderRebuildPreservesSnoozeInsteadOfOriginalSchedule() throws {
        let container = AppContainer.makeTestContainer()
        let manager = NotificationManager.shared
        manager.modelContext = container.mainContext
        defer { manager.modelContext = nil }
        let now = Date.now
        let deadline = now.addingTimeInterval(600)
        for originalOffset in [-3600.0, 3600.0] {
            let item = AgendaItem(title: "Snoozed", scheduledDate: now.addingTimeInterval(originalOffset))
            item.snoozedUntil = deadline
            container.mainContext.insert(item)
            try container.mainContext.save()
            let plan = manager.agendaReminderPlan(for: item, at: now)
            XCTAssertEqual(plan.map(\.type), ["snooze"])
            XCTAssertEqual(plan.first?.date, deadline)
            XCTAssertTrue(manager.agendaReminderPlan(for: item, at: deadline).isEmpty)
            item.isComplete = true
            XCTAssertTrue(manager.agendaReminderPlan(for: item, at: now).isEmpty)
        }
    }

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

    @MainActor
    func testDuplicateFocusStartIsRejected() throws {
        let container = AppContainer.makeTestContainer()
        let manager = NotificationManager.shared
        manager.modelContext = container.mainContext

        XCTAssertTrue(manager.startFocusSession(durationMinutes: 25, taskTitle: "First"))
        XCTAssertFalse(manager.startFocusSession(durationMinutes: 25, taskTitle: "Second"))

        let activeRaw = FocusSessionState.active.rawValue
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.stateRaw == activeRaw }
        )
        XCTAssertEqual(try container.mainContext.fetch(descriptor).count, 1)
        XCTAssertTrue(manager.endFocusSession())
    }

    @MainActor
    func testLaunchReconciliationCompletesExpiredSession() throws {
        let container = AppContainer.makeTestContainer()
        let expired = FocusSession(plannedDurationMinutes: 1, taskTitle: "Expired")
        expired.startTime = Date.now.addingTimeInterval(-120)
        container.mainContext.insert(expired)
        try container.mainContext.save()

        let manager = NotificationManager.shared
        manager.modelContext = nil
        manager.modelContext = container.mainContext

        XCTAssertFalse(manager.focusSessionActive)
        XCTAssertEqual(expired.state, .completed)
        XCTAssertTrue(expired.wasCompleted)
        manager.removeAllNotifications()
    }

    @MainActor
    func testLaunchReconciliationRestoresLatestActiveSessionAndClosesDuplicate() throws {
        let container = AppContainer.makeTestContainer()
        let older = FocusSession(plannedDurationMinutes: 25, taskTitle: "Older")
        older.startTime = Date.now.addingTimeInterval(-60)
        let latest = FocusSession(plannedDurationMinutes: 25, taskTitle: "Latest")
        container.mainContext.insert(older)
        container.mainContext.insert(latest)
        try container.mainContext.save()

        let manager = NotificationManager.shared
        manager.modelContext = nil
        manager.modelContext = container.mainContext

        XCTAssertTrue(manager.focusSessionActive)
        XCTAssertEqual(older.state, .abandoned)
        XCTAssertEqual(latest.state, .active)
        XCTAssertTrue(manager.endFocusSession())
    }

    @MainActor
    func testPauseAndResumePersistExplicitStateAndExcludePausedTime() throws {
        let container = AppContainer.makeTestContainer()
        let manager = NotificationManager.shared
        manager.modelContext = nil
        manager.modelContext = container.mainContext

        XCTAssertTrue(manager.startFocusSession(durationMinutes: 25, taskTitle: "Pause me"))
        let session = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<FocusSession>()).first
        )
        let originalStart = session.startTime

        XCTAssertTrue(manager.pauseFocusSession(reason: "Doorbell"))
        XCTAssertEqual(session.state, .paused)
        XCTAssertTrue(manager.focusSessionActive)
        XCTAssertTrue(manager.focusSessionPaused)
        XCTAssertNil(manager.focusSessionEndsAt)
        XCTAssertEqual(session.interruptionCount, 1)
        XCTAssertEqual(session.interruptionReasons, ["Doorbell"])

        // Make the deterministic pause interval two minutes instead of
        // sleeping in a unit test.
        session.endTime = Date.now.addingTimeInterval(-120)
        try container.mainContext.save()
        XCTAssertTrue(manager.resumeFocusSession())

        XCTAssertEqual(session.state, .active)
        XCTAssertNil(session.endTime)
        XCTAssertFalse(manager.focusSessionPaused)
        XCTAssertNotNil(manager.focusSessionEndsAt)
        XCTAssertGreaterThanOrEqual(
            session.startTime.timeIntervalSince(originalStart),
            119
        )
        XCTAssertTrue(manager.endFocusSession())
    }

    @MainActor
    func testFinishingWhilePausedExcludesOpenPauseFromDuration() throws {
        let container = AppContainer.makeTestContainer()
        let manager = NotificationManager.shared
        manager.modelContext = nil
        manager.modelContext = container.mainContext

        XCTAssertTrue(manager.startFocusSession(durationMinutes: 25))
        let session = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<FocusSession>()).first
        )
        XCTAssertTrue(manager.pauseFocusSession())
        let pausedAt = try XCTUnwrap(session.endTime)

        XCTAssertTrue(manager.endFocusSession())
        XCTAssertEqual(session.state, .completed)
        XCTAssertTrue(session.wasCompleted)
        XCTAssertEqual(session.endTime, pausedAt)
    }

    @MainActor
    func testAbandonFocusSessionPreservesReasonWithoutCompletion() throws {
        let container = AppContainer.makeTestContainer()
        let manager = NotificationManager.shared
        manager.modelContext = nil
        manager.modelContext = container.mainContext

        XCTAssertTrue(manager.startFocusSession(durationMinutes: 25))
        XCTAssertTrue(manager.abandonFocusSession(reason: "Changed priorities"))

        let session = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<FocusSession>()).first
        )
        XCTAssertEqual(session.state, .abandoned)
        XCTAssertTrue(session.wasAbandoned)
        XCTAssertFalse(session.wasCompleted)
        XCTAssertEqual(session.abandonReason, "Changed priorities")
        XCTAssertFalse(manager.focusSessionActive)
        XCTAssertFalse(manager.focusSessionPaused)
    }

    @MainActor
    func testLaunchReconciliationRestoresPausedSessionWithoutExpiringIt() throws {
        let container = AppContainer.makeTestContainer()
        let paused = FocusSession(plannedDurationMinutes: 1, taskTitle: "Paused")
        paused.startTime = Date.now.addingTimeInterval(-300)
        paused.state = .paused
        paused.endTime = Date.now.addingTimeInterval(-240)
        container.mainContext.insert(paused)
        try container.mainContext.save()

        let manager = NotificationManager.shared
        manager.modelContext = nil
        manager.modelContext = container.mainContext

        XCTAssertTrue(manager.focusSessionActive)
        XCTAssertTrue(manager.focusSessionPaused)
        XCTAssertEqual(paused.state, .paused)
        XCTAssertNil(manager.focusSessionEndsAt)
        XCTAssertTrue(manager.abandonFocusSession(reason: "Test cleanup"))
    }
}
