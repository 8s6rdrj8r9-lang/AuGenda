import Foundation
import SwiftData
import Testing
@testable import AuGenda

@MainActor
struct TaskLifecycleTests {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 9
    ) -> Date {
        utcCalendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }

    @Test func earlyGeneratedOccurrencesAdvanceAndRemainIdempotent() throws {
        for rule in [RecurrenceRule.daily, .monthly] {
            let container = AppContainer.makeTestContainer()
            let context = container.mainContext
            let anchor = date(2027, 1, 31)
            let secondDate = rule == .daily ? date(2027, 2, 1) : date(2027, 2, 28)
            let thirdDate = rule == .daily ? date(2027, 2, 2) : date(2027, 3, 31)
            let root = AgendaTask(title: "Repeating task")
            root.dueDate = anchor
            root.recurrenceRule = rule.rawValue
            let agendaRoot = AgendaItem(title: "Repeating agenda", scheduledDate: anchor,
                                        recurrenceRule: rule.rawValue)
            context.insert(root)
            context.insert(agendaRoot)
            try context.save()

            let second = try #require(try TaskLifecycleService.complete(
                root, in: context, at: anchor, calendar: utcCalendar
            ))
            let secondItem = try #require(try AgendaItemLifecycleService.complete(
                agendaRoot, in: context, at: anchor, calendar: utcCalendar
            ))
            #expect(second.dueDate == secondDate)
            #expect(secondItem.scheduledDate == secondDate)

            let earlyCompletion = secondDate.addingTimeInterval(-3600)
            let third = try #require(try TaskLifecycleService.complete(
                second, in: context, at: earlyCompletion, calendar: utcCalendar
            ))
            let thirdItem = try #require(try AgendaItemLifecycleService.complete(
                secondItem, in: context, at: earlyCompletion, calendar: utcCalendar
            ))
            #expect(third.dueDate == thirdDate)
            #expect(thirdItem.scheduledDate == thirdDate)
            #expect(!third.isComplete)
            #expect(!thirdItem.isComplete)

            let replay = try TaskLifecycleService.complete(
                second, in: context, at: thirdDate, calendar: utcCalendar
            )
            let agendaReplay = try AgendaItemLifecycleService.complete(
                secondItem, in: context, at: thirdDate, calendar: utcCalendar
            )
            #expect(replay?.clientID == third.clientID)
            #expect(agendaReplay?.clientID == thirdItem.clientID)
            #expect(try context.fetch(FetchDescriptor<AgendaTask>()).count == 3)
            #expect(try context.fetch(FetchDescriptor<AgendaItem>()).count == 3)
        }
    }

    @Test func recurrenceCalendarAdvancesToFirstFutureOccurrence() {
        let anchor = date(2026, 1, 1)
        let completedLate = date(2026, 1, 10, hour: 12)

        #expect(
            RecurrenceCalendar.nextOccurrence(
                after: anchor,
                referenceDate: completedLate,
                rule: .daily,
                calendar: utcCalendar
            ) == date(2026, 1, 11)
        )
        #expect(
            RecurrenceCalendar.nextOccurrence(
                after: anchor,
                referenceDate: completedLate,
                rule: .weekly,
                calendar: utcCalendar
            ) == date(2026, 1, 15)
        )
    }

    @Test func monthlyRecurrenceClampsToLastValidDay() {
        let january31 = date(2027, 1, 31)
        let completion = date(2027, 1, 31, hour: 12)

        #expect(
            RecurrenceCalendar.nextOccurrence(
                after: january31,
                referenceDate: completion,
                rule: .monthly,
                calendar: utcCalendar
            ) == date(2027, 2, 28)
        )
    }

    @Test func weekdayRecurrenceSkipsWeekendsAndOverdueDays() {
        let friday = date(2026, 7, 24)

        #expect(
            RecurrenceCalendar.nextOccurrence(
                after: friday,
                referenceDate: date(2026, 7, 24, hour: 12),
                rule: .weekdays,
                calendar: utcCalendar
            ) == date(2026, 7, 27)
        )
        #expect(
            RecurrenceCalendar.nextOccurrence(
                after: friday,
                referenceDate: date(2026, 7, 28, hour: 12),
                rule: .weekdays,
                calendar: utcCalendar
            ) == date(2026, 7, 29)
        )
    }

    @Test func backlogCompletionCreatesOneIdempotentNextInstance() throws {
        let container = AppContainer.makeTestContainer()
        let context = container.mainContext
        let task = AgendaTask(title: "Medication")
        task.dueDate = date(2026, 7, 24)
        task.recurrenceRule = RecurrenceRule.daily.rawValue
        task.notes = "With breakfast"
        let step = TaskStep(title: "Fill water", sortOrder: 0)
        step.parentTask = task
        task.steps = [step]
        context.insert(task)
        context.insert(step)
        try context.save()

        let first = try TaskLifecycleService.complete(
            task,
            in: context,
            at: date(2026, 7, 24, hour: 12),
            calendar: utcCalendar
        )
        let repeated = try TaskLifecycleService.complete(
            task,
            in: context,
            at: date(2026, 7, 27, hour: 12),
            calendar: utcCalendar
        )

        #expect(first?.clientID == repeated?.clientID)
        #expect(first?.dueDate == date(2026, 7, 25))
        #expect(first?.recurrenceParentID == task.clientID)
        #expect(first?.notes == "With breakfast")
        #expect(first?.steps?.map(\.title) == ["Fill water"])
        #expect(first?.steps?.first?.isComplete == false)
        #expect(try context.fetch(FetchDescriptor<AgendaTask>()).count == 2)
    }

    @Test func generatedInstanceContinuesSameSeries() throws {
        let container = AppContainer.makeTestContainer()
        let context = container.mainContext
        let root = AgendaTask(title: "Weekly review")
        root.scheduledDate = date(2026, 7, 24)
        root.recurrenceRule = RecurrenceRule.weekly.rawValue
        context.insert(root)
        try context.save()

        let generatedSecond = try TaskLifecycleService.complete(
            root,
            in: context,
            at: date(2026, 7, 24, hour: 12),
            calendar: utcCalendar
        )
        let second = try #require(generatedSecond)
        let generatedThird = try TaskLifecycleService.complete(
            second,
            in: context,
            at: date(2026, 7, 31, hour: 12),
            calendar: utcCalendar
        )
        let third = try #require(generatedThird)

        #expect(second.scheduledDate == date(2026, 7, 31))
        #expect(third.scheduledDate == date(2026, 8, 7))
        #expect(second.recurrenceParentID == root.clientID)
        #expect(third.recurrenceParentID == root.clientID)
        #expect(try context.fetch(FetchDescriptor<AgendaTask>()).count == 3)
    }

    @Test func monthlySeriesKeepsOriginalPreferredDayAfterClamping() throws {
        let container = AppContainer.makeTestContainer()
        let context = container.mainContext
        let root = AgendaTask(title: "Month end")
        root.scheduledDate = date(2027, 1, 31)
        root.recurrenceRule = RecurrenceRule.monthly.rawValue
        context.insert(root)
        try context.save()

        let generatedFebruary = try TaskLifecycleService.complete(
            root,
            in: context,
            at: date(2027, 1, 31, hour: 12),
            calendar: utcCalendar
        )
        let february = try #require(generatedFebruary)
        let generatedMarch = try TaskLifecycleService.complete(
            february,
            in: context,
            at: date(2027, 2, 28, hour: 12),
            calendar: utcCalendar
        )
        let march = try #require(generatedMarch)

        #expect(february.scheduledDate == date(2027, 2, 28))
        #expect(march.scheduledDate == date(2027, 3, 31))
    }

    @Test func repeatingBacklogTaskWithoutDateFailsAtomically() throws {
        let container = AppContainer.makeTestContainer()
        let context = container.mainContext
        let task = AgendaTask(title: "Unanchored")
        task.recurrenceRule = RecurrenceRule.daily.rawValue
        context.insert(task)
        try context.save()

        #expect(throws: TaskLifecycleError.self) {
            try TaskLifecycleService.complete(task, in: context)
        }
        #expect(task.isComplete == false)
        #expect(task.completedAt == nil)
        #expect(try context.fetch(FetchDescriptor<AgendaTask>()).count == 1)
    }

    @Test func unsupportedBacklogRecurrenceFailsClosed() throws {
        let container = AppContainer.makeTestContainer()
        let context = container.mainContext
        let task = AgendaTask(title: "Legacy series")
        task.dueDate = date(2026, 7, 24)
        task.recurrenceRule = "every-fortnight"
        context.insert(task)
        try context.save()

        #expect(throws: TaskLifecycleError.self) {
            try TaskLifecycleService.complete(
                task,
                in: context,
                at: date(2026, 7, 24, hour: 12),
                calendar: utcCalendar
            )
        }
        #expect(!task.isComplete)
        #expect(task.completedAt == nil)
        #expect(try context.fetch(FetchDescriptor<AgendaTask>()).count == 1)
    }

    @Test func agendaItemCompletionIsIdempotentAndCopiesSubtasks() throws {
        let container = AppContainer.makeTestContainer()
        let context = container.mainContext
        let item = AgendaItem(
            title: "Plan tomorrow",
            scheduledDate: date(2026, 7, 24),
            recurrenceRule: RecurrenceRule.daily.rawValue
        )
        let subtask = SubTask(title: "Check calendar", sortOrder: 0)
        subtask.parentItem = item
        item.subTasks = [subtask]
        context.insert(item)
        context.insert(subtask)
        try context.save()

        let next = try AgendaItemLifecycleService.complete(
            item,
            in: context,
            at: date(2026, 7, 24, hour: 12),
            calendar: utcCalendar
        )
        let repeated = try AgendaItemLifecycleService.complete(
            item,
            in: context,
            at: date(2026, 7, 27, hour: 12),
            calendar: utcCalendar
        )

        #expect(next?.clientID == repeated?.clientID)
        #expect(next?.scheduledDate == date(2026, 7, 25))
        #expect(next?.subTasks?.map(\.title) == ["Check calendar"])
        #expect(try context.fetch(FetchDescriptor<AgendaItem>()).count == 2)
    }

    @Test func unsupportedAgendaItemRecurrenceRollsBackCompletion() throws {
        let container = AppContainer.makeTestContainer()
        let context = container.mainContext
        let item = AgendaItem(
            title: "Legacy calendar series",
            scheduledDate: date(2026, 7, 24)
        )
        item.recurrenceRule = "weekdays-only"
        context.insert(item)
        try context.save()

        #expect(throws: TaskLifecycleError.self) {
            try AgendaItemLifecycleService.complete(
                item,
                in: context,
                at: date(2026, 7, 24, hour: 12),
                calendar: utcCalendar
            )
        }
        #expect(!item.isComplete)
        #expect(item.completedAt == nil)
        #expect(try context.fetch(FetchDescriptor<AgendaItem>()).count == 1)
    }

    @Test func abandonAndReopenTransitionsStayConsistent() throws {
        let container = AppContainer.makeTestContainer()
        let context = container.mainContext
        let task = AgendaTask(title: "Maybe later")
        context.insert(task)
        try context.save()

        try TaskLifecycleService.abandon(
            task,
            reason: "No longer needed",
            in: context,
            at: date(2026, 7, 24)
        )
        #expect(task.isAbandoned)
        #expect(!task.isComplete)
        #expect(task.abandonReason == "No longer needed")
        #expect(task.abandonedAt == date(2026, 7, 24))

        try TaskLifecycleService.reopen(
            task,
            in: context,
            at: date(2026, 7, 25)
        )
        #expect(!task.isAbandoned)
        #expect(!task.isComplete)
        #expect(task.abandonReason.isEmpty)
        #expect(task.abandonedAt == nil)
    }
}
