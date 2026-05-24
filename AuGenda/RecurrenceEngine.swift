// RecurrenceEngine.swift
// AUDHD Agenda App
//
// Generates today's AgendaItem instances from recurring templates.
// A "template" is a recurring AgendaItem with recurrenceParentID == nil.
// A "generated instance" is a copy of the template with recurrenceParentID set.
// Idempotent — safe to call multiple times per day.

import Foundation
import SwiftData

enum RecurrenceEngine {

    // MARK: - Public API

    /// Call on every app launch. Creates today's instances for any recurring templates
    /// that don't already have one. Fully idempotent.
    @MainActor
    static func generateForToday(context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }

        // Fetch all recurring templates (items that are themselves templates, not generated copies)
        let templateDescriptor = FetchDescriptor<AgendaItem>(
            predicate: #Predicate {
                $0.recurrenceRule != "none" && $0.recurrenceParentID == nil
            }
        )
        let templates = (try? context.fetch(templateDescriptor)) ?? []

        for template in templates {
            guard shouldFire(template: template, today: today, using: calendar) else { continue }

            // Already have an instance for today?
            let parentID = template.clientID
            let existingDescriptor = FetchDescriptor<AgendaItem>(
                predicate: #Predicate {
                    $0.recurrenceParentID == parentID &&
                    $0.scheduledDate >= today &&
                    $0.scheduledDate < tomorrow
                }
            )
            guard ((try? context.fetch(existingDescriptor)) ?? []).isEmpty else { continue }

            // Schedule instance at the same time-of-day as the template
            let timeComps = calendar.dateComponents([.hour, .minute], from: template.scheduledDate)
            let instanceDate = calendar.date(
                bySettingHour: timeComps.hour ?? 9,
                minute: timeComps.minute ?? 0,
                second: 0,
                of: today
            ) ?? today

            let instance = AgendaItem(
                title: template.title,
                scheduledDate: instanceDate,
                priority: template.priority,
                frictionLevel: template.frictionLevel,
                energyRequired: template.energyRequired,
                contextTag: template.contextTag,
                recurrenceRule: template.recurrenceRule
            )
            instance.recurrenceParentID = template.clientID
            instance.notes = template.notes
            context.insert(instance)
        }

        try? context.save()
    }

    // MARK: - Private

    private static func shouldFire(
        template: AgendaItem,
        today: Date,
        using calendar: Calendar
    ) -> Bool {
        switch template.recurrenceRule {
        case "daily":
            return true
        case "weekly":
            // Same weekday as when the template was originally scheduled
            let templateWeekday = calendar.component(.weekday, from: template.scheduledDate)
            let todayWeekday = calendar.component(.weekday, from: today)
            return templateWeekday == todayWeekday
        case "weekdays":
            // Monday (2) through Friday (6)
            let weekday = calendar.component(.weekday, from: today)
            return weekday >= 2 && weekday <= 6
        default:
            return false
        }
    }
}
