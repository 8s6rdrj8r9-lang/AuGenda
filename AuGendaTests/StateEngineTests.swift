// StateEngineTests.swift
// AuGendaTests
//
// Coverage for the capacity-transition engine repaired in the state-engine
// fix push:
//   • DensityAdvisor pure logic (the snooze/completion nudge rules)
//   • ProfilePreferences.effectiveDensity precedence (the single resolution
//     rule: pin wins, else auto-from-energy)
//
// DensityAdvisor.suggestion(currentDensity:recentSnoozes:recentCompletions:)
// is a pure overload — no ActivityLog I/O — so these are exact, deterministic
// regression locks, mirroring the DifficultyEngine pure-logic pattern.

import Testing
@testable import AuGenda

struct DensityAdvisorTests {

    // MARK: - Drop (cascading snoozes → calmer)

    @Test func dropFiresAtThreeSnoozes() {
        let suggestion = DensityAdvisor.suggestion(
            currentDensity: .functional,
            recentSnoozes: 3,
            recentCompletions: 0
        )
        #expect(suggestion?.target == .low)
    }

    @Test func dropDoesNotFireBelowThreshold() {
        let suggestion = DensityAdvisor.suggestion(
            currentDensity: .functional,
            recentSnoozes: 2,
            recentCompletions: 0
        )
        #expect(suggestion == nil)
    }

    // MARK: - Raise (sustained progress → busier)

    @Test func raiseFiresAtThreeCompletionsWithNoSnoozes() {
        let suggestion = DensityAdvisor.suggestion(
            currentDensity: .functional,
            recentSnoozes: 0,
            recentCompletions: 3
        )
        #expect(suggestion?.target == .high)
    }

    @Test func snoozesSuppressRaise() {
        // Even with plenty of completions, any snooze in the window blocks the
        // raise — progress-with-friction shouldn't push the user busier.
        let suggestion = DensityAdvisor.suggestion(
            currentDensity: .functional,
            recentSnoozes: 1,
            recentCompletions: 5
        )
        #expect(suggestion == nil)
    }

    // MARK: - Edges (can't step past the ends of the scale)

    @Test func survivalCannotDrop() {
        let suggestion = DensityAdvisor.suggestion(
            currentDensity: .survival,
            recentSnoozes: 5,
            recentCompletions: 0
        )
        #expect(suggestion == nil)
    }

    @Test func highCannotRaise() {
        let suggestion = DensityAdvisor.suggestion(
            currentDensity: .high,
            recentSnoozes: 0,
            recentCompletions: 5
        )
        #expect(suggestion == nil)
    }

    // MARK: - Determinism

    @Test func sameInputsProduceSameSuggestion() {
        let first = DensityAdvisor.suggestion(
            currentDensity: .functional, recentSnoozes: 3, recentCompletions: 0
        )
        let second = DensityAdvisor.suggestion(
            currentDensity: .functional, recentSnoozes: 3, recentCompletions: 0
        )
        #expect(first == second)
    }
}

struct EffectiveDensityTests {

    // MARK: - effectiveDensity precedence

    @Test func explicitPinWins() {
        let prefs = ProfilePreferences()
        prefs.currentEnergyLevel = 4          // autoFrom → .high
        prefs.densityPinnedRaw = DensityMode.survival.rawValue
        // Pin overrides the energy-derived mode.
        #expect(prefs.effectiveDensity == .survival)
    }

    @Test func emptyRawFallsBackToAutoFrom() {
        let prefs = ProfilePreferences()
        prefs.currentEnergyLevel = 2          // autoFrom → .low
        prefs.densityPinnedRaw = ""
        #expect(prefs.effectiveDensity == .low)
    }

    @Test func junkRawFallsBackToAutoFrom() {
        let prefs = ProfilePreferences()
        prefs.currentEnergyLevel = 3          // autoFrom → .functional
        prefs.densityPinnedRaw = "not-a-real-mode"
        // densityPinned getter returns nil for an unparseable raw value, so
        // effectiveDensity must fall back to the energy-derived mode rather
        // than crash or pin to garbage.
        #expect(prefs.effectiveDensity == .functional)
    }

    // MARK: - representativeEnergyLevel round-trips through autoFrom

    @Test func representativeEnergyLevelRoundTrips() {
        for mode in DensityMode.allCases {
            #expect(DensityMode.autoFrom(energyLevel: mode.representativeEnergyLevel) == mode)
        }
    }
}
