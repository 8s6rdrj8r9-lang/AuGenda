// CognitiveProfile.swift
// AuGenda
//
// Lightweight cognitive profile aggregator.
// Reads existing data to produce insights about the user's patterns.

import Foundation
import SwiftData

enum CognitiveProfile {
    
    /// Typical productive window length based on completed focus sessions.
    /// Returns the median actual duration of completed sessions in the last 30 days for the given profile.
    @MainActor
    static func typicalWindowLengthMinutes(
        in context: ModelContext,
        profileID: UUID? = nil
    ) -> Int {
        let targetID = profileID ?? ActiveProfileManager.shared.activeProfile?.clientID
        let thirtyDaysAgo = Date.now.addingTimeInterval(-30 * 24 * 60 * 60)
        let descriptor: FetchDescriptor<FocusSession>
        if let targetID {
            descriptor = FetchDescriptor<FocusSession>(
                predicate: #Predicate {
                    $0.wasCompleted && $0.startTime > thirtyDaysAgo && ($0.profileID == nil || $0.profileID == targetID)
                }
            )
        } else {
            descriptor = FetchDescriptor<FocusSession>(
                predicate: #Predicate { $0.wasCompleted && $0.startTime > thirtyDaysAgo }
            )
        }
        guard let sessions = try? context.fetch(descriptor), !sessions.isEmpty else {
            return 25 // default
        }
        let durations = sessions.map { $0.actualDurationMinutes }.sorted()
        return durations[durations.count / 2]
    }
    
    /// Suggests a focus session length based on historical data and current energy.
    @MainActor
    static func suggestedFocusLength(
        in context: ModelContext,
        energyLevel: Int,
        profileID: UUID? = nil
    ) -> Int {
        let typical = typicalWindowLengthMinutes(in: context, profileID: profileID)
        let scale = Double(energyLevel) / 3.0
        return max(5, Int(Double(typical) * scale))
    }
}
