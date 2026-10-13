// TaskListProjection.swift
// AuGenda
//
// Pure, deterministic list projections used by the two highest-traffic task
// surfaces. Relationship state is indexed once, avoiding one SwiftData fetch
// per row during filtering.

import Foundation

enum TaskProjectionIndex {
    static func blockedTaskIDs(
        tasks: [AgendaTask],
        relationships: [TaskRelationship]
    ) -> Set<UUID> {
        let activeSourceIDs = Set(
            tasks.lazy
                .filter { !$0.isComplete && !$0.isAbandoned }
                .map(\.clientID)
        )
        return Set(
            relationships.lazy.compactMap { relationship in
                guard
                    relationship.typeRaw == TaskRelationshipType.blocks.rawValue
                        || relationship.typeRaw == TaskRelationshipType.follows.rawValue,
                    activeSourceIDs.contains(relationship.sourceTaskID)
                else {
                    return nil
                }
                return relationship.targetTaskID
            }
        )
    }

    static func belongsToProfile(
        assignedProfileID: UUID?,
        activeProfileID: UUID?
    ) -> Bool {
        assignedProfileID == nil || assignedProfileID == activeProfileID
    }

    static func isLifecycleActionable(_ task: AgendaTask, now: Date) -> Bool {
        guard !task.isComplete, !task.isAbandoned else { return false }
        return task.isDeferredUntil == nil || task.isDeferredUntil! <= now
    }
}

struct BacklogProjection {
    let tasks: [AgendaTask]
    let actionableCount: Int

    static func make(
        tasks source: [AgendaTask],
        relationships: [TaskRelationship],
        activeProfileID: UUID?,
        filter: TaskFilter,
        sortMode: BacklogSortMode,
        energyLevel: Int,
        now: Date = .now
    ) -> BacklogProjection {
        let blockedIDs = TaskProjectionIndex.blockedTaskIDs(
            tasks: source,
            relationships: relationships
        )

        var actionableCount = 0
        var matches: [AgendaTask] = []
        matches.reserveCapacity(min(source.count, 1_000))

        for task in source {
            guard TaskProjectionIndex.belongsToProfile(
                assignedProfileID: task.assignedToProfileID,
                activeProfileID: activeProfileID
            ) else {
                continue
            }

            let actionable = TaskProjectionIndex.isLifecycleActionable(task, now: now)
                && !blockedIDs.contains(task.clientID)
            if actionable {
                actionableCount += 1
            }

            switch filter {
            case .all:
                if actionable { matches.append(task) }
            case .suggest:
                if actionable, task.difficultyRank <= energyLevel * 2 {
                    matches.append(task)
                }
            case .waiting:
                if !task.waitingOn.isEmpty {
                    matches.append(task)
                }
            }
        }

        matches.sort(by: comparator(for: filter, sortMode: sortMode))
        return BacklogProjection(tasks: matches, actionableCount: actionableCount)
    }

    private static func comparator(
        for filter: TaskFilter,
        sortMode: BacklogSortMode
    ) -> (AgendaTask, AgendaTask) -> Bool {
        if filter == .suggest {
            return rankedBefore
        }

        switch sortMode {
        case .sortOrder:
            return { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return stableIDBefore(lhs, rhs)
            }
        case .ndPriority:
            return rankedBefore
        case .dueDate:
            return { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (left?, right?):
                    if left != right { return left < right }
                    return stableIDBefore(lhs, rhs)
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return stableIDBefore(lhs, rhs)
                }
            }
        case .friction:
            return { lhs, rhs in
                if lhs.frictionLevel != rhs.frictionLevel {
                    return lhs.frictionLevel < rhs.frictionLevel
                }
                return stableIDBefore(lhs, rhs)
            }
        }
    }

    nonisolated private static func rankedBefore(
        _ lhs: AgendaTask,
        _ rhs: AgendaTask
    ) -> Bool {
        if lhs.ndPriorityScore != rhs.ndPriorityScore {
            return lhs.ndPriorityScore > rhs.ndPriorityScore
        }
        return stableIDBefore(lhs, rhs)
    }

    nonisolated private static func stableIDBefore(
        _ lhs: AgendaTask,
        _ rhs: AgendaTask
    ) -> Bool {
        lhs.clientID.uuidString < rhs.clientID.uuidString
    }
}

struct HomeDashboardProjection {
    let profileItems: [AgendaItem]
    let profileTasks: [AgendaTask]
    let todayItems: [AgendaItem]
    let tomorrowItems: [AgendaItem]
    let forNowTasks: [AgendaTask]
    let otherActionableTasks: [AgendaTask]
    let completedToday: [AgendaItem]
    let activeBlocks: [Block]

    static func make(
        items: [AgendaItem],
        tasks: [AgendaTask],
        relationships: [TaskRelationship],
        blocks: [Block],
        completedItems: [AgendaItem],
        activeProfileID: UUID?,
        density: DensityMode,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> HomeDashboardProjection {
        let blockedIDs = TaskProjectionIndex.blockedTaskIDs(
            tasks: tasks,
            relationships: relationships
        )
        let todayEnd = calendar.endOfDay(for: now)
        let tomorrowStart = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        )
        let tomorrowEnd = tomorrowStart.map { calendar.endOfDay(for: $0) }

        var profileItems: [AgendaItem] = []
        var todayItems: [AgendaItem] = []
        var tomorrowItems: [AgendaItem] = []
        profileItems.reserveCapacity(items.count)

        // `items` arrives query-sorted by scheduledDate, so filtering preserves
        // the order needed by the primary and momentum surfaces.
        for item in items {
            guard TaskProjectionIndex.belongsToProfile(
                assignedProfileID: item.assignedToProfileID,
                activeProfileID: activeProfileID
            ) else {
                continue
            }
            profileItems.append(item)

            if (item.snoozedUntil == nil || item.snoozedUntil! <= now),
               item.scheduledDate <= todayEnd,
               item.passes(densityFilter: density) {
                todayItems.append(item)
            }
            if let tomorrowStart, let tomorrowEnd,
               item.scheduledDate >= tomorrowStart,
               item.scheduledDate <= tomorrowEnd {
                tomorrowItems.append(item)
            }
        }

        var profileTasks: [AgendaTask] = []
        var actionableTasks: [AgendaTask] = []
        profileTasks.reserveCapacity(tasks.count)
        actionableTasks.reserveCapacity(tasks.count)
        for task in tasks {
            guard TaskProjectionIndex.belongsToProfile(
                assignedProfileID: task.assignedToProfileID,
                activeProfileID: activeProfileID
            ) else {
                continue
            }
            profileTasks.append(task)
            if TaskProjectionIndex.isLifecycleActionable(task, now: now),
               !blockedIDs.contains(task.clientID) {
                actionableTasks.append(task)
            }
        }
        actionableTasks.sort {
            if $0.ndPriorityScore != $1.ndPriorityScore {
                return $0.ndPriorityScore > $1.ndPriorityScore
            }
            return $0.clientID.uuidString < $1.clientID.uuidString
        }

        var forNowTasks: [AgendaTask] = []
        var otherActionableTasks: [AgendaTask] = []
        for task in actionableTasks {
            if task.passes(densityFilter: density) {
                forNowTasks.append(task)
            } else {
                otherActionableTasks.append(task)
            }
        }

        let completedToday = Array(
            completedItems.lazy
                .filter { item in
                    guard
                        let completedAt = item.completedAt,
                        calendar.isDate(completedAt, inSameDayAs: now)
                    else {
                        return false
                    }
                    return TaskProjectionIndex.belongsToProfile(
                        assignedProfileID: item.assignedToProfileID,
                        activeProfileID: activeProfileID
                    )
                }
                .prefix(5)
        )

        return HomeDashboardProjection(
            profileItems: profileItems,
            profileTasks: profileTasks,
            todayItems: todayItems,
            tomorrowItems: tomorrowItems,
            forNowTasks: forNowTasks,
            otherActionableTasks: otherActionableTasks,
            completedToday: completedToday,
            activeBlocks: blocks.filter { !$0.isComplete }
        )
    }
}
