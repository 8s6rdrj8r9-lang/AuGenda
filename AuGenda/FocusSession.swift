// FocusSession.swift
// AuGenda
//
// Persistent FocusSession model.
// Tracks start time, end time, interruptions, and completion state.

import Foundation
import SwiftData

enum FocusSessionState: String, Codable, CaseIterable {
    case idle
    case active
    case paused
    case completed
    case abandoned
}

@Model
final class FocusSession {
    
    var clientID: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    
    var startTime: Date = Date.now
    var endTime: Date? = nil
    var plannedDurationMinutes: Int = 25
    
    var taskID: UUID? = nil
    var taskTitle: String = ""
    
    var stateRaw: String = FocusSessionState.idle.rawValue
    
    var interruptionCount: Int = 0
    var interruptionTimestamps: [Date] = []
    var interruptionReasons: [String] = []
    var wasCompleted: Bool = false
    var wasAbandoned: Bool = false
    var abandonReason: String = ""
    
    var profileID: UUID? = nil
    
    var state: FocusSessionState {
        get { FocusSessionState(rawValue: stateRaw) ?? .idle }
        set { stateRaw = newValue.rawValue; updatedAt = .now }
    }
    
    var actualDurationMinutes: Int {
        guard let end = endTime else {
            return Int(Date.now.timeIntervalSince(startTime) / 60)
        }
        return Int(end.timeIntervalSince(startTime) / 60)
    }
    
    var isOverdue: Bool {
        guard state == .active else { return false }
        return Date.now > plannedEndTime
    }

    var plannedEndTime: Date {
        startTime.addingTimeInterval(Double(plannedDurationMinutes) * 60)
    }
    
    func recordInterruption(reason: String = "") {
        interruptionCount += 1
        interruptionTimestamps.append(.now)
        interruptionReasons.append(reason)
        updatedAt = .now
    }
    
    init(
        plannedDurationMinutes: Int = 25,
        taskID: UUID? = nil,
        taskTitle: String = "",
        profileID: UUID? = nil
    ) {
        self.clientID = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.startTime = .now
        self.plannedDurationMinutes = plannedDurationMinutes
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.profileID = profileID
        self.state = .active
    }
}

extension FocusSession {
    static var activeSessionDescriptor: FetchDescriptor<FocusSession> {
        let activeRaw = FocusSessionState.active.rawValue
        return FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.stateRaw == activeRaw }
        )
    }
}
