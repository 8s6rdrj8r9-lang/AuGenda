// WatchSessionClient.swift
// AuGenda Watch
//
// Mirrors the iOS `WatchConnectivityManager` (under AuGenda/) on the
// watch side. Same message-key + message-type protocol (kept identical
// here so the two halves can't drift). Per Spec §12, the AI relay
// (Watch → iPhone → Mac/Ollama) is wired but stubbed — no model call
// happens on the watch in v1.
//
// Offline-first principle: this client is *garnish*. The NowView reads
// SwiftData directly; the session just keeps live state (focus timer,
// immediate NEXT changes) flowing when both devices are awake.

import Combine
import Foundation
import SwiftData
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// MARK: - Shared protocol constants
//
// SHARED contract: these mirror the iOS-side declarations in
// AuGenda/WatchConnectivityManager.swift. Keep them in sync.

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
    // AI relay (Spec §12, stubbed for v2)
    static let aiSuggestContext = "aiSuggestContext"
    static let aiSuggestResult = "aiSuggestResult"
}

enum WCMessageType: String {
    case syncSnapshot
    case taskCompleted
    case taskSnoozed
    case energyUpdate
    case requestSync
    case focusStarted
    case focusEnded
    // TODO(watch v2): Ollama relay payload shape isn't finalised in spec §12.
    // Stubbed message types — once the iOS-side relay is built, swap to the
    // real payload struct.
    case aiSuggestRequest
    case aiSuggestResponse
}

struct WatchSyncPayload: Codable {
    var nextAgendaItemTitle: String
    var nextAgendaItemTime: Date?
    var nextAgendaItemClientID: String
    var currentEnergyLevel: Int
    var focusSessionActive: Bool
    var focusSessionEndsAt: Date?
    var pendingTaskCount: Int
    var lowFrictionTaskCount: Int
    var pendingRecovery: Bool
}

// MARK: - WatchSessionClient

#if canImport(WatchConnectivity)

/// Singleton wrapper around `WCSession` for the watchOS app.
/// Posts back completion / snooze / energy updates to the iPhone; receives
/// focus-state pushes and fresh sync snapshots.
@MainActor
final class WatchSessionClient: NSObject, ObservableObject {

    static let shared = WatchSessionClient()

    @Published var isPhoneReachable: Bool = false
    @Published var lastSyncDate: Date? = nil
    @Published var focusSessionActive: Bool = false
    @Published var focusSessionEndsAt: Date? = nil
    @Published var pendingRecovery: Bool = false

    /// Set from `AuGendaWatchApp` on launch so the client can persist
    /// incoming sync snapshots straight to the watch's local SwiftData.
    var modelContext: ModelContext?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Watch → iPhone

    /// Tell the iPhone the user marked an item complete on the watch.
    func sendTaskCompleted(clientID: UUID) {
        guard WCSession.default.activationState == .activated else { return }
        let message: [String: Any] = [
            WCMessageKey.messageType: WCMessageType.taskCompleted.rawValue,
            WCMessageKey.agendaItemClientID: clientID.uuidString,
            WCMessageKey.timestamp: Date.now.timeIntervalSince1970
        ]
        send(message)
    }

    /// Tell the iPhone the user snoozed an item from the watch.
    func sendTaskSnoozed(clientID: UUID, minutes: Int) {
        guard WCSession.default.activationState == .activated else { return }
        let message: [String: Any] = [
            WCMessageKey.messageType: WCMessageType.taskSnoozed.rawValue,
            WCMessageKey.agendaItemClientID: clientID.uuidString,
            WCMessageKey.snoozeMinutes: minutes,
            WCMessageKey.timestamp: Date.now.timeIntervalSince1970
        ]
        send(message)
    }

    /// Tell the iPhone the user changed their energy level on the watch.
    func sendEnergyUpdate(level: Int) {
        guard WCSession.default.activationState == .activated else { return }
        let message: [String: Any] = [
            WCMessageKey.messageType: WCMessageType.energyUpdate.rawValue,
            WCMessageKey.energyLevel: level,
            WCMessageKey.timestamp: Date.now.timeIntervalSince1970
        ]
        send(message)
    }

    /// Ask the iPhone for a fresh sync snapshot — usually called on launch
    /// or when the watch app comes to the foreground.
    func requestSync() {
        guard WCSession.default.activationState == .activated else { return }
        let message: [String: Any] = [
            WCMessageKey.messageType: WCMessageType.requestSync.rawValue,
            WCMessageKey.timestamp: Date.now.timeIntervalSince1970
        ]
        send(message)
    }

    /// TODO(watch v2): the AI relay. Wired but unused — the iPhone side
    /// hasn't built the Ollama relay yet, so this send is a no-op queue.
    func sendAISuggestRequest(contextSnapshot: [String: Any] = [:]) {
        guard WCSession.default.activationState == .activated else { return }
        var message: [String: Any] = [
            WCMessageKey.messageType: WCMessageType.aiSuggestRequest.rawValue,
            WCMessageKey.timestamp: Date.now.timeIntervalSince1970
        ]
        message[WCMessageKey.aiSuggestContext] = contextSnapshot
        send(message)
    }

    // MARK: - Internals

    private func send(_ message: [String: Any]) {
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { _ in
                // Errors are non-fatal here — the watch state still works
                // offline. Future v2: route through os.Logger.
            }
        } else {
            // Phone asleep — queue for delivery on next wake.
            try? WCSession.default.updateApplicationContext(message)
        }
    }

    /// Apply an incoming `syncSnapshot` payload. For v1 we only refresh the
    /// in-memory reachable + focus state; full SwiftData merge from the
    /// iPhone snapshot is deferred (the watch reads its own CloudKit-synced
    /// store anyway).
    private func handleSyncSnapshot(_ message: [String: Any]) {
        if let active = message["focusSessionActive"] as? Bool {
            focusSessionActive = active
        }
        if let endsAtTS = message["focusEndsAt"] as? TimeInterval {
            focusSessionEndsAt = Date(timeIntervalSince1970: endsAtTS)
        }
        if let pending = message["pendingRecovery"] as? Bool {
            pendingRecovery = pending
        }
        lastSyncDate = .now
    }

    private func handleFocusStarted(_ message: [String: Any]) {
        focusSessionActive = true
        if let endsAtTS = message["focusEndsAt"] as? TimeInterval {
            focusSessionEndsAt = Date(timeIntervalSince1970: endsAtTS)
        }
    }

    private func handleFocusEnded() {
        focusSessionActive = false
        focusSessionEndsAt = nil
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionClient: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
            // Pull fresh state from the iPhone on activation.
            if activationState == .activated {
                self.requestSync()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPhoneReachable = session.isReachable
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        Task { @MainActor in
            self.routeIncoming(message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            self.routeIncoming(applicationContext)
        }
    }

    @MainActor
    private func routeIncoming(_ message: [String: Any]) {
        guard let typeRaw = message[WCMessageKey.messageType] as? String,
              let type = WCMessageType(rawValue: typeRaw) else { return }
        switch type {
        case .syncSnapshot:        handleSyncSnapshot(message)
        case .focusStarted:        handleFocusStarted(message)
        case .focusEnded:          handleFocusEnded()
        case .aiSuggestResponse:   break   // TODO(watch v2): apply suggestion
        default:                   break   // Watch-originated message types
        }
    }
}

#else

// Fallback shim for build configurations where WatchConnectivity is
// unavailable (e.g. CI matrices not targeting watchOS).
@MainActor
final class WatchSessionClient: ObservableObject {
    static let shared = WatchSessionClient()
    @Published var isPhoneReachable: Bool = false
    @Published var lastSyncDate: Date? = nil
    @Published var focusSessionActive: Bool = false
    @Published var focusSessionEndsAt: Date? = nil
    @Published var pendingRecovery: Bool = false
    var modelContext: ModelContext?
    private init() {}
    func sendTaskCompleted(clientID: UUID) {}
    func sendTaskSnoozed(clientID: UUID, minutes: Int) {}
    func sendEnergyUpdate(level: Int) {}
    func requestSync() {}
    func sendAISuggestRequest(contextSnapshot: [String: Any] = [:]) {}
}

#endif
