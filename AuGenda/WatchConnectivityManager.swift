// WatchConnectivityManager.swift
// AuGenda
//
// The phone is the source of truth. It sends a versioned, full-replacement
// snapshot scoped to the active profile and idempotently applies durable
// mutations queued by the Watch.

import Combine
import Foundation
import os.log
import SwiftData
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

private let logger = Logger(subsystem: "com.augenda.AuGenda", category: "WatchConnectivity")

#if canImport(WatchConnectivity)

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()

    static let shared = WatchConnectivityManager()

    @Published var isWatchReachable = false
    @Published var lastSyncDate: Date?
    @Published var lastWatchAction: WatchMutationKind?

    var modelContext: ModelContext?

    private let processedMutationDefaultsKey = "watch.sync.processedMutationIDs.v1"
    private let maximumProcessedMutationCount = 1_024

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: Phone -> Watch state

    func sendSyncSnapshot() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isWatchAppInstalled else { return }

        guard let snapshot = buildSnapshot() else { return }
        let message: [String: Any]
        do {
            message = try WatchSyncContract.message(type: .syncSnapshot, payload: snapshot)
        } catch {
            logger.error("Failed to encode Watch snapshot: \(error.localizedDescription, privacy: .public)")
            return
        }

        // Application context is intentionally replaceable: only the newest
        // complete snapshot matters. This also guarantees eventual delivery.
        do {
            try session.updateApplicationContext(message)
            lastSyncDate = snapshot.generatedAt
        } catch {
            logger.error("Failed to update Watch application context: \(error.localizedDescription, privacy: .public)")
        }

        // Reachable delivery is a latency optimization; application context
        // remains the durable fallback if this immediate send fails.
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                logger.error("Immediate Watch snapshot failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Focus state is part of the versioned snapshot, eliminating the former
    /// key and Date-encoding drift between one-off focus messages and sync.
    func sendFocusStarted(endsAt: Date) {
        _ = endsAt
        sendSyncSnapshot()
    }

    func sendFocusEnded() {
        sendSyncSnapshot()
    }

    func buildSnapshot(at generatedAt: Date = .now) -> WatchSnapshot? {
        guard let context = modelContext,
              let activeProfileID = ActiveProfileManager.shared.activeProfile?.clientID else {
            return emptySnapshot(generatedAt: generatedAt)
        }

        let agendaDescriptor = FetchDescriptor<AgendaItem>(
            predicate: #Predicate { !$0.isComplete },
            sortBy: [SortDescriptor(\.scheduledDate), SortDescriptor(\.sortOrder)]
        )
        let allAgendaItems: [AgendaItem]
        do {
            allAgendaItems = try context.fetch(agendaDescriptor)
        } catch {
            logger.error(
                "Watch snapshot agenda fetch failed; preserving the last delivered snapshot: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
        let agendaItems = allAgendaItems
            .filter { belongsToActiveProfile($0.assignedToProfileID, activeProfileID: activeProfileID) }
            .prefix(32)
            .map {
                WatchAgendaSummary(
                    clientID: $0.clientID,
                    title: $0.title,
                    scheduledDate: $0.scheduledDate,
                    isAllDay: $0.isAllDay,
                    snoozedUntil: $0.snoozedUntil,
                    frictionLevel: $0.frictionLevel,
                    contextTag: $0.contextTag
                )
            }

        let taskDescriptor = FetchDescriptor<AgendaTask>(
            predicate: #Predicate { !$0.isComplete && !$0.isAbandoned },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        let allTasks: [AgendaTask]
        do {
            allTasks = try context.fetch(taskDescriptor)
        } catch {
            logger.error(
                "Watch snapshot task fetch failed; preserving the last delivered snapshot: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
        let profileTasks = allTasks.filter {
            belongsToActiveProfile($0.assignedToProfileID, activeProfileID: activeProfileID)
        }
        let relationshipDescriptor = FetchDescriptor<TaskRelationship>(
            predicate: #Predicate {
                $0.typeRaw == "blocks" || $0.typeRaw == "follows"
            }
        )
        let blockingRelationships: [TaskRelationship]
        do {
            blockingRelationships = try context.fetch(relationshipDescriptor)
        } catch {
            logger.error(
                "Watch snapshot relationship fetch failed; preserving the last delivered snapshot: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
        let blockedIDs = TaskProjectionIndex.blockedTaskIDs(
            tasks: allTasks,
            relationships: blockingRelationships
        )
        let actionableTasks = profileTasks.filter {
            TaskProjectionIndex.isLifecycleActionable($0, now: generatedAt)
                && !blockedIDs.contains($0.clientID)
        }
        let backlogTasks = actionableTasks.prefix(16).map {
            WatchBacklogSummary(
                clientID: $0.clientID,
                title: $0.title,
                frictionLevel: $0.frictionLevel,
                contextTag: $0.contextTag,
                sortOrder: $0.sortOrder
            )
        }

        let preferences = ActiveProfileManager.shared.activePreferences
        return WatchSnapshot(
            schemaVersion: WatchSyncContract.schemaVersion,
            snapshotID: UUID(),
            generatedAt: generatedAt,
            profileID: activeProfileID,
            agendaItems: Array(agendaItems),
            backlogTasks: Array(backlogTasks),
            currentEnergyLevel: preferences?.currentEnergyLevel ?? 3,
            densityModeRaw: preferences?.effectiveDensity.rawValue,
            focusSessionActive: NotificationManager.shared.focusSessionActive,
            focusSessionEndsAt: NotificationManager.shared.focusSessionEndsAt,
            pendingTaskCount: profileTasks.count,
            lowFrictionTaskCount: actionableTasks.filter { $0.frictionLevel <= 2 }.count,
            pendingRecovery: InterruptionContext.currentActivity() != nil
        )
    }

    private func emptySnapshot(generatedAt: Date) -> WatchSnapshot {
        WatchSnapshot(
            schemaVersion: WatchSyncContract.schemaVersion,
            snapshotID: UUID(),
            generatedAt: generatedAt,
            profileID: nil,
            agendaItems: [],
            backlogTasks: [],
            currentEnergyLevel: 3,
            densityModeRaw: nil,
            focusSessionActive: false,
            focusSessionEndsAt: nil,
            pendingTaskCount: 0,
            lowFrictionTaskCount: 0,
            pendingRecovery: false
        )
    }

    private func belongsToActiveProfile(_ assignedID: UUID?, activeProfileID: UUID) -> Bool {
        // Unassigned legacy records are visible to the locally active profile,
        // matching the app's existing task filtering. Records assigned to any
        // other household profile never cross the Watch transport boundary.
        assignedID == nil || assignedID == activeProfileID
    }

    // MARK: Watch -> Phone mutations

    private func handleIncoming(_ message: [String: Any]) {
        guard let rawType = message[WatchSyncContract.messageTypeKey] as? String,
              let type = WatchSyncContract.MessageType(rawValue: rawType) else {
            return
        }

        switch type {
        case .mutation:
            do {
                let mutation = try WatchSyncContract.decode(
                    WatchMutation.self,
                    from: message,
                    expectedMessageType: .mutation
                )
                handleMutation(mutation)
            } catch {
                logger.error("Rejected malformed Watch mutation: \(error.localizedDescription, privacy: .public)")
            }
        case .requestSync:
            sendSyncSnapshot()
        case .syncSnapshot, .acknowledgement:
            break
        }
    }

    private func handleMutation(_ mutation: WatchMutation) {
        guard mutation.schemaVersion == WatchSyncContract.schemaVersion else {
            sendAcknowledgement(
                WatchAcknowledgement(
                    eventID: mutation.eventID,
                    status: .rejected,
                    reason: "Unsupported sync schema"
                )
            )
            return
        }

        if hasProcessed(mutation.eventID) {
            // A prior launch may have persisted the mutation and ledger but
            // terminated before publishing its replacement snapshot.
            sendSyncSnapshot()
            sendAcknowledgement(
                WatchAcknowledgement(eventID: mutation.eventID, status: .duplicate)
            )
            return
        }

        let acknowledgement = apply(mutation)
        if acknowledgement.status == .applied {
            recordProcessed(mutation.eventID)
            lastWatchAction = mutation.kind
            sendSyncSnapshot()
        }
        sendAcknowledgement(acknowledgement)
    }

    private func apply(_ mutation: WatchMutation) -> WatchAcknowledgement {
        guard let context = modelContext else {
            return retryable(mutation, reason: "Phone data store unavailable")
        }
        guard let activeProfileID = ActiveProfileManager.shared.activeProfile?.clientID,
              activeProfileID == mutation.profileID else {
            return rejected(mutation, reason: "Active profile changed")
        }

        switch mutation.kind {
        case .completeAgendaItem:
            guard let item = agendaItem(
                id: mutation.agendaItemID,
                activeProfileID: activeProfileID,
                in: context
            ) else {
                return rejected(mutation, reason: "Agenda item unavailable")
            }
            if !item.isComplete {
                do {
                    let next = try AgendaItemLifecycleService.complete(
                        item,
                        in: context,
                        at: mutation.createdAt
                    )
                    if let next {
                        NotificationManager.shared.scheduleNotifications(for: next)
                    }
                } catch {
                    return retryable(mutation, reason: "Could not save completion")
                }
            }
            NotificationManager.shared.cancelNotifications(for: item)

        case .snoozeAgendaItem:
            guard let minutes = mutation.snoozeMinutes, (1...1_440).contains(minutes) else {
                return rejected(mutation, reason: "Invalid snooze duration")
            }
            guard let item = agendaItem(
                id: mutation.agendaItemID,
                activeProfileID: activeProfileID,
                in: context
            ) else {
                return rejected(mutation, reason: "Agenda item unavailable")
            }
            // Derive the deadline from the immutable event timestamp so a
            // replay after a crash cannot extend the snooze a second time.
            let snoozeDate = mutation.createdAt.addingTimeInterval(Double(minutes) * 60)
            item.snoozedUntil = snoozeDate
            item.updatedAt = max(item.updatedAt, mutation.createdAt)
            guard save(context) else {
                return retryable(mutation, reason: "Could not save snooze")
            }
            NotificationManager.shared.scheduleSnooze(
                item: item,
                at: snoozeDate
            )

        case .updateEnergy:
            guard let level = mutation.energyLevel, TaskFieldDomain.energy.contains(level),
                  let preferences = ActiveProfileManager.shared.activePreferences else {
                return rejected(mutation, reason: "Invalid energy level")
            }
            preferences.currentEnergyLevel = level
            preferences.updatedAt = .now
            guard save(context) else {
                return retryable(mutation, reason: "Could not save energy")
            }

        case .captureTask:
            let title = mutation.captureTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty, title.count <= 500 else {
                return rejected(mutation, reason: "Invalid capture")
            }
            // The event ID is also the created task's durable identity. If the
            // app committed the task and terminated before updating the
            // UserDefaults acknowledgement ledger, redelivery finds this
            // record and remains exactly-once from the user's perspective.
            if agendaTask(id: mutation.eventID, in: context) != nil {
                return WatchAcknowledgement(
                    eventID: mutation.eventID,
                    status: .applied
                )
            }
            let task = AgendaTask(
                title: title,
                frictionLevel: 3,
                energyRequired: 2,
                estimatedMinutes: 15
            )
            task.clientID = mutation.eventID
            task.createdAt = mutation.createdAt
            task.updatedAt = mutation.createdAt
            task.assignedToProfileID = activeProfileID
            context.insert(task)
            guard save(context) else {
                return retryable(mutation, reason: "Could not save capture")
            }
        }

        return WatchAcknowledgement(eventID: mutation.eventID, status: .applied)
    }

    private func agendaItem(
        id: UUID?,
        activeProfileID: UUID,
        in context: ModelContext
    ) -> AgendaItem? {
        guard let id else { return nil }
        let descriptor = FetchDescriptor<AgendaItem>(
            predicate: #Predicate { $0.clientID == id }
        )
        guard let item = (try? context.fetch(descriptor))?.first,
              belongsToActiveProfile(item.assignedToProfileID, activeProfileID: activeProfileID) else {
            return nil
        }
        return item
    }

    private func agendaTask(id: UUID, in context: ModelContext) -> AgendaTask? {
        let descriptor = FetchDescriptor<AgendaTask>(
            predicate: #Predicate { $0.clientID == id }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func save(_ context: ModelContext) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            logger.error("Watch mutation save failed: \(error.localizedDescription, privacy: .public)")
            ErrorBannerController.shared.show("Watch sync failed to save: \(error.localizedDescription)")
            return false
        }
    }

    private func rejected(_ mutation: WatchMutation, reason: String) -> WatchAcknowledgement {
        WatchAcknowledgement(eventID: mutation.eventID, status: .rejected, reason: reason)
    }

    private func retryable(_ mutation: WatchMutation, reason: String) -> WatchAcknowledgement {
        WatchAcknowledgement(eventID: mutation.eventID, status: .retryable, reason: reason)
    }

    private func sendAcknowledgement(_ acknowledgement: WatchAcknowledgement) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let message: [String: Any]
        do {
            message = try WatchSyncContract.message(
                type: .acknowledgement,
                payload: acknowledgement
            )
        } catch {
            logger.error("Failed to encode Watch acknowledgement: \(error.localizedDescription, privacy: .public)")
            return
        }

        // Acknowledgements must survive either process sleeping.
        session.transferUserInfo(message)
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                logger.error("Immediate Watch acknowledgement failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Durable idempotency ledger

    private func hasProcessed(_ eventID: UUID) -> Bool {
        processedMutationIDs.contains(eventID.uuidString)
    }

    private func recordProcessed(_ eventID: UUID) {
        var ids = processedMutationIDs
        ids.removeAll(where: { $0 == eventID.uuidString })
        ids.append(eventID.uuidString)
        if ids.count > maximumProcessedMutationCount {
            ids.removeFirst(ids.count - maximumProcessedMutationCount)
        }
        UserDefaults.standard.set(ids, forKey: processedMutationDefaultsKey)
    }

    private var processedMutationIDs: [String] {
        UserDefaults.standard.stringArray(forKey: processedMutationDefaultsKey) ?? []
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
            if activationState == .activated {
                sendSyncSnapshot()
            }
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

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in handleIncoming(message) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in handleIncoming(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in handleIncoming(userInfo) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}

#endif
