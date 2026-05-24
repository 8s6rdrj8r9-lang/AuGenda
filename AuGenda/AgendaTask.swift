// AgendaTask.swift
// AUDHD Agenda App
//
// Renamed from Task.swift to avoid collision with Swift's built-in Task concurrency type.
// Discrete actionable task model, separate from AgendaItem (which is schedule-anchored).
// A AgendaTask can exist without a scheduled time — it lives in the backlog until assigned.
// CloudKit-compatible: all properties have defaults or are optional.

import Foundation
import SwiftData

@Model
final class AgendaTask {

    // MARK: - Identity
    var clientID: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // MARK: - Content
    var title: String = ""
    var notes: String = ""

    // MARK: - Scheduling (optional — unscheduled tasks live in backlog)
    var scheduledDate: Date? = nil
    var dueDate: Date? = nil

    // MARK: - ND-specific fields

    /// How hard does starting this feel (1 = easy, 5 = wall)
    var frictionLevel: Int = 3

    /// Energy cost to complete (1 = low, 3 = high)
    var energyRequired: Int = 2

    /// Estimated duration in minutes — ND time blindness mitigation
    var estimatedMinutes: Int = 15

    /// Context tag: what conditions this task needs
    var contextTag: String = ""

    /// Hyperfocus potential: tasks that might absorb excessive time
    var hyperfocusRisk: Bool = false

    /// Body double flag
    var needsBodyDouble: Bool = false

    /// Waiting on: blocked by something external
    var waitingOn: String = ""

    /// Interest level (1 = tedious, 5 = genuinely interesting)
    var interestLevel: Int = 3

    // MARK: - Priority & ordering
    var priority: Int = 0
    var sortOrder: Int = 0

    // MARK: - State
    var isComplete: Bool = false
    var completedAt: Date? = nil
    var isDeferredUntil: Date? = nil
    var isAbandoned: Bool = false
    var abandonedAt: Date? = nil
    var abandonReason: String = ""

    // MARK: - Recurrence
    var recurrenceRule: String = "none"
    var recurrenceParentID: UUID? = nil

    // MARK: - Assignment
    /// Profile this task is assigned to (UUID stored directly — avoids CloudKit relationship limits)
    var assignedToProfileID: UUID? = nil
    /// Profile that created/assigned this task (nil = self-assigned)
    var assignedByProfileID: UUID? = nil

    // MARK: - Relationships
    var agendaItemID: UUID? = nil

    @Relationship(deleteRule: .cascade, inverse: \TaskStep.parentTask)
    var steps: [TaskStep]? = nil

    // MARK: - Init
    init(
        title: String = "",
        frictionLevel: Int = 3,
        energyRequired: Int = 2,
        estimatedMinutes: Int = 15,
        contextTag: String = "",
        priority: Int = 0,
        interestLevel: Int = 3
    ) {
        self.clientID = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.title = title
        self.frictionLevel = frictionLevel
        self.energyRequired = energyRequired
        self.estimatedMinutes = estimatedMinutes
        self.contextTag = contextTag
        self.priority = priority
        self.interestLevel = interestLevel
    }
}


// MARK: - TaskStep

@Model
final class TaskStep {

    var clientID: UUID = UUID()
    var createdAt: Date = Date.now

    var title: String = ""
    var isComplete: Bool = false
    var sortOrder: Int = 0
    var estimatedMinutes: Int = 5

    var parentTask: AgendaTask? = nil

    init(title: String = "", estimatedMinutes: Int = 5, sortOrder: Int = 0) {
        self.clientID = UUID()
        self.createdAt = .now
        self.title = title
        self.estimatedMinutes = estimatedMinutes
        self.sortOrder = sortOrder
    }
}


// MARK: - Computed helpers

extension AgendaTask {

    var ndPriorityScore: Double {
        let priorityWeight = Double(priority) * 3.0
        let interestWeight = Double(interestLevel) * 1.5
        let frictionPenalty = Double(frictionLevel) * -1.0
        let energyPenalty = Double(energyRequired) * -0.5
        return priorityWeight + interestWeight + frictionPenalty + energyPenalty
    }

    var isActionable: Bool {
        guard !isComplete, !isAbandoned else { return false }
        if let deferDate = isDeferredUntil {
            return deferDate <= .now
        }
        return true
    }

    var totalEstimatedMinutes: Int {
        guard let steps = steps, !steps.isEmpty else { return estimatedMinutes }
        return steps.reduce(0) { $0 + $1.estimatedMinutes }
    }
}
