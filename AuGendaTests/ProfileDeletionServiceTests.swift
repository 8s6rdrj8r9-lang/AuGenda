import SwiftData
import XCTest
@testable import AuGenda

final class ProfileDeletionServiceTests: XCTestCase {

    @MainActor
    func testDeletionIsBlockedWhileProfileOwnsRecords() throws {
        let container = AppContainer.makeTestContainer()
        let first = Profile(name: "First", sortOrder: 0)
        let second = Profile(name: "Second", sortOrder: 1)
        let task = AgendaTask(title: "Owned")
        task.assignedToProfileID = first.clientID
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        container.mainContext.insert(task)
        try container.mainContext.save()

        XCTAssertThrowsError(
            try ProfileDeletionService.delete(
                profileIDs: [first.clientID],
                in: container.mainContext
            )
        ) { error in
            guard case ProfileDeletionError.ownsRecords(1) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(
            try container.mainContext.fetch(FetchDescriptor<Profile>()).count,
            2
        )
    }

    @MainActor
    func testDeletionClearsHistoricalAssignerReferences() throws {
        let container = AppContainer.makeTestContainer()
        let first = Profile(name: "First", sortOrder: 0)
        let second = Profile(name: "Second", sortOrder: 1)
        let item = AgendaItem(title: "Assigned", scheduledDate: .now)
        item.assignedToProfileID = second.clientID
        item.assignedByProfileID = first.clientID
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        container.mainContext.insert(item)
        try container.mainContext.save()

        let remainingID = try ProfileDeletionService.delete(
            profileIDs: [first.clientID],
            in: container.mainContext
        )

        XCTAssertEqual(remainingID, second.clientID)
        XCTAssertNil(item.assignedByProfileID)
        XCTAssertEqual(
            try container.mainContext.fetch(FetchDescriptor<Profile>()).map(\.clientID),
            [second.clientID]
        )
    }
}
