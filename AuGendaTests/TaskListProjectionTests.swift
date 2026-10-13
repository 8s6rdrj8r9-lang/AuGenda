import Foundation
import Testing
@testable import AuGenda

@MainActor
struct TaskListProjectionTests {
    private let activeProfileID = UUID(
        uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    )!
    private let otherProfileID = UUID(
        uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
    )!
    private let referenceDate = Date(timeIntervalSince1970: 1_774_358_400)

    @Test func backlogProjectionAppliesProfileLifecycleAndBlockingInOnePass() {
        let source = task(index: 0, assignedTo: activeProfileID)
        let blocked = task(index: 1, assignedTo: activeProfileID)
        let otherProfile = task(index: 2, assignedTo: otherProfileID)
        let legacyUnassigned = task(index: 3, assignedTo: nil)
        let deferred = task(index: 4, assignedTo: activeProfileID)
        deferred.isDeferredUntil = referenceDate.addingTimeInterval(3_600)
        let relationship = TaskRelationship(
            sourceTaskID: source.clientID,
            targetTaskID: blocked.clientID,
            type: .blocks
        )

        let result = BacklogProjection.make(
            tasks: [source, blocked, otherProfile, legacyUnassigned, deferred],
            relationships: [relationship],
            activeProfileID: activeProfileID,
            filter: .all,
            sortMode: .sortOrder,
            energyLevel: 4,
            now: referenceDate
        )

        #expect(result.tasks.map(\.clientID) == [
            source.clientID,
            legacyUnassigned.clientID
        ])
        #expect(result.actionableCount == 2)
    }

    @Test func backlogProjectionHasDeterministicOrdering() {
        let tasks = (0..<200).map {
            task(index: $0, assignedTo: activeProfileID)
        }
        var generator = SeededGenerator(seed: 42)
        let shuffled = tasks.shuffled(using: &generator)
        let first = BacklogProjection.make(
            tasks: Array(tasks.reversed()),
            relationships: [],
            activeProfileID: activeProfileID,
            filter: .all,
            sortMode: .ndPriority,
            energyLevel: 4,
            now: referenceDate
        )
        let second = BacklogProjection.make(
            tasks: shuffled,
            relationships: [],
            activeProfileID: activeProfileID,
            filter: .all,
            sortMode: .ndPriority,
            energyLevel: 4,
            now: referenceDate
        )

        #expect(first.tasks.map(\.clientID) == second.tasks.map(\.clientID))
    }

    @Test func oneThousandRecordProjectionStaysWithinBudget() {
        assertProjectionBudget(recordCount: 1_000, budgetSeconds: 1.0)
    }

    @Test func tenThousandRecordProjectionStaysWithinBudget() {
        // Debug + coverage instrumentation is intentionally much slower than
        // the Release/Instruments gate. This ceiling catches accidental
        // quadratic/N+1 regressions without pretending to be a frame budget.
        assertProjectionBudget(recordCount: 10_000, budgetSeconds: 15.0)
    }

    private func assertProjectionBudget(
        recordCount: Int,
        budgetSeconds: TimeInterval
    ) {
        let tasks = (0..<recordCount).map { index in
            task(
                index: index,
                assignedTo: index.isMultiple(of: 3) ? activeProfileID : nil
            )
        }
        let relationships = stride(from: 1, to: recordCount, by: 20).map { target in
            TaskRelationship(
                sourceTaskID: tasks[target - 1].clientID,
                targetTaskID: tasks[target].clientID,
                type: .blocks
            )
        }
        let items = (0..<recordCount).map { index in
            let item = AgendaItem(
                title: "Item \(index)",
                scheduledDate: referenceDate.addingTimeInterval(
                    Double(index % 72) * 3_600
                )
            )
            item.clientID = deterministicUUID(index + recordCount)
            item.assignedToProfileID = index.isMultiple(of: 4)
                ? activeProfileID
                : nil
            item.frictionLevel = index % 4 + 1
            return item
        }

        let started = ProcessInfo.processInfo.systemUptime
        let backlog = BacklogProjection.make(
            tasks: tasks,
            relationships: relationships,
            activeProfileID: activeProfileID,
            filter: .suggest,
            sortMode: .ndPriority,
            energyLevel: 3,
            now: referenceDate
        )
        let dashboard = HomeDashboardProjection.make(
            items: items,
            tasks: tasks,
            relationships: relationships,
            blocks: [],
            completedItems: [],
            activeProfileID: activeProfileID,
            density: .functional,
            now: referenceDate
        )
        let elapsed = ProcessInfo.processInfo.systemUptime - started

        #expect(!backlog.tasks.isEmpty)
        #expect(!dashboard.profileTasks.isEmpty)
        #expect(
            elapsed < budgetSeconds,
            "Projection took \(elapsed.formatted(.number.precision(.fractionLength(3))))s; budget is \(budgetSeconds)s"
        )
    }

    private func task(index: Int, assignedTo profileID: UUID?) -> AgendaTask {
        let task = AgendaTask(
            title: "Task \(index)",
            frictionLevel: index % 4 + 1,
            energyRequired: index % 4 + 1,
            priority: index % 3,
            interestLevel: index % 5 + 1
        )
        task.clientID = deterministicUUID(index)
        task.sortOrder = index
        task.assignedToProfileID = profileID
        task.waitingOn = index.isMultiple(of: 11) ? "Response" : ""
        task.dueDate = referenceDate.addingTimeInterval(
            Double(index % 30) * 86_400
        )
        return task
    }

    private func deterministicUUID(_ value: Int) -> UUID {
        let suffix = String(format: "%012llX", Int64(value))
        return UUID(
            uuidString: "00000000-0000-0000-0000-\(suffix)"
        )!
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}
