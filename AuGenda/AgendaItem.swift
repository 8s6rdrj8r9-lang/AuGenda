// AgendaItem.swift
// AUDHD Agenda App
//
// Primary agenda model. CloudKit-compatible:
// - All properties have defaults or are optional
// - No @Attribute(.unique) constraints
// - Relationships are optional on both sides

import Foundation
import SwiftData

@Model
final class AgendaItem {

    // MARK: - Identity
    /// Stable client-generated ID for deduplication (CloudKit has no unique constraints)
    var clientID: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    // MARK: - Content
    var title: String = ""
    var notes: String = ""

    // MARK: - Scheduling
    var scheduledDate: Date = Date.now
    var dueDate: Date? = nil
    var isAllDay: Bool = false

    // MARK: - ND-specific state
    /// Snooze: defer this item without losing it
    var snoozedUntil: Date? = nil

    /// Friction level: how hard does starting this feel right now (1–5)
    /// Used to surface low-friction tasks when executive function is low
    var frictionLevel: Int = 3

    /// Energy level required (1 = low, 3 = high)
    var energyRequired: Int = 2

    /// Context tag: where/what this task needs (e.g. "home", "phone", "focus", "errand")
    var contextTag: String = ""

    /// Body double mode: flag tasks that benefit from accountability presence
    var needsBodyDouble: Bool = false

    /// Interest level (1 = tedious, 5 = genuinely interesting). Default 3
    /// (neutral). Lets calendar items participate in the difficulty engine
    /// alongside AgendaTask.
    var interestLevel: Int = 3

    // MARK: - Difficulty axes (six-axis difficulty model)
    //
    // All default to 0/false so existing data renders correctly without
    // migration. See memory/task_difficulty_and_ai_enrichment.md for the
    // formula + rationale.

    /// Sensory load: environmental noise / light / smell / texture / crowd
    /// exposure (0 = none, 3 = severe).
    var sensoryLoad: Int = 0

    /// Social load: synchronous communication weight (0 = solo, 3 = unknown
    /// caller / negotiation).
    var socialLoad: Int = 0

    /// Initiation cost: first-step paralysis / dread weight, independent of
    /// execution friction.
    var initiationCost: Int = 0

    /// Hyperfocus override — forces inclusion in survival mode regardless of
    /// computed rank.
    var specialInterest: Bool = false

    /// Per-task AI enrichment opt-out.
    var excludeFromAI: Bool = false

    // MARK: - Completion
    var isComplete: Bool = false
    var completedAt: Date? = nil

    // MARK: - Priority & ordering
    var priority: Int = 0          // 0 = normal, 1 = high, 2 = urgent
    var sortOrder: Int = 0

    // MARK: - Recurrence (simple string rule, e.g. "daily", "weekly", "none")
    var recurrenceRule: String = "none"
    var recurrenceParentID: UUID? = nil   // links a generated instance back to its template

    // MARK: - Assignment
    /// Profile this item is assigned to (UUID stored directly — avoids CloudKit relationship limits)
    var assignedToProfileID: UUID? = nil
    /// Profile that created/assigned this item (nil = self-assigned)
    var assignedByProfileID: UUID? = nil

    // MARK: - Relationships
    @Relationship(deleteRule: .cascade, inverse: \SubTask.parentItem)
    var subTasks: [SubTask]? = nil

    // MARK: - Init
    init(
        title: String = "",
        scheduledDate: Date = .now,
        priority: Int = 0,
        frictionLevel: Int = 3,
        energyRequired: Int = 2,
        contextTag: String = "",
        recurrenceRule: String = "none"
    ) {
        self.clientID = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.title = title
        self.scheduledDate = scheduledDate
        self.priority = priority
        self.frictionLevel = frictionLevel
        self.energyRequired = energyRequired
        self.contextTag = contextTag
        self.recurrenceRule = recurrenceRule
    }
}


// MARK: - SubTask

@Model
final class SubTask {

    var clientID: UUID = UUID()
    var createdAt: Date = Date.now

    var title: String = ""
    var isComplete: Bool = false
    var sortOrder: Int = 0

    // Relationship back to parent — optional for CloudKit compatibility
    var parentItem: AgendaItem? = nil

    init(title: String = "", sortOrder: Int = 0) {
        self.clientID = UUID()
        self.createdAt = .now
        self.title = title
        self.sortOrder = sortOrder
    }
}
