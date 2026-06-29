// CognitiveProfile.swift
// AuGenda
//
// Lightweight cognitive profile aggregator.
// Reads existing data to produce insights about the user's patterns.

import Foundation
import SwiftData

enum CognitiveProfile {
    
    /// Typical productive window length based on completed focus sessions.
    /// Returns the median actual duration of completed sessions in the last 30 days.
    static func typicalWindowLengthMinutes(in context: ModelContext) -> Int {
        let thirtyDaysAgo = Date.now.addingTimeInterval(-30 * 24 * 60 * 60)
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.wasCompleted && $0.startTime > thirtyDaysAgo }
        )
        guard let sessions = try? context.fetch(descriptor), !sessions.isEmpty else {
            return 25 // default
        }
        let durations = sessions.map { $0.actualDurationMinutes }.sorted()
        return durations[durations.count / 2]
    }
    
    /// Suggests a focus session length based on historical data and current energy.
    static func suggestedFocusLength(in context: ModelContext, energyLevel: Int) -> Int {
        let typical = typicalWindowLengthMinutes(in: context)
        let scale = Double(energyLevel) / 3.0
        return max(5, Int(Double(typical) * scale))
    }
}
