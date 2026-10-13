// NotificationManager.swift
// AUDHD Agenda App
//
// Notification scheduling tuned for AUDHD needs:
// - Advance warnings (not just at-time alerts — time blindness mitigation)
// - Snooze with escalating urgency
// - Focus session start/end notifications
// - Hyperfocus risk timer alerts
// - Low-friction task nudges during low-EF periods
// - Quiet hours respect
//
// The app uses local notifications only. Authorization is requested
// contextually, the manager is the notification-center delegate, and no
// background-fetch or remote-notification capability is required.

import Combine
import Foundation
import os.log
import UserNotifications
import SwiftData

private let logger = Logger(subsystem: "com.augenda.AuGenda", category: "NotificationManager")

// MARK: - Notification Category & Action IDs

enum NotificationCategory {
    static let agendaItem = "AGENDA_ITEM"
    static let focusSession = "FOCUS_SESSION"
    static let hyperfocusWarning = "HYPERFOCUS_WARNING"
    static let lowEFNudge = "LOW_EF_NUDGE"
}

enum NotificationAction {
    static let complete = "COMPLETE"
    static let snooze5 = "SNOOZE_5"
    static let snooze15 = "SNOOZE_15"
    static let snooze30 = "SNOOZE_30"
    static let startFocus = "START_FOCUS"
    static let endFocus = "END_FOCUS"
    static let dismiss = "DISMISS"
}

// MARK: - Snooze Options

enum SnoozeInterval: Int, CaseIterable {
    case five = 5
    case fifteen = 15
    case thirty = 30

    var label: String {
        switch self {
        case .five: return "5 min"
        case .fifteen: return "15 min"
        case .thirty: return "30 min"
        }
    }
}

// MARK: - NotificationManager

@MainActor
final class NotificationManager: NSObject, ObservableObject {

    nonisolated let objectWillChange = ObservableObjectPublisher()

    static let shared = NotificationManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var focusSessionActive: Bool = false
    @Published private(set) var focusSessionPaused: Bool = false
    @Published var focusSessionEndsAt: Date? = nil

    var modelContext: ModelContext? = nil {
        didSet {
            reconcileFocusSessionState()
        }
    }

    private let center = UNUserNotificationCenter.current()
    private var activeFocusSessionID: UUID?
    private var focusExpiryTask: Task<Void, Never>?

    private override init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            // Standard alert/sound/badge only. `.criticalAlert` requires a
            // separate Apple entitlement and bypasses Do Not Disturb — overreach
            // for a routine productivity app and a guaranteed App Review block.
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            await refreshAuthorizationStatus()
            logger.info("Notification authorization granted: \(granted, privacy: .public)")
        } catch {
            logger.error("Notification authorization error: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    // MARK: - Register actionable notification categories

    private func registerCategories() {
        // Agenda item actions
        let completeAction = UNNotificationAction(
            identifier: NotificationAction.complete,
            title: "✓ Done",
            options: [.authenticationRequired]
        )
        let snooze5Action = UNNotificationAction(
            identifier: NotificationAction.snooze5,
            title: "⏱ 5 min",
            options: []
        )
        let snooze15Action = UNNotificationAction(
            identifier: NotificationAction.snooze15,
            title: "⏱ 15 min",
            options: []
        )
        let snooze30Action = UNNotificationAction(
            identifier: NotificationAction.snooze30,
            title: "⏱ 30 min",
            options: []
        )

        let agendaCategory = UNNotificationCategory(
            identifier: NotificationCategory.agendaItem,
            actions: [completeAction, snooze5Action, snooze15Action, snooze30Action],
            intentIdentifiers: [],
            options: []
        )

        // Focus session actions
        let endFocusAction = UNNotificationAction(
            identifier: NotificationAction.endFocus,
            title: "End Session",
            options: []
        )
        let focusCategory = UNNotificationCategory(
            identifier: NotificationCategory.focusSession,
            actions: [endFocusAction],
            intentIdentifiers: [],
            options: []
        )

        // Hyperfocus warning
        let dismissAction = UNNotificationAction(
            identifier: NotificationAction.dismiss,
            title: "I'm aware",
            options: []
        )
        let hyperfocusCategory = UNNotificationCategory(
            identifier: NotificationCategory.hyperfocusWarning,
            actions: [dismissAction, endFocusAction],
            intentIdentifiers: [],
            options: []
        )

        // Low-EF nudge
        let startFocusAction = UNNotificationAction(
            identifier: NotificationAction.startFocus,
            title: "Start focus session",
            options: []
        )
        let nudgeCategory = UNNotificationCategory(
            identifier: NotificationCategory.lowEFNudge,
            actions: [startFocusAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([
            agendaCategory,
            focusCategory,
            hyperfocusCategory,
            nudgeCategory
        ])
    }

    // MARK: - Profile preferences convenience

    /// Active profile's notification preferences (nil-safe; falls back to standard behaviour).
    /// Whether to redact task content (titles, notes) from notification
    /// previews. Defaults to true so privacy is the safe default.
    private var strictPrivacy: Bool {
        activePrefs?.notificationPrivacyStrict ?? true
    }

    private var activePrefs: ProfilePreferences? {
        ActiveProfileManager.shared.activePreferences
    }

    private var canScheduleNotifications: Bool {
        switch authorizationStatus {
        case .authorized, .provisional:
            return true
        #if os(iOS)
        case .ephemeral:
            return true
        #endif
        default:
            return false
        }
    }

    // MARK: - Schedule AgendaItem notifications

    /// A deterministic agenda reminder plan, shared by scheduling and tests.
    struct AgendaReminder {
        let type: String
        let title: String
        let body: String
        let date: Date
    }

    /// Agenda content follows its owner's preferences, never whichever household
    /// profile happens to be active. Unassigned or unavailable owners stay private.
    private func agendaPreferences(for item: AgendaItem) -> ProfilePreferences? {
        guard let ownerID = item.assignedToProfileID, let context = modelContext else {
            return nil
        }
        let descriptor = FetchDescriptor<Profile>(
            predicate: #Predicate { $0.clientID == ownerID }
        )
        return (try? context.fetch(descriptor))?.first?.preferences
    }

    func agendaReminderPlan(
        for item: AgendaItem,
        at now: Date = .now,
        advanceMinutes: Int = 10,
        snoozeOverride: Date? = nil
    ) -> [AgendaReminder] {
        guard !item.isComplete else { return [] }
        let preferences = agendaPreferences(for: item)
        let redact = preferences?.notificationPrivacyStrict ?? true
        let style = preferences?.notificationStyle ?? .minimal

        // A snooze replaces the original schedule, including during privacy
        // refresh and backup restore. Expired snoozes must not resurrect it.
        if let snoozeDate = snoozeOverride ?? item.snoozedUntil {
            guard snoozeDate > now else { return [] }
            return [AgendaReminder(
                type: "snooze",
                title: redact ? "Snooze reminder" : "Snoozed: \(item.title)",
                body: "You asked to be reminded now.",
                date: snoozeDate
            )]
        }

        var reminders: [AgendaReminder] = []
        let advanceDate = item.scheduledDate.addingTimeInterval(Double(-advanceMinutes) * 60)
        if style != .minimal, advanceDate > now {
            reminders.append(AgendaReminder(
                type: "advance",
                title: "Coming up in \(advanceMinutes) min",
                body: redact ? "Tap to open" : item.title,
                date: advanceDate
            ))
        }
        if item.scheduledDate > now {
            reminders.append(AgendaReminder(
                type: "attime",
                title: redact ? "Time for your task" : "Now: \(item.title)",
                body: redact ? "Tap to open" : (item.notes.isEmpty ? "Tap to open" : item.notes),
                date: item.scheduledDate
            ))
        }
        let overdueDate = item.scheduledDate.addingTimeInterval(15 * 60)
        if style == .standard, overdueDate > now {
            reminders.append(AgendaReminder(
                type: "overdue",
                title: redact ? "Still pending" : "Still pending: \(item.title)",
                body: "Started 15 minutes ago — still need to do this?",
                date: overdueDate
            ))
        }
        return reminders
    }

    /// Schedules the owner's reminder style, or the outstanding snooze deadline.
    func scheduleNotifications(for item: AgendaItem, advanceMinutes: Int = 10) {
        if authorizationStatus == .notDetermined {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.requestAuthorization()
                guard self.canScheduleNotifications else { return }
                self.scheduleNotifications(for: item, advanceMinutes: advanceMinutes)
            }
            return
        }
        guard canScheduleNotifications else { return }
        cancelNotifications(for: item)
        scheduleAgendaReminders(
            agendaReminderPlan(for: item, advanceMinutes: advanceMinutes),
            for: item
        )
    }

    private func scheduleAgendaReminders(_ reminders: [AgendaReminder], for item: AgendaItem) {
        for reminder in reminders {
            scheduleAlert(
                id: "\(item.clientID.uuidString)-\(reminder.type)",
                title: reminder.title,
                body: reminder.body,
                date: reminder.date,
                category: NotificationCategory.agendaItem,
                userInfo: ["clientID": item.clientID.uuidString, "type": reminder.type]
            )
        }
    }

    func cancelNotifications(for item: AgendaItem) {
        let idBase = item.clientID.uuidString
        let identifiers = [
            "\(idBase)-advance",
            "\(idBase)-attime",
            "\(idBase)-overdue",
            "\(idBase)-snooze"
        ]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Rebuild all agenda-item requests from the durable model. The category
    /// sweep is intentionally broader than per-record cancellation: deleted,
    /// completed, or otherwise obsolete records no longer exist to provide an
    /// identifier, but their pending and delivered notification content must
    /// still be removed when privacy or scheduling policy changes.
    func reconcilePendingAgendaNotifications() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<AgendaItem>(
            predicate: #Predicate { !$0.isComplete }
        )
        do {
            let items = try context.fetch(descriptor)
            Task { @MainActor [weak self] in
                guard let self else { return }

                let pending = await center.pendingNotificationRequests()
                let pendingIDs = pending
                    .filter {
                        $0.content.categoryIdentifier == NotificationCategory.agendaItem
                    }
                    .map(\.identifier)
                center.removePendingNotificationRequests(withIdentifiers: pendingIDs)

                let delivered = await center.deliveredNotifications()
                let deliveredIDs = delivered
                    .filter {
                        $0.request.content.categoryIdentifier == NotificationCategory.agendaItem
                    }
                    .map { $0.request.identifier }
                center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)

                for item in items {
                    scheduleNotifications(for: item)
                }
            }
        } catch {
            logger.error("Failed to reconcile agenda notifications: \(error.localizedDescription, privacy: .public)")
            ErrorBannerController.shared.show("Couldn't refresh notifications: \(error.localizedDescription)")
        }
    }

    /// Clear every notification surface owned by AuGenda. This is part of the
    /// erase contract, because delivered notifications may still contain data
    /// after the underlying models have been deleted.
    func removeAllNotifications() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        focusExpiryTask?.cancel()
        focusExpiryTask = nil
        activeFocusSessionID = nil
        focusSessionActive = false
        focusSessionEndsAt = nil
    }

    // MARK: - Snooze

    func snooze(item: AgendaItem, minutes: Int) {
        scheduleSnooze(
            item: item,
            at: Date.now.addingTimeInterval(Double(minutes) * 60)
        )
    }

    /// Schedule an agenda snooze at a stable deadline. Watch mutations use
    /// their immutable event timestamp so redelivery is idempotent.
    func scheduleSnooze(item: AgendaItem, at snoozeDate: Date) {
        cancelNotifications(for: item)
        scheduleAgendaReminders(
            agendaReminderPlan(for: item, snoozeOverride: snoozeDate),
            for: item
        )
    }

    // MARK: - Focus Session

    @discardableResult
    func startFocusSession(durationMinutes: Int, taskTitle: String = "", taskID: UUID? = nil) -> Bool {
        guard durationMinutes > 0, let context = modelContext else {
            ErrorBannerController.shared.show("Focus session couldn't start because storage is unavailable.")
            return false
        }

        reconcileFocusSessionState()
        guard !focusSessionActive else {
            ErrorBannerController.shared.show("A focus session is already active.")
            return false
        }

        let endsAt = Date.now.addingTimeInterval(Double(durationMinutes) * 60)
        let session = FocusSession(
            plannedDurationMinutes: durationMinutes,
            taskID: taskID,
            taskTitle: taskTitle,
            profileID: ActiveProfileManager.shared.activeProfile?.clientID
        )
        context.insert(session)
        do {
            try context.save()
        } catch {
            context.rollback()
            logger.error("Failed to save focus session: \(error.localizedDescription, privacy: .public)")
            ErrorBannerController.shared.show("Couldn't start focus session: \(error.localizedDescription)")
            return false
        }

        activeFocusSessionID = session.clientID
        focusSessionActive = true
        focusSessionPaused = false
        focusSessionEndsAt = endsAt
        scheduleFocusExpiry(at: endsAt)

        // Notify Watch
        #if canImport(WatchConnectivity)
        WatchConnectivityManager.shared.sendFocusStarted(endsAt: endsAt)
        #endif

        // End-of-session notification
        let body: String
        if strictPrivacy || taskTitle.isEmpty {
            body = "Your focus session is complete. Take a break."
        } else {
            body = "Focus session for '\(taskTitle)' complete. Take a break."
        }

        scheduleAlert(
            id: "focus-session-end",
            title: "Focus session done ✓",
            body: body,
            date: endsAt,
            category: NotificationCategory.focusSession,
            userInfo: ["type": "focusEnd"]
        )

        // Halfway check-in (skip for minimal notification style)
        if activePrefs?.notificationStyle != .minimal {
            let halfwayDate = Date.now.addingTimeInterval(Double(durationMinutes) * 30)
            scheduleAlert(
                id: "focus-session-halfway",
                title: "Halfway there",
                body: "Still on task? \(durationMinutes / 2) minutes left.",
                date: halfwayDate,
                category: NotificationCategory.focusSession,
                userInfo: ["type": "focusHalfway"]
            )
        }

        // Hyperfocus guard — fires a prominent warning at 75% and again at 100% of session time.
        // Deliberately uses the hyperfocusWarning category (louder, harder to ignore) so ADHD
        // profiles get a real interrupt rather than the gentle focus-done banner.
        if activePrefs?.hyperfocusGuard == true {
            let seventyFivePercent = Date.now.addingTimeInterval(Double(durationMinutes) * 60 * 0.75)
            let hyperfocusBody: String
            if strictPrivacy || taskTitle.isEmpty {
                hyperfocusBody = "You've been in this session for \(Int(Double(durationMinutes) * 0.75)) minutes. Intentional?"
            } else {
                hyperfocusBody = "'\(taskTitle)' — \(Int(Double(durationMinutes) * 0.75)) min in. Still intentional?"
            }
            scheduleAlert(
                id: "hyperfocus-guard-warning",
                title: "⚠️ Time check",
                body: hyperfocusBody,
                date: seventyFivePercent,
                category: NotificationCategory.hyperfocusWarning,
                userInfo: ["type": "hyperfocusGuard"]
            )
            // Hard-stop at session end — separate from the regular focus-done banner
            let stopBody: String
            if strictPrivacy || taskTitle.isEmpty {
                stopBody = "Your \(durationMinutes)-minute session has ended. Step away."
            } else {
                stopBody = "'\(taskTitle)' session done. You decided \(durationMinutes) min was the limit."
            }
            scheduleAlert(
                id: "hyperfocus-guard-stop",
                title: "🛑 Session over — time to stop",
                body: stopBody,
                date: endsAt,
                category: NotificationCategory.hyperfocusWarning,
                userInfo: ["type": "hyperfocusGuardStop"]
            )
        }
        return true
    }

    @discardableResult
    func endFocusSession() -> Bool {
        guard let context = modelContext,
              let active = fetchOngoingFocusSession(in: context)
        else {
            clearPublishedFocusState()
            return false
        }

        let completedAt = active.state == .paused ? (active.endTime ?? .now) : .now
        active.state = .completed
        active.endTime = completedAt
        active.wasCompleted = true
        active.wasAbandoned = false
        active.abandonReason = ""
        do {
            try context.save()
        } catch {
            context.rollback()
            logger.error("Failed to complete focus session: \(error.localizedDescription, privacy: .public)")
            ErrorBannerController.shared.show("Couldn't end focus session: \(error.localizedDescription)")
            return false
        }

        clearPublishedFocusState()
        finishFocusSideEffects()
        return true
    }

    /// Pause the current session without counting paused wall-clock time as
    /// focus. `endTime` temporarily stores the pause instant; resume shifts
    /// `startTime` by the pause duration and clears `endTime`.
    @discardableResult
    func pauseFocusSession(reason: String = "Paused by user") -> Bool {
        guard
            let context = modelContext,
            let session = fetchOngoingFocusSession(in: context),
            session.state == .active
        else {
            return false
        }

        let pausedAt = Date.now
        session.state = .paused
        session.endTime = pausedAt
        session.recordInterruption(reason: reason)
        do {
            try context.save()
        } catch {
            context.rollback()
            logger.error("Failed to pause focus session: \(error.localizedDescription, privacy: .public)")
            ErrorBannerController.shared.show("Couldn't pause focus session: \(error.localizedDescription)")
            return false
        }

        focusExpiryTask?.cancel()
        focusExpiryTask = nil
        activeFocusSessionID = session.clientID
        focusSessionActive = true
        focusSessionPaused = true
        focusSessionEndsAt = nil
        finishFocusSideEffects()
        return true
    }

    @discardableResult
    func resumeFocusSession() -> Bool {
        guard
            let context = modelContext,
            let session = fetchOngoingFocusSession(in: context),
            session.state == .paused,
            let pausedAt = session.endTime
        else {
            return false
        }

        let resumedAt = Date.now
        let pauseDuration = max(0, resumedAt.timeIntervalSince(pausedAt))
        session.startTime = session.startTime.addingTimeInterval(pauseDuration)
        session.endTime = nil
        session.state = .active
        do {
            try context.save()
        } catch {
            context.rollback()
            logger.error("Failed to resume focus session: \(error.localizedDescription, privacy: .public)")
            ErrorBannerController.shared.show("Couldn't resume focus session: \(error.localizedDescription)")
            return false
        }

        let endsAt = session.plannedEndTime
        activeFocusSessionID = session.clientID
        focusSessionActive = true
        focusSessionPaused = false
        focusSessionEndsAt = endsAt
        scheduleFocusExpiry(at: endsAt)
        scheduleResumedFocusNotifications(for: session, endsAt: endsAt)
        #if canImport(WatchConnectivity)
        WatchConnectivityManager.shared.sendFocusStarted(endsAt: endsAt)
        #endif
        return true
    }

    @discardableResult
    func abandonFocusSession(reason: String) -> Bool {
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedReason.isEmpty,
            let context = modelContext,
            let session = fetchOngoingFocusSession(in: context)
        else {
            return false
        }

        let abandonedAt = session.state == .paused ? (session.endTime ?? .now) : .now
        session.state = .abandoned
        session.endTime = abandonedAt
        session.wasCompleted = false
        session.wasAbandoned = true
        session.abandonReason = normalizedReason
        do {
            try context.save()
        } catch {
            context.rollback()
            logger.error("Failed to abandon focus session: \(error.localizedDescription, privacy: .public)")
            ErrorBannerController.shared.show("Couldn't stop focus session: \(error.localizedDescription)")
            return false
        }

        clearPublishedFocusState()
        finishFocusSideEffects()
        return true
    }

    /// Restore the one authoritative active session after launch/foreground
    /// and close expired or duplicate sessions deterministically.
    func reconcileFocusSessionState(now: Date = .now) {
        guard let context = modelContext else {
            clearPublishedFocusState()
            return
        }

        let activeRaw = FocusSessionState.active.rawValue
        let pausedRaw = FocusSessionState.paused.rawValue
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate {
                $0.stateRaw == activeRaw || $0.stateRaw == pausedRaw
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 100

        let sessions: [FocusSession]
        do {
            sessions = try context.fetch(descriptor)
        } catch {
            logger.error("Failed to restore focus state: \(error.localizedDescription, privacy: .public)")
            clearPublishedFocusState()
            return
        }

        guard let primary = sessions.first else {
            clearPublishedFocusState()
            return
        }

        // Any additional active records are invalid. Preserve their history as
        // abandoned rather than allowing an unordered record to be completed.
        for duplicate in sessions.dropFirst() {
            duplicate.state = .abandoned
            duplicate.wasAbandoned = true
            duplicate.abandonReason = "Superseded during launch reconciliation"
            duplicate.endTime = now
        }

        let primaryIsPaused = primary.state == .paused
        let plannedEnd = primary.plannedEndTime
        if !primaryIsPaused && plannedEnd <= now {
            primary.state = .completed
            primary.endTime = plannedEnd
            primary.wasCompleted = true
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            logger.error("Failed to reconcile focus records: \(error.localizedDescription, privacy: .public)")
            clearPublishedFocusState()
            return
        }

        if primaryIsPaused {
            focusExpiryTask?.cancel()
            focusExpiryTask = nil
            activeFocusSessionID = primary.clientID
            focusSessionActive = true
            focusSessionPaused = true
            focusSessionEndsAt = nil
            finishFocusSideEffects()
        } else if plannedEnd <= now {
            clearPublishedFocusState()
            finishFocusSideEffects()
        } else {
            activeFocusSessionID = primary.clientID
            focusSessionActive = true
            focusSessionPaused = false
            focusSessionEndsAt = plannedEnd
            scheduleFocusExpiry(at: plannedEnd)
        }
    }

    private func fetchOngoingFocusSession(in context: ModelContext) -> FocusSession? {
        let activeRaw = FocusSessionState.active.rawValue
        let pausedRaw = FocusSessionState.paused.rawValue
        if let id = activeFocusSessionID {
            let descriptor = FetchDescriptor<FocusSession>(
                predicate: #Predicate {
                    $0.clientID == id
                        && ($0.stateRaw == activeRaw || $0.stateRaw == pausedRaw)
                }
            )
            if let exact = try? context.fetch(descriptor).first {
                return exact
            }
        }

        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate {
                $0.stateRaw == activeRaw || $0.stateRaw == pausedRaw
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        return try? context.fetch(descriptor).first
    }

    private func scheduleFocusExpiry(at deadline: Date) {
        focusExpiryTask?.cancel()
        let seconds = max(0, deadline.timeIntervalSinceNow)
        let nanoseconds = UInt64(min(seconds, 86_400 * 365) * 1_000_000_000)
        focusExpiryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.reconcileFocusSessionState()
        }
    }

    private func clearPublishedFocusState() {
        focusExpiryTask?.cancel()
        focusExpiryTask = nil
        activeFocusSessionID = nil
        focusSessionActive = false
        focusSessionPaused = false
        focusSessionEndsAt = nil
    }

    private func finishFocusSideEffects() {
        center.removePendingNotificationRequests(withIdentifiers: [
            "focus-session-end",
            "focus-session-halfway",
            "hyperfocus-guard-warning",
            "hyperfocus-guard-stop"
        ])
        #if canImport(WatchConnectivity)
        WatchConnectivityManager.shared.sendFocusEnded()
        #endif
    }

    private func scheduleResumedFocusNotifications(
        for session: FocusSession,
        endsAt: Date
    ) {
        let body: String
        if strictPrivacy || session.taskTitle.isEmpty {
            body = "Your focus session is complete. Take a break."
        } else {
            body = "Focus session for '\(session.taskTitle)' complete. Take a break."
        }
        scheduleAlert(
            id: "focus-session-end",
            title: "Focus session done ✓",
            body: body,
            date: endsAt,
            category: NotificationCategory.focusSession,
            userInfo: ["type": "focusEnd"]
        )

        if activePrefs?.hyperfocusGuard == true {
            scheduleAlert(
                id: "hyperfocus-guard-stop",
                title: "🛑 Session over — time to stop",
                body: strictPrivacy || session.taskTitle.isEmpty
                    ? "Your focus session has ended. Step away."
                    : "'\(session.taskTitle)' session done. Step away.",
                date: endsAt,
                category: NotificationCategory.hyperfocusWarning,
                userInfo: ["type": "hyperfocusGuardStop"]
            )
        }
    }

    func recordInterruption(reason: String = "") {
        guard let ctx = modelContext else { return }
        let activeRaw = FocusSessionState.active.rawValue
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.stateRaw == activeRaw }
        )
        if let active = (try? ctx.fetch(descriptor))?.first {
            active.recordInterruption(reason: reason)
            do {
                try ctx.save()
            } catch {
                ctx.rollback()
                logger.error("Failed to record interruption: \(error.localizedDescription, privacy: .public)")
                ErrorBannerController.shared.show("Couldn't save interruption: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Durable notification actions

    @discardableResult
    private func completeAgendaItem(clientID: String) -> Bool {
        guard let context = modelContext,
              let id = UUID(uuidString: clientID)
        else { return false }
        let descriptor = FetchDescriptor<AgendaItem>(
            predicate: #Predicate { $0.clientID == id }
        )
        guard let item = try? context.fetch(descriptor).first else { return false }

        do {
            let next = try AgendaItemLifecycleService.complete(
                item,
                in: context
            )
            if let next {
                scheduleNotifications(for: next)
            }
        } catch {
            logger.error("Notification completion failed to save: \(error.localizedDescription, privacy: .public)")
            return false
        }
        cancelNotifications(for: item)
        ActivityLog.recordCompletion()
        #if canImport(WatchConnectivity)
        WatchConnectivityManager.shared.sendSyncSnapshot()
        #endif
        return true
    }

    @discardableResult
    private func snoozeAgendaItem(clientID: String, minutes: Int) -> Bool {
        guard let context = modelContext,
              let id = UUID(uuidString: clientID)
        else { return false }
        let descriptor = FetchDescriptor<AgendaItem>(
            predicate: #Predicate { $0.clientID == id }
        )
        guard let item = try? context.fetch(descriptor).first else { return false }

        item.snoozedUntil = Date.now.addingTimeInterval(Double(minutes) * 60)
        item.updatedAt = .now
        do {
            try context.save()
        } catch {
            context.rollback()
            logger.error("Notification snooze failed to save: \(error.localizedDescription, privacy: .public)")
            return false
        }
        snooze(item: item, minutes: minutes)
        ActivityLog.recordSnooze()
        #if canImport(WatchConnectivity)
        WatchConnectivityManager.shared.sendSyncSnapshot()
        #endif
        return true
    }

    // MARK: - Hyperfocus risk timer

    /// Call when user starts a task flagged as hyperfocusRisk
    func scheduleHyperfocusWarning(taskTitle: String, afterMinutes: Int = 45) {
        let warningDate = Date.now.addingTimeInterval(Double(afterMinutes) * 60)
        let body = strictPrivacy
            ? "You've been on this task for \(afterMinutes) minutes. Intentional?"
            : "You've been on '\(taskTitle)' for \(afterMinutes) minutes. Intentional?"
        scheduleAlert(
            id: "hyperfocus-warning",
            title: "⚠️ Time check",
            body: body,
            date: warningDate,
            category: NotificationCategory.hyperfocusWarning,
            userInfo: ["type": "hyperfocus"]
        )
    }

    func cancelHyperfocusWarning() {
        center.removePendingNotificationRequests(withIdentifiers: ["hyperfocus-warning"])
    }

    // MARK: - Low-EF nudge

    /// Surface this when user reports low energy — suggests lowest friction task
    func scheduleLowEFNudge(taskTitle: String, delayMinutes: Int = 30) {
        let nudgeDate = Date.now.addingTimeInterval(Double(delayMinutes) * 60)
        let body = strictPrivacy
            ? "There's a low-friction task ready when you are."
            : "'\(taskTitle)' is low friction — ready when you are."
        scheduleAlert(
            id: "low-ef-nudge",
            title: "Low effort task available",
            body: body,
            date: nudgeDate,
            category: NotificationCategory.lowEFNudge,
            userInfo: ["type": "lowEFNudge"]
        )
    }

    // MARK: - Core scheduling primitive

    private func scheduleAlert(
        id: String,
        title: String,
        body: String,
        date: Date,
        category: String,
        userInfo: [String: String] = [:]
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = userInfo

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                // Hash the id so log readers can't reconstruct task UUIDs.
                logger.error("Notification schedule error [\(id, privacy: .private(mask: .hash))]: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

    // Show notifications even when app is foregrounded
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // Handle action taps (complete, snooze, etc.)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionID = response.actionIdentifier
        let clientID = userInfo["clientID"] as? String ?? ""

        Task { @MainActor [weak self] in
            self?.handleAction(actionID: actionID, clientID: clientID)
            completionHandler()
        }
    }

    @MainActor
    private func handleAction(actionID: String, clientID: String) {
        switch actionID {
        case NotificationAction.complete:
            _ = completeAgendaItem(clientID: clientID)

        case NotificationAction.snooze5:
            _ = snoozeAgendaItem(clientID: clientID, minutes: 5)

        case NotificationAction.snooze15:
            _ = snoozeAgendaItem(clientID: clientID, minutes: 15)

        case NotificationAction.snooze30:
            _ = snoozeAgendaItem(clientID: clientID, minutes: 30)

        case NotificationAction.startFocus:
            _ = startFocusSession(
                durationMinutes: activePrefs?.focusSessionMinutes ?? 25
            )

        case NotificationAction.endFocus:
            _ = endFocusSession()

        default:
            break
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted by the macOS "Go" menu commands (⌘1–⌘5) to switch tabs.
    /// userInfo["index"] is the 0-based tab index. Observed by ContentView.
    static let selectTab = Notification.Name("selectTab")
    /// Routes the interruption banner to its recorded task/item.
    /// userInfo["itemID"] is an optional UUID string.
    static let resumeActivity = Notification.Name("resumeActivity")
}
