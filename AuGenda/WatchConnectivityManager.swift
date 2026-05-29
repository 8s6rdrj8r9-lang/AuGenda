// WatchConnectivityManager.swift
// AUDHD Agenda App
//
// Handles bidirectional communication between iPhone and Apple Watch.
// Watch cannot access CloudKit directly — iPhone is the source of truth.
// Watch gets a lightweight subset: next task, current energy level, focus timer state.
//
// SETUP REQUIRED:
// 1. Add WatchConnectivity framework to both iPhone and Watch targets
// 2. Initialize WatchConnectivityManager early in app lifecycle (see AUDHDAgendaApp.swift)
// 3. Create a matching WatchConnectivityManager in the Watch Extension target

import Combine
import Foundation
import os.log
import SwiftData
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

private let logger = Logger(subsystem: "com.augenda.AuGenda", category: "WatchConnectivity")

#if canImport(WatchConnectivity)

// MARK: - Message Keys
// Shared constants — copy this enum to your Watch Extension target too

enum WCMessageKey {
    static let messageType = "messageType"
    static let nextTask = "nextTask"
    static let energyLevel = "energyLevel"
    static let focusState = "focusState"
    static let taskCompleted = "taskCompleted"
    static let taskSnoozed = "taskSnoozed"
    static let snoozeMinutes = "snoozeMinutes"
    static let taskClientID = "taskClientID"
    static let agendaItemClientID = "agendaItemClientID"
    static let timestamp = "timestamp"
}

enum WCMessageType: String {
    case syncSnapshot = "syncSnapshot"         // iPhone → Watch: full lightweight sync
    case taskCompleted = "taskCompleted"       // Watch → iPhone: mark complete
    case taskSnoozed = "taskSnoozed"           // Watch → iPhone: snooze item
    case energyUpdate = "energyUpdate"         // Watch → iPhone: user changed energy level
    case requestSync = "requestSync"           // Watch → iPhone: please send fresh data
    case focusStarted = "focusStarted"         // iPhone → Watch: focus session began
    case focusEnded = "focusEnded"             // iPhone → Watch: focus session ended
}


// MARK: - Watch Sync Payload
// Lightweight struct — only what the Watch needs

struct WatchSyncPayload: Codable {
    var nextAgendaItemTitle: String
    var nextAgendaItemTime: Date?
    var nextAgendaItemClientID: String
    var currentEnergyLevel: Int
    var focusSessionActive: Bool
    var focusSessionEndsAt: Date?
    var pendingTaskCount: Int
    var lowFrictionTaskCount: Int   // tasks at friction ≤ 2, actionable now
}


// MARK: - WatchConnectivityManager

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {

    nonisolated let objectWillChange = ObservableObjectPublisher()

    static let shared = WatchConnectivityManager()

    // MARK: - Published state (drives iPhone UI awareness of Watch)
    @Published var isWatchReachable: Bool = false
    @Published var lastSyncDate: Date? = nil
    @Published var lastWatchAction: WCMessageType? = nil

    // Injected after init — set this from your App entry point
    var modelContext: ModelContext?

    // MARK: - Init
    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Send sync snapshot to Watch

    func sendSyncSnapshot() {
        guard WCSession.default.activationState == .activated else { return }
        guard WCSession.default.isWatchAppInstalled else { return }

        let payload = buildPayload()

        guard let encoded = try? JSONEncoder().encode(payload),
              let dict = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        else { return }

        var message = dict
        message[WCMessageKey.messageType] = WCMessageType.syncSnapshot.rawValue
        message[WCMessageKey.timestamp] = Date.now.timeIntervalSince1970

        if WCSession.default.isReachable {
            // Watch is awake — send immediately
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                logger.error("WC sendMessage error: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            // Watch not reachable — queue via application context (delivered on next wake)
            try? WCSession.default.updateApplicationContext(message)
        }

        lastSyncDate = .now
    }

    // MARK: - Send focus session state

    func sendFocusStarted(endsAt: Date) {
        let message: [String: Any] = [
            WCMessageKey.messageType: WCMessageType.focusStarted.rawValue,
            "focusEndsAt": endsAt.timeIntervalSince1970
        ]
        send(message)
    }

    func sendFocusEnded() {
        let message: [String: Any] = [
            WCMessageKey.messageType: WCMessageType.focusEnded.rawValue
        ]
        send(message)
    }

    // MARK: - Private helpers

    private func send(_ message: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: { error in
                logger.error("WC send error: \(error.localizedDescription, privacy: .public)")
            })
        } else {
            try? WCSession.default.updateApplicationContext(message)
        }
    }

    private func buildPayload() -> WatchSyncPayload {
        guard let context = modelContext else {
            return WatchSyncPayload(
                nextAgendaItemTitle: "No data",
                nextAgendaItemTime: nil,
                nextAgendaItemClientID: "",
                currentEnergyLevel: 3,
                focusSessionActive: false,
                focusSessionEndsAt: nil,
                pendingTaskCount: 0,
                lowFrictionTaskCount: 0
            )
        }

        // Fetch next upcoming incomplete agenda item
        let now = Date.now
        let agendaDescriptor = FetchDescriptor<AgendaItem>(
            predicate: #Predicate {
                !$0.isComplete && $0.scheduledDate >= now
            },
            sortBy: [SortDescriptor(\.scheduledDate)]
        )
        let upcoming = (try? context.fetch(agendaDescriptor)) ?? []
        let next = upcoming.first

        // Count actionable tasks — scoped to active profile where possible
        let activeProfileID = ActiveProfileManager.shared.activeProfile?.clientID
        let taskDescriptor = FetchDescriptor<Task>(
            predicate: #Predicate {
                !$0.isComplete && !$0.isAbandoned
            }
        )
        let allTasks = (try? context.fetch(taskDescriptor)) ?? []
        // Filter to tasks assigned to the active profile (or unassigned legacy tasks)
        let profileTasks = allTasks.filter { task in
            if let assignedID = task.assignedToProfileID {
                return assignedID == activeProfileID
            }
            return true
        }
        let lowFriction = profileTasks.filter { $0.frictionLevel <= 2 && $0.isActionable }

        // Read energy from active profile's preferences (not legacy UserPreferences)
        let activePrefs = ActiveProfileManager.shared.activePreferences
        let energyLevel = activePrefs?.currentEnergyLevel ?? 3
        let focusManager = NotificationManager.shared

        return WatchSyncPayload(
            nextAgendaItemTitle: next?.title ?? "Nothing scheduled",
            nextAgendaItemTime: next?.scheduledDate,
            nextAgendaItemClientID: next?.clientID.uuidString ?? "",
            currentEnergyLevel: energyLevel,
            focusSessionActive: focusManager.focusSessionActive,
            focusSessionEndsAt: focusManager.focusSessionEndsAt,
            pendingTaskCount: profileTasks.count,
            lowFrictionTaskCount: lowFriction.count
        )
    }

    // MARK: - Handle incoming Watch messages

    private func handleIncoming(_ message: [String: AnyObject]) {
        guard let typeRaw = message[WCMessageKey.messageType] as? String,
              let type = WCMessageType(rawValue: typeRaw)
        else { return }

        lastWatchAction = type

        switch type {
        case .taskCompleted:
            handleTaskCompleted(message)
        case .taskSnoozed:
            handleTaskSnoozed(message)
        case .energyUpdate:
            handleEnergyUpdate(message)
        case .requestSync:
            sendSyncSnapshot()
        default:
            break
        }
    }

    private func handleTaskCompleted(_ message: [String: AnyObject]) {
        guard let context = modelContext,
              let idString = message[WCMessageKey.agendaItemClientID] as? String,
              let uuid = UUID(uuidString: idString)
        else { return }

        let descriptor = FetchDescriptor<AgendaItem>(
            predicate: #Predicate { $0.clientID == uuid }
        )
        guard let item = (try? context.fetch(descriptor))?.first else { return }
        item.isComplete = true
        item.completedAt = .now
        item.updatedAt = .now
        try? context.save()
        sendSyncSnapshot()
    }

    private func handleTaskSnoozed(_ message: [String: AnyObject]) {
        guard let context = modelContext,
              let idString = message[WCMessageKey.agendaItemClientID] as? String,
              let uuid = UUID(uuidString: idString),
              let minutes = message[WCMessageKey.snoozeMinutes] as? Int
        else { return }

        let descriptor = FetchDescriptor<AgendaItem>(
            predicate: #Predicate { $0.clientID == uuid }
        )
        guard let item = (try? context.fetch(descriptor))?.first else { return }
        item.snoozedUntil = Calendar.current.date(byAdding: .minute, value: minutes, to: .now)
        item.updatedAt = .now
        try? context.save()
        sendSyncSnapshot()
    }

    private func handleEnergyUpdate(_ message: [String: AnyObject]) {
        guard let level = message[WCMessageKey.energyLevel] as? Int else { return }

        // Write energy update to the active profile's preferences (not legacy UserPreferences)
        guard let prefs = ActiveProfileManager.shared.activePreferences else { return }
        prefs.currentEnergyLevel = level
        prefs.updatedAt = .now
        try? modelContext?.save()
        sendSyncSnapshot()
    }
}


// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            isWatchReachable = session.isReachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isWatchReachable = session.isReachable
            if session.isReachable {
                sendSyncSnapshot()
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        Task { @MainActor in
            handleIncoming(message as [String: AnyObject])
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            handleIncoming(applicationContext as [String: AnyObject])
        }
    }

    // Required for iOS — not called on watchOS
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}

#endif // canImport(WatchConnectivity)
