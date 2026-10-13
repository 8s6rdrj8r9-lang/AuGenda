// TaskLifecycle.swift
// AuGenda
//
// Centralized, persisted state transitions for task completion/abandonment
// and the deliberately small recurrence feature set supported by the UI.

import Foundation
import SwiftData

enum RecurrenceRule: String, CaseIterable, Identifiable, Codable {
    case none
    case daily
    case weekdays
    case weekly
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "Does not repeat"
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

enum TaskLifecycleError: LocalizedError {
    case invalidTransition(String)
    case missingAbandonReason
    case recurrenceNeedsDate
    case unsupportedRecurrenceRule(String)

    var errorDescription: String? {
        switch self {
        case .invalidTransition(let detail):
            return detail
        case .missingAbandonReason:
            return "Choose a reason before abandoning this task."
        case .recurrenceNeedsDate:
            return "A repeating backlog task needs a due date."
        case .unsupportedRecurrenceRule(let rawValue):
            return "This task uses an unsupported recurrence rule (\(rawValue)). Choose Does not repeat, Daily, Weekdays, Weekly, or Monthly before completing it."
        }
    }
}

/// Pure calendar arithmetic shared by both persisted task types.
///
/// The supported subset is intentionally explicit. Each completion advances
/// to the first occurrence strictly after `referenceDate`, so completing an
/// overdue occurrence cannot create a burst of historical catch-up records.
enum RecurrenceCalendar {
    static func nextOccurrence(
        after anchor: Date,
        referenceDate: Date,
        rule: RecurrenceRule,
        calendar: Calendar = .current
    ) -> Date? {
        guard rule != .none else { return nil }

        switch rule {
        case .none:
            return nil
        case .daily:
            return nextDayBasedOccurrence(
                after: anchor,
                referenceDate: referenceDate,
                dayInterval: 1,
                calendar: calendar
            )
        case .weekdays:
            return nextWeekdayOccurrence(
                after: anchor,
                referenceDate: referenceDate,
                calendar: calendar
            )
        case .weekly:
            return nextDayBasedOccurrence(
                after: anchor,
                referenceDate: referenceDate,
                dayInterval: 7,
                calendar: calendar
            )
        case .monthly:
            return nextMonthlyOccurrence(
                after: anchor,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
    }

    private static func nextWeekdayOccurrence(
        after anchor: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        let anchorTime = calendar.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: anchor
        )
        var candidateDay = calendar.startOfDay(for: max(anchor, referenceDate))

        // At most the current day plus the next seven days are needed to find
        // a weekday. Rebuild the candidate from calendar components so DST
        // transitions preserve the user's intended local wall-clock time.
        for _ in 0..<8 {
            var components = calendar.dateComponents(
                [.era, .year, .month, .day],
                from: candidateDay
            )
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.hour = anchorTime.hour
            components.minute = anchorTime.minute
            components.second = anchorTime.second
            components.nanosecond = anchorTime.nanosecond

            if let candidate = calendar.date(from: components),
               candidate > anchor,
               candidate > referenceDate,
               !calendar.isDateInWeekend(candidate) {
                return candidate
            }

            guard let followingDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: candidateDay
            ) else {
                return nil
            }
            candidateDay = followingDay
        }
        return nil
    }

    private static func nextDayBasedOccurrence(
        after anchor: Date,
        referenceDate: Date,
        dayInterval: Int,
        calendar: Calendar
    ) -> Date? {
        let anchorDay = calendar.startOfDay(for: anchor)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let elapsedDays = max(
            0,
            calendar.dateComponents([.day], from: anchorDay, to: referenceDay).day ?? 0
        )
        let completedIntervals = elapsedDays / dayInterval
        var intervalCount = max(1, completedIntervals)

        guard var candidate = calendar.date(
            byAdding: .day,
            value: intervalCount * dayInterval,
            to: anchor
        ) else {
            return nil
        }

        // At most one extra step is normally required. Keep the small loop to
        // cover unusual calendar transitions without unbounded iteration.
        while candidate <= referenceDate, intervalCount <= completedIntervals + 2 {
            intervalCount += 1
            guard let advanced = calendar.date(
                byAdding: .day,
                value: dayInterval,
                to: candidate
            ) else {
                return nil
            }
            candidate = advanced
        }
        return candidate > referenceDate ? candidate : nil
    }

    private static func nextMonthlyOccurrence(
        after anchor: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        let anchorParts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: anchor
        )
        let referenceParts = calendar.dateComponents([.year, .month], from: referenceDate)
        guard
            let anchorYear = anchorParts.year,
            let anchorMonth = anchorParts.month,
            let anchorDay = anchorParts.day,
            let referenceYear = referenceParts.year,
            let referenceMonth = referenceParts.month
        else {
            return nil
        }

        let elapsedMonths = max(
            0,
            (referenceYear - anchorYear) * 12 + (referenceMonth - anchorMonth)
        )
        var monthOffset = max(1, elapsedMonths)
        var candidate = clampedMonthlyDate(
            anchorParts: anchorParts,
            preferredDay: anchorDay,
            monthOffset: monthOffset,
            calendar: calendar
        )

        while let date = candidate, date <= referenceDate, monthOffset <= elapsedMonths + 2 {
            monthOffset += 1
            candidate = clampedMonthlyDate(
                anchorParts: anchorParts,
                preferredDay: anchorDay,
                monthOffset: monthOffset,
                calendar: calendar
            )
        }
        guard let candidate, candidate > referenceDate else { return nil }
        return candidate
    }

    /// Calendar's direct `.month` addition can spill January 31 into March.
    /// Build the destination month explicitly and clamp to its last valid day.
    private static func clampedMonthlyDate(
        anchorParts: DateComponents,
        preferredDay: Int,
        monthOffset: Int,
        calendar: Calendar
    ) -> Date? {
        guard
            let year = anchorParts.year,
            let month = anchorParts.month
        else {
            return nil
        }

        let zeroBasedMonth = (month - 1) + monthOffset
        let destinationYear = year + zeroBasedMonth / 12
        let destinationMonth = zeroBasedMonth % 12 + 1

        var monthStartParts = DateComponents()
        monthStartParts.calendar = calendar
        monthStartParts.timeZone = calendar.timeZone
        monthStartParts.year = destinationYear
        monthStartParts.month = destinationMonth
        monthStartParts.day = 1
        guard
            let monthStart = calendar.date(from: monthStartParts),
            let validDays = calendar.range(of: .day, in: .month, for: monthStart)
        else {
            return nil
        }

        var result = DateComponents()
        result.calendar = calendar
        result.timeZone = calendar.timeZone
        result.year = destinationYear
        result.month = destinationMonth
        result.day = min(preferredDay, validDays.count)
        result.hour = anchorParts.hour
        result.minute = anchorParts.minute
        result.second = anchorParts.second
        result.nanosecond = anchorParts.nanosecond
        return calendar.date(from: result)
    }
}

/// The single mutation boundary for `AgendaTask` lifecycle state.
@MainActor
enum TaskLifecycleService {
    /// Complete a backlog task and materialize the next supported occurrence
    /// in the same save. Returns that occurrence (new or already present).
    @discardableResult
    static func complete(
        _ task: AgendaTask,
        in context: ModelContext,
        at completionDate: Date = .now,
        calendar: Calendar = .current
    ) throws -> AgendaTask? {
        guard !task.isAbandoned else {
            throw TaskLifecycleError.invalidTransition(
                "Reopen this abandoned task before completing it."
            )
        }

        let effectiveCompletionDate = task.completedAt ?? completionDate

        // Validate/materialize recurrence before mutating the source so an
        // unsupported transition (for example, no recurrence anchor) leaves
        // the task untouched. Replays reuse the first persisted completion
        // instant, so a delayed notification cannot advance the series twice.
        let next: AgendaTask?
        do {
            next = try materializeNextOccurrence(
                for: task,
                in: context,
                after: effectiveCompletionDate,
                calendar: calendar
            )
        } catch {
            context.rollback()
            throw error
        }
        task.isComplete = true
        task.completedAt = effectiveCompletionDate
        task.isDeferredUntil = nil
        task.updatedAt = max(task.updatedAt, effectiveCompletionDate)

        try saveOrRollback(context)
        return next
    }

    static func abandon(
        _ task: AgendaTask,
        reason: String,
        in context: ModelContext,
        at date: Date = .now
    ) throws {
        guard !task.isComplete else {
            throw TaskLifecycleError.invalidTransition(
                "Reopen this completed task before abandoning it."
            )
        }
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReason.isEmpty else {
            throw TaskLifecycleError.missingAbandonReason
        }

        task.isAbandoned = true
        task.abandonedAt = date
        task.abandonReason = normalizedReason
        task.isDeferredUntil = nil
        task.updatedAt = date
        try saveOrRollback(context)
    }

    static func reopen(
        _ task: AgendaTask,
        in context: ModelContext,
        at date: Date = .now
    ) throws {
        task.isComplete = false
        task.completedAt = nil
        task.isAbandoned = false
        task.abandonedAt = nil
        task.abandonReason = ""
        task.updatedAt = date
        try saveOrRollback(context)
    }

    private static func materializeNextOccurrence(
        for task: AgendaTask,
        in context: ModelContext,
        after completionDate: Date,
        calendar: Calendar
    ) throws -> AgendaTask? {
        if task.recurrenceRule == RecurrenceRule.none.rawValue {
            return nil
        }
        guard let rule = RecurrenceRule(rawValue: task.recurrenceRule) else {
            throw TaskLifecycleError.unsupportedRecurrenceRule(
                task.recurrenceRule
            )
        }

        let seriesID = task.recurrenceParentID ?? task.clientID
        var recurrenceTemplate = task
        if task.recurrenceParentID != nil {
            var templateDescriptor = FetchDescriptor<AgendaTask>(
                predicate: #Predicate { $0.clientID == seriesID }
            )
            templateDescriptor.fetchLimit = 1
            recurrenceTemplate = try context.fetch(templateDescriptor).first ?? task
        }

        let anchor: Date
        let currentAnchor: Date
        let usesScheduledDate: Bool
        if let scheduledDate = recurrenceTemplate.scheduledDate,
           let currentScheduledDate = task.scheduledDate {
            anchor = scheduledDate
            currentAnchor = currentScheduledDate
            usesScheduledDate = true
        } else if let dueDate = recurrenceTemplate.dueDate,
                  let currentDueDate = task.dueDate {
            anchor = dueDate
            currentAnchor = currentDueDate
            usesScheduledDate = false
        } else {
            throw TaskLifecycleError.recurrenceNeedsDate
        }

        // Preserve the series cadence, but never select the occurrence being
        // completed when the user finishes it ahead of its scheduled time.
        guard let nextAnchor = RecurrenceCalendar.nextOccurrence(
            after: anchor,
            referenceDate: max(completionDate, currentAnchor),
            rule: rule,
            calendar: calendar
        ) else {
            return nil
        }

        if let existing = try existingTaskOccurrence(
            seriesID: seriesID,
            anchor: nextAnchor,
            usesScheduledDate: usesScheduledDate,
            in: context
        ) {
            return existing
        }

        let next = AgendaTask(
            title: task.title,
            frictionLevel: task.frictionLevel,
            energyRequired: task.energyRequired,
            estimatedMinutes: task.estimatedMinutes,
            contextTag: task.contextTag,
            priority: task.priority,
            interestLevel: task.interestLevel
        )
        next.notes = task.notes
        next.scheduledDate = usesScheduledDate ? nextAnchor : nil
        if usesScheduledDate, let dueDate = task.dueDate {
            next.dueDate = nextAnchor.addingTimeInterval(
                dueDate.timeIntervalSince(currentAnchor)
            )
        } else {
            next.dueDate = nextAnchor
        }
        next.hyperfocusRisk = task.hyperfocusRisk
        next.needsBodyDouble = task.needsBodyDouble
        next.waitingOn = task.waitingOn
        next.sensoryLoad = task.sensoryLoad
        next.socialLoad = task.socialLoad
        next.initiationCost = task.initiationCost
        next.specialInterest = task.specialInterest
        next.excludeFromAI = task.excludeFromAI
        next.sortOrder = task.sortOrder
        next.recurrenceRule = rule.rawValue
        next.recurrenceParentID = seriesID
        next.assignedToProfileID = task.assignedToProfileID
        next.assignedByProfileID = task.assignedByProfileID

        let copiedSteps = (task.steps ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { source in
                let step = TaskStep(
                    title: source.title,
                    estimatedMinutes: source.estimatedMinutes,
                    sortOrder: source.sortOrder
                )
                step.parentTask = next
                context.insert(step)
                return step
            }
        next.steps = copiedSteps.isEmpty ? nil : copiedSteps
        context.insert(next)
        return next
    }

    private static func existingTaskOccurrence(
        seriesID: UUID,
        anchor: Date,
        usesScheduledDate: Bool,
        in context: ModelContext
    ) throws -> AgendaTask? {
        var descriptor: FetchDescriptor<AgendaTask>
        if usesScheduledDate {
            descriptor = FetchDescriptor(
                predicate: #Predicate {
                    $0.recurrenceParentID == seriesID && $0.scheduledDate == anchor
                }
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate {
                    $0.recurrenceParentID == seriesID
                        && $0.scheduledDate == nil
                        && $0.dueDate == anchor
                }
            )
        }
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func saveOrRollback(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

/// Agenda items have completion/reopen transitions and use the same recurrence
/// calendar, but do not expose abandonment in the product model.
@MainActor
enum AgendaItemLifecycleService {
    @discardableResult
    static func complete(
        _ item: AgendaItem,
        in context: ModelContext,
        at completionDate: Date = .now,
        calendar: Calendar = .current
    ) throws -> AgendaItem? {
        let effectiveCompletionDate = item.completedAt ?? completionDate
        let next: AgendaItem?
        do {
            next = try materializeNextOccurrence(
                for: item,
                in: context,
                after: effectiveCompletionDate,
                calendar: calendar
            )
        } catch {
            context.rollback()
            throw error
        }
        item.isComplete = true
        item.completedAt = effectiveCompletionDate
        item.snoozedUntil = nil
        item.updatedAt = max(item.updatedAt, effectiveCompletionDate)
        try saveOrRollback(context)
        return next
    }

    static func reopen(
        _ item: AgendaItem,
        in context: ModelContext,
        at date: Date = .now
    ) throws {
        item.isComplete = false
        item.completedAt = nil
        item.updatedAt = date
        try saveOrRollback(context)
    }

    private static func materializeNextOccurrence(
        for item: AgendaItem,
        in context: ModelContext,
        after completionDate: Date,
        calendar: Calendar
    ) throws -> AgendaItem? {
        if item.recurrenceRule == RecurrenceRule.none.rawValue {
            return nil
        }
        guard let rule = RecurrenceRule(rawValue: item.recurrenceRule) else {
            throw TaskLifecycleError.unsupportedRecurrenceRule(
                item.recurrenceRule
            )
        }
        let seriesID = item.recurrenceParentID ?? item.clientID
        var recurrenceAnchor = item.scheduledDate
        if item.recurrenceParentID != nil {
            var templateDescriptor = FetchDescriptor<AgendaItem>(
                predicate: #Predicate { $0.clientID == seriesID }
            )
            templateDescriptor.fetchLimit = 1
            recurrenceAnchor = try context.fetch(templateDescriptor).first?
                .scheduledDate ?? item.scheduledDate
        }

        guard
            let nextDate = RecurrenceCalendar.nextOccurrence(
                after: recurrenceAnchor,
                referenceDate: max(completionDate, item.scheduledDate),
                rule: rule,
                calendar: calendar
            )
        else {
            return nil
        }

        var descriptor = FetchDescriptor<AgendaItem>(
            predicate: #Predicate {
                $0.recurrenceParentID == seriesID && $0.scheduledDate == nextDate
            }
        )
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let next = AgendaItem(
            title: item.title,
            scheduledDate: nextDate,
            priority: item.priority,
            frictionLevel: item.frictionLevel,
            energyRequired: item.energyRequired,
            contextTag: item.contextTag,
            recurrenceRule: rule.rawValue
        )
        next.notes = item.notes
        if let dueDate = item.dueDate {
            next.dueDate = nextDate.addingTimeInterval(
                dueDate.timeIntervalSince(item.scheduledDate)
            )
        }
        next.isAllDay = item.isAllDay
        next.needsBodyDouble = item.needsBodyDouble
        next.interestLevel = item.interestLevel
        next.sensoryLoad = item.sensoryLoad
        next.socialLoad = item.socialLoad
        next.initiationCost = item.initiationCost
        next.specialInterest = item.specialInterest
        next.excludeFromAI = item.excludeFromAI
        next.sortOrder = item.sortOrder
        next.recurrenceParentID = seriesID
        next.assignedToProfileID = item.assignedToProfileID
        next.assignedByProfileID = item.assignedByProfileID

        let copiedSubtasks = (item.subTasks ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { source in
                let subtask = SubTask(title: source.title, sortOrder: source.sortOrder)
                subtask.parentItem = next
                context.insert(subtask)
                return subtask
            }
        next.subTasks = copiedSubtasks.isEmpty ? nil : copiedSubtasks
        context.insert(next)
        return next
    }

    private static func saveOrRollback(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
