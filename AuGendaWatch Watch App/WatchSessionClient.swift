// WatchSessionClient.swift
// AuGenda Watch
//
// The Watch consumes a full-replacement phone snapshot and persists a durable
// mutation outbox. Discrete actions use transferUserInfo, never replaceable
// application context, and remain queued until the phone acknowledges them.

import Combine
import Foundation
import os.log
import WidgetKit
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

private let logger = Logger(
    subsystem: "com.augenda.AuGenda.watchkitapp",
    category: "WatchConnectivity"
)

#if canImport(WatchConnectivity)

@MainActor
final class WatchSessionClient: NSObject, ObservableObject {
    static let shared = WatchSessionClient()

    @Published var isPhoneReachable = false
    @Published private(set) var snapshot: WatchSnapshot?
    @Published private(set) var pendingMutationCount = 0
    @Published private(set) var lastDeliveryError: String?
    @Published private(set) var rejectedCaptures: [RejectedWatchCapture] = []

    private let store: WatchSharedStateStore
    private var outboxRetryTask: Task<Void, Never>?

    var lastSyncDate: Date? { snapshot?.generatedAt }
    var focusSessionActive: Bool { freshSnapshot?.focusSessionActive ?? false }
    var focusSessionEndsAt: Date? { freshSnapshot?.focusSessionEndsAt }
    var pendingRecovery: Bool { freshSnapshot?.pendingRecovery ?? false }

    var freshSnapshot: WatchSnapshot? {
        presentationSnapshot(at: .now)
    }

    var hasFreshSnapshot: Bool {
        freshSnapshot != nil
    }

    private override convenience init() {
        self.init(store: WatchSharedStateStore())
    }

    init(store: WatchSharedStateStore) {
        self.store = store
        self.snapshot = store.loadSnapshot()
        self.pendingMutationCount = store.pendingMutations().count
        self.rejectedCaptures = store.rejectedCaptures()
        super.init()

        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: Watch -> Phone

    @discardableResult
    func sendTaskCompleted(clientID: UUID) -> Bool {
        return enqueueMutation(kind: .completeAgendaItem, agendaItemID: clientID)
    }

    @discardableResult
    func sendTaskSnoozed(clientID: UUID, minutes: Int) -> Bool {
        return enqueueMutation(
            kind: .snoozeAgendaItem,
            agendaItemID: clientID,
            snoozeMinutes: minutes
        )
    }

    @discardableResult
    func sendEnergyUpdate(level: Int) -> Bool {
        guard (1...4).contains(level) else {
            lastDeliveryError = "Choose an energy level from 1 to 4."
            return false
        }
        return enqueueMutation(kind: .updateEnergy, energyLevel: level)
    }

    @discardableResult
    func sendCapture(title: String) -> Bool {
        return enqueueMutation(kind: .captureTask, captureTitle: title)
    }

    func requestSync() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        // A sync request is replaceable, unlike a mutation. Application
        // context retains only the newest request for background delivery.
        do {
            try session.updateApplicationContext(WatchSyncContract.requestSyncMessage)
        } catch {
            logger.error("Background sync request failed: \(error.localizedDescription, privacy: .public)")
        }
        if session.isReachable {
            session.sendMessage(
                WatchSyncContract.requestSyncMessage,
                replyHandler: nil
            ) { error in
                logger.error("Immediate sync request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func enqueueMutation(
        kind: WatchMutationKind,
        agendaItemID: UUID? = nil,
        snoozeMinutes: Int? = nil,
        energyLevel: Int? = nil,
        captureTitle: String? = nil
    ) -> Bool {
        guard let profileID = snapshot?.profileID, hasFreshSnapshot else {
            lastDeliveryError = "Open AuGenda on iPhone to sync before making changes."
            return false
        }

        let mutation = WatchMutation(
            profileID: profileID,
            kind: kind,
            agendaItemID: agendaItemID,
            snoozeMinutes: snoozeMinutes,
            energyLevel: energyLevel,
            captureTitle: captureTitle
        )
        guard store.enqueue(mutation) else {
            lastDeliveryError = "Could not queue this change."
            return false
        }

        pendingMutationCount = store.pendingMutations().count
        lastDeliveryError = nil
        reloadComplication()
        flushOutbox()
        return true
    }

    private func flushOutbox() {
        let session = WCSession.default
        guard session.activationState == .activated else {
            scheduleOutboxRetry()
            return
        }

        for pending in store.mutationsDue() {
            do {
                let message = try WatchSyncContract.message(
                    type: .mutation,
                    payload: pending.mutation
                )
                if pending.attemptCount == 0 {
                    // Submit one durable, ordered background transfer. Do not
                    // enqueue another OS transfer every 30 seconds while its
                    // acknowledgement is pending.
                    session.transferUserInfo(message)
                } else if session.isReachable {
                    // A foreground retry is cheap and idempotent. The phone's
                    // processed-event ledger handles a delayed duplicate.
                    session.sendMessage(
                        message,
                        replyHandler: nil
                    ) { error in
                        logger.error(
                            "Immediate Watch mutation retry failed: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                } else {
                    continue
                }
                store.markAttempted(eventID: pending.mutation.eventID)
            } catch {
                lastDeliveryError = "Could not encode a queued change."
                logger.error("Watch mutation encoding failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        pendingMutationCount = store.pendingMutations().count
        scheduleOutboxRetry()
    }

    /// `transferUserInfo` supplies the OS-managed background transport, while
    /// this bounded foreground retry closes the gap where an attempted
    /// transfer fails without a reachability or activation callback. The
    /// durable outbox remains the source of truth until an acknowledgement.
    private func scheduleOutboxRetry() {
        outboxRetryTask?.cancel()
        guard !store.pendingMutations().isEmpty else {
            outboxRetryTask = nil
            return
        }
        // Once the initial transfer is accepted, WatchConnectivity owns its
        // background delivery. Wake the foreground retry loop only for a new
        // unsent item or while the phone is reachable.
        guard WCSession.default.isReachable
                || store.pendingMutations().contains(where: {
                    $0.attemptCount == 0
                }) else {
            outboxRetryTask = nil
            return
        }

        outboxRetryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.flushOutbox()
        }
    }

    // MARK: Presentation

    func presentationSnapshot(at date: Date) -> WatchSnapshot? {
        store.presentationSnapshot(from: snapshot, at: date)
    }

    // MARK: Phone -> Watch

    private func routeIncoming(_ message: [String: Any]) {
        guard let rawType = message[WatchSyncContract.messageTypeKey] as? String,
              let type = WatchSyncContract.MessageType(rawValue: rawType) else {
            return
        }

        switch type {
        case .syncSnapshot:
            do {
                let incoming = try WatchSyncContract.decode(
                    WatchSnapshot.self,
                    from: message,
                    expectedMessageType: .syncSnapshot
                )
                apply(incoming)
            } catch {
                logger.error("Rejected malformed phone snapshot: \(error.localizedDescription, privacy: .public)")
            }
        case .acknowledgement:
            do {
                let acknowledgement = try WatchSyncContract.decode(
                    WatchAcknowledgement.self,
                    from: message,
                    expectedMessageType: .acknowledgement
                )
                apply(acknowledgement)
            } catch {
                logger.error("Rejected malformed phone acknowledgement: \(error.localizedDescription, privacy: .public)")
            }
        case .mutation, .requestSync:
            break
        }
    }

    private func apply(_ incoming: WatchSnapshot) {
        guard store.save(snapshot: incoming) else { return }
        snapshot = incoming
        lastDeliveryError = nil
        reloadComplication()
    }

    private func apply(_ acknowledgement: WatchAcknowledgement) {
        guard acknowledgement.schemaVersion == WatchSyncContract.schemaVersion else { return }

        switch acknowledgement.status {
        case .applied, .duplicate:
            store.acknowledge(eventID: acknowledgement.eventID)
            lastDeliveryError = nil
        case .rejected:
            if let pending = store.pendingMutations().first(where: { $0.mutation.eventID == acknowledgement.eventID }),
               pending.mutation.kind == .captureTask,
               let title = pending.mutation.captureTitle {
                let reason: String
                if let rawReason = acknowledgement.reason, !rawReason.isEmpty {
                    if rawReason.lowercased().hasPrefix("rejected") {
                        reason = rawReason
                    } else if rawReason.lowercased().contains("profile") {
                        reason = "Rejected: profile changed"
                    } else {
                        reason = "Rejected: \(rawReason.lowercased())"
                    }
                } else {
                    reason = "Rejected: profile changed"
                }
                let capture = RejectedWatchCapture(
                    eventID: acknowledgement.eventID,
                    profileID: pending.mutation.profileID,
                    title: title,
                    reason: reason,
                    rejectedAt: .now
                )
                store.saveRejectedCapture(capture)
                rejectedCaptures = store.rejectedCaptures()
            }
            store.acknowledge(eventID: acknowledgement.eventID)
            lastDeliveryError = acknowledgement.reason ?? "The phone rejected a queued change."
            requestSync()
        case .retryable:
            lastDeliveryError = acknowledgement.reason ?? "A queued change will retry."
        }
        pendingMutationCount = store.pendingMutations().count
        reloadComplication()
        scheduleOutboxRetry()
    }

    @discardableResult
    func retryRejectedCapture(_ capture: RejectedWatchCapture) -> Bool {
        guard let profileID = snapshot?.profileID ?? Optional(capture.profileID) else {
            lastDeliveryError = "Open AuGenda on iPhone to sync before making changes."
            return false
        }

        let mutation = WatchMutation(
            eventID: UUID(),
            profileID: profileID,
            kind: .captureTask,
            captureTitle: capture.title
        )
        guard store.enqueue(mutation) else {
            lastDeliveryError = "Could not queue this change."
            return false
        }

        store.removeRejectedCapture(eventID: capture.eventID)
        rejectedCaptures = store.rejectedCaptures()
        pendingMutationCount = store.pendingMutations().count
        lastDeliveryError = nil
        reloadComplication()
        flushOutbox()
        return true
    }

    func dismissRejectedCapture(eventID: UUID) {
        store.removeRejectedCapture(eventID: eventID)
        rejectedCaptures = store.rejectedCaptures()
    }

    private func reloadComplication() {
        WidgetCenter.shared.reloadTimelines(ofKind: WatchSyncContract.widgetKind)
    }
}

// MARK: WCSessionDelegate

extension WatchSessionClient: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            isPhoneReachable = session.isReachable
            if activationState == .activated {
                flushOutbox()
                requestSync()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isPhoneReachable = session.isReachable
            if session.isReachable {
                flushOutbox()
                requestSync()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in routeIncoming(message) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in routeIncoming(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in routeIncoming(userInfo) }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor in
            if let mutation = try? WatchSyncContract.decode(
                WatchMutation.self,
                from: userInfoTransfer.userInfo,
                expectedMessageType: .mutation
            ) {
                store.markTransferFailed(eventID: mutation.eventID)
            }
            lastDeliveryError = "A queued change will retry."
            logger.error("Background Watch transfer failed: \(error.localizedDescription, privacy: .public)")
            scheduleOutboxRetry()
        }
    }
}

#else

@MainActor
final class WatchSessionClient: ObservableObject {
    static let shared = WatchSessionClient()
    @Published var isPhoneReachable = false
    @Published private(set) var snapshot: WatchSnapshot?
    @Published private(set) var pendingMutationCount = 0
    @Published private(set) var lastDeliveryError: String?

    var lastSyncDate: Date? { snapshot?.generatedAt }
    var focusSessionActive: Bool { false }
    var focusSessionEndsAt: Date? { nil }
    var pendingRecovery: Bool { false }
    var freshSnapshot: WatchSnapshot? { nil }
    var hasFreshSnapshot: Bool { false }

    private init() {}
    func sendTaskCompleted(clientID: UUID) -> Bool { false }
    func sendTaskSnoozed(clientID: UUID, minutes: Int) -> Bool { false }
    func sendEnergyUpdate(level: Int) -> Bool { false }
    func sendCapture(title: String) -> Bool { false }
    func requestSync() {}
    func presentationSnapshot(at date: Date) -> WatchSnapshot? { nil }
}

#endif
