// WatchSyncContract.swift
// Shared by the iPhone app, Watch app, and Watch widget extension.

import Foundation

enum WatchSyncContract {
    static let schemaVersion = 1
    static let snapshotMaxAge: TimeInterval = 6 * 60 * 60
    static let widgetKind = "AuGendaNowWidget"

    static let messageTypeKey = "messageType"
    static let payloadKey = "payload"

    enum MessageType: String {
        case syncSnapshot
        case mutation
        case acknowledgement
        case requestSync
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    static func message<T: Encodable>(
        type: MessageType,
        payload: T
    ) throws -> [String: Any] {
        [
            messageTypeKey: type.rawValue,
            payloadKey: try encoder().encode(payload)
        ]
    }

    static func decode<T: Decodable>(
        _ type: T.Type,
        from message: [String: Any],
        expectedMessageType: MessageType
    ) throws -> T {
        guard message[messageTypeKey] as? String == expectedMessageType.rawValue,
              let data = message[payloadKey] as? Data else {
            throw WatchSyncContractError.invalidEnvelope
        }
        return try decoder().decode(type, from: data)
    }

    static var requestSyncMessage: [String: Any] {
        [messageTypeKey: MessageType.requestSync.rawValue]
    }
}

enum WatchSyncContractError: Error {
    case invalidEnvelope
}

struct WatchAgendaSummary: Codable, Equatable, Identifiable {
    var id: UUID { clientID }

    var clientID: UUID
    var title: String
    var scheduledDate: Date
    var isAllDay: Bool
    var snoozedUntil: Date?
    var frictionLevel: Int
    var contextTag: String
}

struct WatchBacklogSummary: Codable, Equatable, Identifiable {
    var id: UUID { clientID }

    var clientID: UUID
    var title: String
    var frictionLevel: Int
    var contextTag: String
    var sortOrder: Int
}

/// Full-replacement state. Absence from either item array is a deletion.
struct WatchSnapshot: Codable, Equatable {
    var schemaVersion: Int
    var snapshotID: UUID
    var generatedAt: Date
    var profileID: UUID?
    var agendaItems: [WatchAgendaSummary]
    var backlogTasks: [WatchBacklogSummary]
    var currentEnergyLevel: Int
    var densityModeRaw: String?
    var focusSessionActive: Bool
    var focusSessionEndsAt: Date?
    var pendingTaskCount: Int
    var lowFrictionTaskCount: Int
    var pendingRecovery: Bool

    func isFresh(
        at date: Date = .now,
        maxAge: TimeInterval = WatchSyncContract.snapshotMaxAge
    ) -> Bool {
        guard schemaVersion == WatchSyncContract.schemaVersion else { return false }
        // Treat snapshots implausibly far in the future as invalid instead of
        // allowing a clock error to keep sensitive titles visible indefinitely.
        guard generatedAt <= date.addingTimeInterval(5 * 60) else { return false }
        return date.timeIntervalSince(generatedAt) <= maxAge
    }
}

enum WatchMutationKind: String, Codable {
    case completeAgendaItem
    case snoozeAgendaItem
    case updateEnergy
    case captureTask
}

struct WatchMutation: Codable, Equatable, Identifiable {
    var id: UUID { eventID }

    var schemaVersion: Int
    var eventID: UUID
    var createdAt: Date
    var profileID: UUID
    var kind: WatchMutationKind
    var agendaItemID: UUID?
    var snoozeMinutes: Int?
    var energyLevel: Int?
    var captureTitle: String?

    init(
        eventID: UUID = UUID(),
        createdAt: Date = .now,
        profileID: UUID,
        kind: WatchMutationKind,
        agendaItemID: UUID? = nil,
        snoozeMinutes: Int? = nil,
        energyLevel: Int? = nil,
        captureTitle: String? = nil
    ) {
        self.schemaVersion = WatchSyncContract.schemaVersion
        self.eventID = eventID
        self.createdAt = createdAt
        self.profileID = profileID
        self.kind = kind
        self.agendaItemID = agendaItemID
        self.snoozeMinutes = snoozeMinutes
        self.energyLevel = energyLevel
        self.captureTitle = captureTitle
    }
}

struct PendingWatchMutation: Codable, Equatable {
    var mutation: WatchMutation
    var attemptCount: Int
    var lastAttemptAt: Date?

    init(mutation: WatchMutation) {
        self.mutation = mutation
        self.attemptCount = 0
        self.lastAttemptAt = nil
    }

    func isDue(at date: Date, retryInterval: TimeInterval) -> Bool {
        guard let lastAttemptAt else { return true }
        return date.timeIntervalSince(lastAttemptAt) >= retryInterval
    }
}

enum WatchAcknowledgementStatus: String, Codable {
    case applied
    case duplicate
    case rejected
    case retryable
}

struct WatchAcknowledgement: Codable, Equatable {
    var schemaVersion: Int
    var eventID: UUID
    var status: WatchAcknowledgementStatus
    var reason: String?

    init(
        eventID: UUID,
        status: WatchAcknowledgementStatus,
        reason: String? = nil
    ) {
        self.schemaVersion = WatchSyncContract.schemaVersion
        self.eventID = eventID
        self.status = status
        self.reason = reason
    }
}
