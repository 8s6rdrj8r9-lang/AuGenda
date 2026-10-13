// WatchSharedStateStore.swift
// Shared by the Watch app and its widget extension.

import Foundation

struct RejectedWatchCapture: Codable, Equatable, Identifiable {
    var id: UUID { eventID }
    let eventID: UUID
    let profileID: UUID
    let title: String
    let reason: String
    let rejectedAt: Date
}

final class WatchSharedStateStore {
    static let appGroupIdentifier = "group.ensdev.AuGenda.watch"

    private static let snapshotKey = "watch.sync.snapshot.v1"
    private static let outboxKey = "watch.sync.outbox.v1"
    private static let rejectedCapturesKey = "watch.sync.rejectedCaptures.v1"
    private static let maximumOutboxCount = 256

    /// Nil means the App Group is unavailable. Production deliberately does
    /// not fall back to `.standard`: the Watch app and widget have different
    /// standard containers, so that fallback would acknowledge writes that the
    /// other process can never read.
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: Self.appGroupIdentifier)
    }

    func loadSnapshot() -> WatchSnapshot? {
        guard let defaults,
              let data = defaults.data(forKey: Self.snapshotKey) else {
            return nil
        }
        return try? WatchSyncContract.decoder().decode(WatchSnapshot.self, from: data)
    }

    /// Returns the fresh phone snapshot with queued Watch actions applied as a
    /// presentation overlay. The Watch app and complication share this path so
    /// neither can re-present an action that is still awaiting acknowledgement.
    func presentationSnapshot(
        from snapshot: WatchSnapshot? = nil,
        at date: Date = .now
    ) -> WatchSnapshot? {
        guard var presented = snapshot ?? loadSnapshot(),
              presented.profileID != nil,
              presented.isFresh(at: date) else {
            return nil
        }

        for entry in pendingMutations().sorted(by: {
            $0.mutation.createdAt < $1.mutation.createdAt
        }) {
            let mutation = entry.mutation
            guard mutation.profileID == presented.profileID else { continue }

            switch mutation.kind {
            case .completeAgendaItem:
                presented.agendaItems.removeAll { $0.clientID == mutation.agendaItemID }
            case .snoozeAgendaItem:
                guard let id = mutation.agendaItemID,
                      let minutes = mutation.snoozeMinutes,
                      let index = presented.agendaItems.firstIndex(where: {
                          $0.clientID == id
                      }) else {
                    continue
                }
                presented.agendaItems[index].snoozedUntil =
                    mutation.createdAt.addingTimeInterval(Double(minutes) * 60)
            case .updateEnergy:
                if let level = mutation.energyLevel {
                    presented.currentEnergyLevel = level
                    presented.densityModeRaw = nil
                }
            case .captureTask:
                guard let title = mutation.captureTitle else { continue }
                presented.backlogTasks.append(
                    WatchBacklogSummary(
                        clientID: mutation.eventID,
                        title: title,
                        frictionLevel: 3,
                        contextTag: "",
                        sortOrder: Int.max
                    )
                )
            }
        }

        return presented
    }

    /// Stores only current-schema snapshots and rejects out-of-order delivery.
    @discardableResult
    func save(snapshot: WatchSnapshot) -> Bool {
        guard let defaults,
              snapshot.schemaVersion == WatchSyncContract.schemaVersion else {
            return false
        }
        if let current = loadSnapshot(), current.generatedAt > snapshot.generatedAt {
            return false
        }
        guard let data = try? WatchSyncContract.encoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: Self.snapshotKey)
        return true
    }

    func pendingMutations() -> [PendingWatchMutation] {
        guard let defaults,
              let data = defaults.data(forKey: Self.outboxKey),
              let entries = try? WatchSyncContract.decoder().decode(
                [PendingWatchMutation].self,
                from: data
              ) else {
            return []
        }
        return entries
    }

    @discardableResult
    func enqueue(_ mutation: WatchMutation) -> Bool {
        guard mutation.schemaVersion == WatchSyncContract.schemaVersion,
              isValid(mutation) else {
            return false
        }
        var entries = pendingMutations()
        guard !entries.contains(where: { $0.mutation.eventID == mutation.eventID }) else {
            return false
        }
        // Never discard an unacknowledged user action to make room. Refuse the
        // new action so the UI can surface the queueing failure instead.
        guard entries.count < Self.maximumOutboxCount else { return false }
        entries.append(PendingWatchMutation(mutation: mutation))
        return save(entries)
    }

    private func isValid(_ mutation: WatchMutation) -> Bool {
        switch mutation.kind {
        case .completeAgendaItem:
            return mutation.agendaItemID != nil
        case .snoozeAgendaItem:
            guard mutation.agendaItemID != nil, let minutes = mutation.snoozeMinutes else {
                return false
            }
            return (1...1_440).contains(minutes)
        case .updateEnergy:
            guard let level = mutation.energyLevel else { return false }
            return (1...4).contains(level)
        case .captureTask:
            let title = mutation.captureTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !title.isEmpty && title.count <= 500
        }
    }

    func mutationsDue(
        at date: Date = .now,
        retryInterval: TimeInterval = 30
    ) -> [PendingWatchMutation] {
        pendingMutations().filter { $0.isDue(at: date, retryInterval: retryInterval) }
    }

    func markAttempted(eventID: UUID, at date: Date = .now) {
        var entries = pendingMutations()
        guard let index = entries.firstIndex(where: { $0.mutation.eventID == eventID }) else {
            return
        }
        entries[index].attemptCount += 1
        entries[index].lastAttemptAt = date
        _ = save(entries)
    }

    /// Makes a failed OS-managed transfer eligible for a new durable attempt.
    /// The mutation itself remains queued until a phone acknowledgement.
    func markTransferFailed(eventID: UUID) {
        var entries = pendingMutations()
        guard let index = entries.firstIndex(where: {
            $0.mutation.eventID == eventID
        }) else {
            return
        }
        entries[index].attemptCount = 0
        entries[index].lastAttemptAt = nil
        _ = save(entries)
    }

    func acknowledge(eventID: UUID) {
        let remaining = pendingMutations().filter { $0.mutation.eventID != eventID }
        _ = save(remaining)
    }

    func rejectedCaptures() -> [RejectedWatchCapture] {
        guard let defaults,
              let data = defaults.data(forKey: Self.rejectedCapturesKey),
              let entries = try? WatchSyncContract.decoder().decode(
                [RejectedWatchCapture].self,
                from: data
              ) else {
            return []
        }
        return entries
    }

    func saveRejectedCapture(_ capture: RejectedWatchCapture) {
        var entries = rejectedCaptures()
        entries.removeAll { $0.eventID == capture.eventID }
        entries.append(capture)
        guard let defaults,
              let data = try? WatchSyncContract.encoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.rejectedCapturesKey)
    }

    func removeRejectedCapture(eventID: UUID) {
        var entries = rejectedCaptures()
        entries.removeAll { $0.eventID == eventID }
        guard let defaults,
              let data = try? WatchSyncContract.encoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.rejectedCapturesKey)
    }

    @discardableResult
    private func save(_ entries: [PendingWatchMutation]) -> Bool {
        guard let defaults,
              let data = try? WatchSyncContract.encoder().encode(entries) else {
            return false
        }
        defaults.set(data, forKey: Self.outboxKey)
        return true
    }
}
