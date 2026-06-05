// DifficultyEngine.swift
// AuGenda
//
// Pure logic — turns six task attributes into a single 0–10 difficulty rank
// and a named band, then maps that rank onto the DensityMode filter ceiling.
//
// Spec: memory/task_difficulty_and_ai_enrichment.md
//
// Key insight: difficulty is NOT a single user-assigned number for AuDHD
// brains. The boring-easy paradox (washing dishes) and the IRS-letter
// problem (30-second dread task) both prove that classic 1–5 difficulty
// stars collapse independent dimensions. We model six axes — friction,
// energy, sensory load, social load, initiation cost, interest — and
// project them into one rank using a weighted formula. The rank is
// COMPUTED, not stored, so the formula can evolve without migrations.

import Foundation

// MARK: - DifficultyBand

/// Named bands the rank falls into. Used by the dashboard to label
/// difficulty without exposing the raw 0–10 number (which invites
/// gamification we don't want for AuDHD users).
enum DifficultyBand: String, CaseIterable, Sendable {
    case trivial
    case easy
    case moderate
    case hard
    case demanding

    /// Map a 0–10 rank into its band.
    init(rank: Int) {
        switch rank {
        case ..<3:  self = .trivial
        case 3...4: self = .easy
        case 5...6: self = .moderate
        case 7...8: self = .hard
        default:    self = .demanding
        }
    }

    var label: String {
        switch self {
        case .trivial:   return "Trivial"
        case .easy:      return "Easy"
        case .moderate:  return "Moderate"
        case .hard:      return "Hard"
        case .demanding: return "Demanding"
        }
    }

    /// One-line tooltip explanation surfaced in the editor + on hover.
    var description: String {
        switch self {
        case .trivial:   return "Pick-up-and-go. No real cost."
        case .easy:      return "Quick to do; minimal load."
        case .moderate:  return "Standard. Some real effort."
        case .hard:      return "Heavy. Needs capacity to start."
        case .demanding: return "Big lift. Save for high-capacity windows."
        }
    }

    /// Stable sort order (trivial = 0, demanding = 4).
    var sortOrder: Int {
        switch self {
        case .trivial:   return 0
        case .easy:      return 1
        case .moderate:  return 2
        case .hard:      return 3
        case .demanding: return 4
        }
    }
}

// MARK: - DifficultyEngine

/// Pure projection from the six input axes to a 0–10 rank. Stateless,
/// deterministic, no SwiftData dependency — easy to unit-test.
///
/// Formula weights live here (single source of truth). Per-profile
/// weighting (e.g. autism profiles weighting sensory heavier) is a v2
/// extension — for now we use the universal weights.
enum DifficultyEngine {

    /// Compute the 0–10 difficulty rank from the six input axes.
    ///
    /// - Parameters:
    ///   - friction: 1–4 — execution effort
    ///   - energy: 1–4 — running cost
    ///   - sensoryLoad: 0–3 — environmental load
    ///   - socialLoad: 0–3 — communication weight
    ///   - initiationCost: 0–3 — first-step / dread weight
    ///   - interest: 1–5 — intrinsic engagement (absorbs difficulty)
    /// - Returns: integer 0–10
    static func rank(
        friction: Int,
        energy: Int,
        sensoryLoad: Int,
        socialLoad: Int,
        initiationCost: Int,
        interest: Int
    ) -> Int {
        // Clamp inputs defensively in case stored data drifts out of range.
        let f = clamped(friction,        to: 1...4)
        let e = clamped(energy,          to: 1...4)
        let s = clamped(sensoryLoad,     to: 0...3)
        let c = clamped(socialLoad,      to: 0...3)
        let i = clamped(initiationCost,  to: 0...3)
        let n = clamped(interest,        to: 1...5)

        // Per-axis weighted contributions (see spec for rationale).
        let raw =
              Double(f) * 2.0          //  max  8.0  — friction heavy
            + Double(e) * 1.5          //  max  6.0  — energy
            + Double(s) * 1.0          //  max  3.0  — sensory
            + Double(c) * 1.0          //  max  3.0  — social
            + Double(i) * 2.0          //  max  6.0  — initiation heavy
            - Double(n - 1) * 1.0      //  max -4.0  — interest absorbs

        let bounded = max(0.0, min(30.0, raw))
        return Int((bounded / 3.0).rounded())   // 0–30 → 0–10
    }

    private static func clamped<T: Comparable>(_ value: T, to range: ClosedRange<T>) -> T {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - AgendaTask conformance

extension AgendaTask {

    /// 0–10 difficulty rank, derived from the six axes on this task.
    /// Computed, not stored — formula can evolve without migration.
    var difficultyRank: Int {
        DifficultyEngine.rank(
            friction:       frictionLevel,
            energy:         energyRequired,
            sensoryLoad:    sensoryLoad,
            socialLoad:     socialLoad,
            initiationCost: initiationCost,
            interest:       interestLevel
        )
    }

    var difficultyBand: DifficultyBand {
        DifficultyBand(rank: difficultyRank)
    }
}

// MARK: - AgendaItem conformance

extension AgendaItem {

    /// 0–10 difficulty rank, derived from the six axes on this item.
    var difficultyRank: Int {
        DifficultyEngine.rank(
            friction:       frictionLevel,
            energy:         energyRequired,
            sensoryLoad:    sensoryLoad,
            socialLoad:     socialLoad,
            initiationCost: initiationCost,
            interest:       interestLevel
        )
    }

    var difficultyBand: DifficultyBand {
        DifficultyBand(rank: difficultyRank)
    }
}

// MARK: - DensityMode → max rank

extension DensityMode {

    /// Per the spec's band-to-mode mapping:
    ///   survival   → ≤ 4 (Trivial + Easy)
    ///   low        → ≤ 6 (+ Moderate)
    ///   functional → ≤ 8 (+ Hard)
    ///   high       → ≤ 10 (everything)
    ///
    /// Used as the ceiling when filtering task feeds by density mode.
    /// `specialInterest` items bypass this filter — see `passes(densityFilter:)`.
    var maxDifficultyRank: Int {
        switch self {
        case .survival:   return 4
        case .low:        return 6
        case .functional: return 8
        case .high:       return 10
        }
    }
}

// MARK: - Filter helpers

extension AgendaTask {
    /// Does this task pass the difficulty filter for the given density mode?
    /// `specialInterest` items bypass the filter (hyperfocus override).
    func passes(densityFilter mode: DensityMode) -> Bool {
        if specialInterest { return true }
        return difficultyRank <= mode.maxDifficultyRank
    }
}

extension AgendaItem {
    /// Does this item pass the difficulty filter for the given density mode?
    /// `specialInterest` items bypass the filter (hyperfocus override).
    func passes(densityFilter mode: DensityMode) -> Bool {
        if specialInterest { return true }
        return difficultyRank <= mode.maxDifficultyRank
    }
}
