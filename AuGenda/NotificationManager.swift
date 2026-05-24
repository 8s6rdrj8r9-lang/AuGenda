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
// SETUP REQUIRED:
// 1. Add UNUserNotificationCenter delegate in your App entry point
// 2. Request authorization early (see requestAuthorization())
// 3. Add "Background Modes → Background fetch" capability for silent pushes

import Combine
import Foundation
import UserNotifications
import SwiftData

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
    @Published var focusSessionEndsAt: Date? = nil

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
        registerCategories()
        Task { await refreshAuthorizationStatus() }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound, .badge, .criticalAlert]
            )
            await refreshAuthorizationStatus()
            print("Notification authorization granted: \(granted)")
        } catch {
            print("Notification authorization error: \(error)")
        }
    }

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
    private var activePrefs: ProfilePreferences? {
        ActiveProfileManager.shared.activePreferences
    }

    // MARK: - Schedule AgendaItem notifications

    /// Schedules up to 3 notifications per item, respecting the active profile's NotificationStyle:
    /// - `.standard`    → advance warning + at-time + overdue nudge
    /// - `.predictable` → advance warning + at-time only (no overdue surprise)
    /// - `.minimal`     → at-time only
    func scheduleNotifications(for item: AgendaItem, advanceMinutes: Int = 10) {
        let idBase = item.clientID.uuidString
        let notifStyle = activePrefs?.notificationStyle ?? .standard

        // Cancel any existing notifications for this item first
        cancelNotifications(for: item)

        let scheduledDate = item.scheduledDate
        let now = Date.now

        // 1. Advance warning — skip for minimal style
        if notifStyle != .minimal {
            let advanceDate = scheduledDate.addingTimeInterval(Double(-advanceMinutes) * 60)
            if advanceDate > now {
                scheduleAlert(
                    id: "\(idBase)-advance",
                    title: "Coming up in \(advanceMinutes) min",
                    body: item.title,
                    date: advanceDate,
                    category: NotificationCategory.agendaItem,
                    userInfo: [
                        "clientID": item.clientID.uuidString,
                        "type": "advance"
                    ]
                )
            }
        }

        // 2. At-time alert — always scheduled
        if scheduledDate > now {
            scheduleAlert(
                id: "\(idBase)-attime",
                title: "Now: \(item.title)",
                body: item.notes.isEmpty ? "Tap to open" : item.notes,
                date: scheduledDate,
                category: NotificationCategory.agendaItem,
                userInfo: [
                    "clientID": item.clientID.uuidString,
                    "type": "attime"
                ]
            )
        }

        // 3. Overdue nudge — standard style only (predictable/minimal skip surprises)
        if notifStyle == .standard {
            let overdueDate = scheduledDate.addingTimeInterval(15 * 60)
            if overdueDate > now {
                scheduleAlert(
                    id: "\(idBase)-overdue",
                    title: "Still pending: \(item.title)",
                    body: "Started 15 minutes ago — still need to do this?",
                    date: overdueDate,
                    category: NotificationCategory.agendaItem,
                    userInfo: [
                        "clientID": item.clientID.uuidString,
                        "type": "overdue"
                    ]
                )
            }
        }
    }

    func cancelNotifications(for item: AgendaItem) {
        let idBase = item.clientID.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [
            "\(idBase)-advance",
            "\(idBase)-attime",
            "\(idBase)-overdue",
            "\(idBase)-snooze"
        ])
    }

    // MARK: - Snooze

    func snooze(item: AgendaItem, minutes: Int) {
        cancelNotifications(for: item)
        let snoozeDate = Date.now.addingTimeInterval(Double(minutes) * 60)

        scheduleAlert(
            id: "\(item.clientID.uuidString)-snooze",
            title: "Snoozed: \(item.title)",
            body: "You asked to be reminded now.",
            date: snoozeDate,
            category: NotificationCategory.agendaItem,
            userInfo: [
                "clientID": item.clientID.uuidString,
                "type": "snooze"
            ]
        )
    }

    // MARK: - Focus Session

    func startFocusSession(durationMinutes: Int, taskTitle: String = "") {
        let endsAt = Date.now.addingTimeInterval(Double(durationMinutes) * 60)
        focusSessionActive = true
        focusSessionEndsAt = endsAt

        // Notify Watch
        #if canImport(WatchConnectivity)
        WatchConnectivityManager.shared.sendFocusStarted(endsAt: endsAt)
        #endif

        // End-of-session notification
        let body = taskTitle.isEmpty
            ? "Your focus session is complete. Take a break."
            : "Focus session for '\(taskTitle)' complete. Take a break."

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
            scheduleAlert(
                id: "hyperfocus-guard-warning",
                title: "⚠️ Time check",
                body: taskTitle.isEmpty
                    ? "You've been in this session for \(Int(Double(durationMinutes) * 0.75)) minutes. Intentional?"
                    : "'\(taskTitle)' — \(Int(Double(durationMinutes) * 0.75)) min in. Still intentional?",
                date: seventyFivePercent,
                category: NotificationCategory.hyperfocusWarning,
                userInfo: ["type": "hyperfocusGuard"]
            )
            // Hard-stop at session end — separate from the regular focus-done banner
            scheduleAlert(
                id: "hyperfocus-guard-stop",
                title: "🛑 Session over — time to stop",
                body: taskTitle.isEmpty
                    ? "Your \(durationMinutes)-minute session has ended. Step away."
                    : "'\(taskTitle)' session done. You decided \(durationMinutes) min was the limit.",
                date: endsAt,
                category: NotificationCategory.hyperfocusWarning,
                userInfo: ["type": "hyperfocusGuardStop"]
            )
        }
    }

    func endFocusSession() {
        focusSessionActive = false
        focusSessionEndsAt = nil
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

    // MARK: - Hyperfocus risk timer

    /// Call when user starts a task flagged as hyperfocusRisk
    func scheduleHyperfocusWarning(taskTitle: String, afterMinutes: Int = 45) {
        let warningDate = Date.now.addingTimeInterval(Double(afterMinutes) * 60)
        scheduleAlert(
            id: "hyperfocus-warning",
            title: "⚠️ Time check",
            body: "You've been on '\(taskTitle)' for \(afterMinutes) minutes. Intentional?",
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
        scheduleAlert(
            id: "low-ef-nudge",
            title: "Low effort task available",
            body: "'\(taskTitle)' is low friction — ready when you are.",
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
            if let error { print("Notification schedule error [\(id)]: \(error)") }
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

        Task { @MainActor in
            await handleAction(actionID: actionID, userInfo: userInfo)
        }

        completionHandler()
    }

    @MainActor
    private func handleAction(actionID: String, userInfo: [AnyHashable: Any]) async {
        switch actionID {
        case NotificationAction.complete:
            // Post to app to mark item complete — handled by scene/view observing this
            NotificationCenter.default.post(
                name: .agendaItemCompleted,
                object: nil,
                userInfo: userInfo as? [String: Any]
            )

        case NotificationAction.snooze5:
            NotificationCenter.default.post(
                name: .agendaItemSnoozed,
                object: nil,
                userInfo: ["clientID": userInfo["clientID"] ?? "", "minutes": 5]
            )

        case NotificationAction.snooze15:
            NotificationCenter.default.post(
                name: .agendaItemSnoozed,
                object: nil,
                userInfo: ["clientID": userInfo["clientID"] ?? "", "minutes": 15]
            )

        case NotificationAction.snooze30:
            NotificationCenter.default.post(
                name: .agendaItemSnoozed,
                object: nil,
                userInfo: ["clientID": userInfo["clientID"] ?? "", "minutes": 30]
            )

        case NotificationAction.endFocus:
            endFocusSession()

        default:
            break
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let agendaItemCompleted = Notification.Name("agendaItemCompleted")
    static let agendaItemSnoozed = Notification.Name("agendaItemSnoozed")
}
