import XCTest
@testable import AuGenda

@MainActor
final class WatchSyncContractTests: XCTestCase {
    func testSnapshotRoundTripUsesOneDateContract() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_750_000_000.123)
        let scheduledAt = generatedAt.addingTimeInterval(900.456)
        let profileID = UUID()
        let itemID = UUID()
        let snapshot = WatchSnapshot(
            schemaVersion: WatchSyncContract.schemaVersion,
            snapshotID: UUID(),
            generatedAt: generatedAt,
            profileID: profileID,
            agendaItems: [
                WatchAgendaSummary(
                    clientID: itemID,
                    title: "Medication",
                    scheduledDate: scheduledAt,
                    isAllDay: false,
                    snoozedUntil: nil,
                    frictionLevel: 2,
                    contextTag: "home"
                )
            ],
            backlogTasks: [],
            currentEnergyLevel: 2,
            densityModeRaw: "low",
            focusSessionActive: true,
            focusSessionEndsAt: generatedAt.addingTimeInterval(1_500),
            pendingTaskCount: 1,
            lowFrictionTaskCount: 1,
            pendingRecovery: false
        )

        let message = try WatchSyncContract.message(type: .syncSnapshot, payload: snapshot)
        let decoded = try WatchSyncContract.decode(
            WatchSnapshot.self,
            from: message,
            expectedMessageType: .syncSnapshot
        )

        XCTAssertEqual(decoded.profileID, profileID)
        XCTAssertEqual(decoded.agendaItems.first?.clientID, itemID)
        let decodedScheduledAt = try XCTUnwrap(decoded.agendaItems.first?.scheduledDate)
        XCTAssertEqual(
            decodedScheduledAt.timeIntervalSince1970,
            scheduledAt.timeIntervalSince1970,
            accuracy: 0.001
        )
        let decodedFocusEndsAt = try XCTUnwrap(decoded.focusSessionEndsAt)
        let expectedFocusEndsAt = try XCTUnwrap(snapshot.focusSessionEndsAt)
        XCTAssertEqual(
            decodedFocusEndsAt.timeIntervalSince1970,
            expectedFocusEndsAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testSnapshotFreshnessRejectsOldFutureAndWrongVersion() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var snapshot = emptySnapshot(generatedAt: now)
        XCTAssertTrue(snapshot.isFresh(at: now))

        snapshot.generatedAt = now.addingTimeInterval(
            -(WatchSyncContract.snapshotMaxAge + 1)
        )
        XCTAssertFalse(snapshot.isFresh(at: now))

        snapshot.generatedAt = now.addingTimeInterval(5 * 60 + 1)
        XCTAssertFalse(snapshot.isFresh(at: now))

        snapshot.generatedAt = now
        snapshot.schemaVersion += 1
        XCTAssertFalse(snapshot.isFresh(at: now))
    }

    func testMutationEnvelopePreservesIdempotencyKey() throws {
        let eventID = UUID()
        let mutation = WatchMutation(
            eventID: eventID,
            profileID: UUID(),
            kind: .snoozeAgendaItem,
            agendaItemID: UUID(),
            snoozeMinutes: 15
        )

        let message = try WatchSyncContract.message(type: .mutation, payload: mutation)
        let decoded = try WatchSyncContract.decode(
            WatchMutation.self,
            from: message,
            expectedMessageType: .mutation
        )

        XCTAssertEqual(decoded.eventID, eventID)
        XCTAssertEqual(decoded.kind, .snoozeAgendaItem)
        XCTAssertEqual(decoded.snoozeMinutes, 15)
    }

    private func emptySnapshot(generatedAt: Date) -> WatchSnapshot {
        WatchSnapshot(
            schemaVersion: WatchSyncContract.schemaVersion,
            snapshotID: UUID(),
            generatedAt: generatedAt,
            profileID: UUID(),
            agendaItems: [],
            backlogTasks: [],
            currentEnergyLevel: 3,
            densityModeRaw: nil,
            focusSessionActive: false,
            focusSessionEndsAt: nil,
            pendingTaskCount: 0,
            lowFrictionTaskCount: 0,
            pendingRecovery: false
        )
    }
}
