//
//  AuGendaWatch_Watch_AppTests.swift
//  AuGendaWatch Watch AppTests
//
//  Created by Arthur Ens on 2026-05-29.
//

import Testing
import Foundation
@testable import AuGendaWatch_Watch_App

struct AuGendaWatch_Watch_AppTests {

    @Test func staleSnapshotDoesNotExposeTaskContent() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = WatchSnapshot(
            schemaVersion: WatchSyncContract.schemaVersion,
            snapshotID: UUID(),
            generatedAt: now.addingTimeInterval(
                -(WatchSyncContract.snapshotMaxAge + 1)
            ),
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

        #expect(!snapshot.isFresh(at: now))
    }

}
