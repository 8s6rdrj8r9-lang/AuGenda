import Foundation
import Testing
@testable import AuGendaWatch_Watch_App

struct WatchSharedStateStoreTests {
    @Test @MainActor
    func outboxIsDurableDeduplicatedAndAcknowledged() throws {
        let suiteName = "WatchSharedStateStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WatchSharedStateStore(defaults: defaults)
        let mutation = WatchMutation(
            eventID: UUID(),
            profileID: UUID(),
            kind: .completeAgendaItem,
            agendaItemID: UUID()
        )

        #expect(store.enqueue(mutation))
        #expect(!store.enqueue(mutation))
        #expect(store.pendingMutations().map(\.mutation.eventID) == [mutation.eventID])

        let attemptDate = Date(timeIntervalSince1970: 2_000_000_000)
        store.markAttempted(eventID: mutation.eventID, at: attemptDate)
        let attempted = try #require(store.pendingMutations().first)
        #expect(attempted.attemptCount == 1)
        #expect(attempted.lastAttemptAt == attemptDate)
        #expect(store.mutationsDue(at: attemptDate.addingTimeInterval(29)).isEmpty)
        #expect(store.mutationsDue(at: attemptDate.addingTimeInterval(30)).count == 1)

        store.markTransferFailed(eventID: mutation.eventID)
        let reset = try #require(store.pendingMutations().first)
        #expect(reset.attemptCount == 0)
        #expect(reset.lastAttemptAt == nil)
        #expect(store.mutationsDue(at: attemptDate).count == 1)

        store.acknowledge(eventID: mutation.eventID)
        #expect(store.pendingMutations().isEmpty)
    }

    @Test @MainActor
    func rejectedCapturesArePreservedAcrossStoreRestarts() throws {
        let suiteName = "WatchSharedStateStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WatchSharedStateStore(defaults: defaults)

        let eventID = UUID()
        let profileID = UUID()
        let capture = RejectedWatchCapture(
            eventID: eventID,
            profileID: profileID,
            title: "Remember to breathe",
            reason: "Rejected: profile changed",
            rejectedAt: Date.now
        )

        store.saveRejectedCapture(capture)
        #expect(store.rejectedCaptures().count == 1)
        #expect(store.rejectedCaptures().first?.title == "Remember to breathe")

        // Simulate app restart with a fresh store instance pointing to same defaults
        let restartedStore = WatchSharedStateStore(defaults: defaults)
        let preserved = try #require(restartedStore.rejectedCaptures().first)
        #expect(preserved.eventID == eventID)
        #expect(preserved.title == "Remember to breathe")
        #expect(preserved.reason == "Rejected: profile changed")

        restartedStore.removeRejectedCapture(eventID: eventID)
        #expect(restartedStore.rejectedCaptures().isEmpty)
    }

    @Test @MainActor
    func olderSnapshotCannotReplaceNewerSnapshot() throws {
        let suiteName = "WatchSharedStateStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WatchSharedStateStore(defaults: defaults)
        let profileID = UUID()
        let newer = snapshot(
            id: UUID(),
            generatedAt: Date(timeIntervalSince1970: 2_000),
            profileID: profileID
        )
        let older = snapshot(
            id: UUID(),
            generatedAt: Date(timeIntervalSince1970: 1_000),
            profileID: profileID
        )

        #expect(store.save(snapshot: newer))
        #expect(!store.save(snapshot: older))
        #expect(store.loadSnapshot()?.snapshotID == newer.snapshotID)
    }

    @Test @MainActor
    func outboxRejectsMalformedMutationsAtItsDurableBoundary() throws {
        let suiteName = "WatchSharedStateStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WatchSharedStateStore(defaults: defaults)
        let profileID = UUID()

        #expect(
            !store.enqueue(
                WatchMutation(
                    profileID: profileID,
                    kind: .updateEnergy,
                    energyLevel: 5
                )
            )
        )
        #expect(
            !store.enqueue(
                WatchMutation(
                    profileID: profileID,
                    kind: .snoozeAgendaItem,
                    agendaItemID: UUID(),
                    snoozeMinutes: 0
                )
            )
        )
        #expect(
            !store.enqueue(
                WatchMutation(
                    profileID: profileID,
                    kind: .captureTask,
                    captureTitle: "   "
                )
            )
        )
        #expect(store.pendingMutations().isEmpty)
    }

    @Test @MainActor
    func presentationSnapshotAppliesPendingActionsAndRequiresAProfile() throws {
        let suiteName = "WatchSharedStateStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WatchSharedStateStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 2_000)
        let profileID = UUID()
        let agendaID = UUID()
        var source = snapshot(id: UUID(), generatedAt: now, profileID: profileID)
        source.agendaItems = [
            WatchAgendaSummary(
                clientID: agendaID,
                title: "Call pharmacy",
                scheduledDate: now,
                isAllDay: false,
                snoozedUntil: nil,
                frictionLevel: 2,
                contextTag: "phone"
            )
        ]
        #expect(store.save(snapshot: source))
        #expect(
            store.enqueue(
                WatchMutation(
                    profileID: profileID,
                    kind: .completeAgendaItem,
                    agendaItemID: agendaID
                )
            )
        )
        #expect(
            store.enqueue(
                WatchMutation(
                    profileID: profileID,
                    kind: .captureTask,
                    captureTitle: "Refill vitamins"
                )
            )
        )

        let presented = try #require(store.presentationSnapshot(at: now))
        #expect(presented.agendaItems.isEmpty)
        #expect(presented.backlogTasks.map(\.title) == ["Refill vitamins"])

        source.profileID = nil
        source.snapshotID = UUID()
        source.generatedAt = now.addingTimeInterval(1)
        #expect(store.save(snapshot: source))
        #expect(store.presentationSnapshot(at: now.addingTimeInterval(1)) == nil)
    }

    private func snapshot(id: UUID, generatedAt: Date, profileID: UUID) -> WatchSnapshot {
        WatchSnapshot(
            schemaVersion: WatchSyncContract.schemaVersion,
            snapshotID: id,
            generatedAt: generatedAt,
            profileID: profileID,
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
