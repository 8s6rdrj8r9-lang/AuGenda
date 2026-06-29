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

    // MARK: - Difficulty axes (introduced for the six-axis difficulty model)
    //
    // All default to 0 so existing data renders correctly without migration.
    // See memory/task_difficulty_and_ai_enrichment.md for the formula + rationale.

    /// Sensory load: environmental noise / light / smell / texture / crowd
    /// exposure (0 = none, 3 = severe). Critical for autism profiles —
    /// rates the ENVIRONMENT the task happens in, not the task content.
    var sensoryLoad: Int = 0

    /// Social load: synchronous communication weight.
    /// 0 = solo, 1 = async (email/text), 2 = known scheduled call, 3 = unknown
    /// caller / negotiation / confrontation.
    var socialLoad: Int = 0

    /// Initiation cost: first-step paralysis / dread weight, independent of
    /// execution friction. A 30-second action can have initiation=3 (the
    /// IRS-letter problem). Weighted heavily in the difficulty formula.
    var initiationCost: Int = 0

    /// Hyperfocus override — forces inclusion in survival mode regardless of
    /// computed difficulty rank. Lets the user opt their special-interest
    /// tasks past the rank filter when they explicitly want to do them.
    var specialInterest: Bool = false

    /// Per-task AI enrichment opt-out. Hides the "Enrich" button on this
    /// task and skips it from auto-enrich. Use for explicitly sensitive
    /// items the user doesn't want sent to any cloud provider.
    var excludeFromAI: Bool = false

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

    /// Returns true if any incomplete task blocks or must precede this task.
    /// Call this in the view layer where ModelContext is available.
    func isBlocked(in context: ModelContext) -> Bool {
        let taskID = self.clientID
        let descriptor = FetchDescriptor<TaskRelationship>(
            predicate: #Predicate {
                $0.targetTaskID == taskID
                && ($0.typeRaw == "blocks" || $0.typeRaw == "follows")
            }
        )
        guard let relationships = try? context.fetch(descriptor) else { return false }
        for rel in relationships {
            let sourceID = rel.sourceTaskID
            let sourceDescriptor = FetchDescriptor<AgendaTask>(
                predicate: #Predicate { $0.clientID == sourceID }
            )
            if let source = (try? context.fetch(sourceDescriptor))?.first, !source.isComplete {
                return true
            }
        }
        return false
    }
}
