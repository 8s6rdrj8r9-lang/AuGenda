// DifficultyEngineTests.swift
// AuGendaTests
//
// First real coverage for the six-axis difficulty model — the core of the
// beta thesis (capacity-adaptive filtering). DifficultyEngine is pure and
// deterministic, so these are exact-value regression locks: if the weighting
// formula changes, these fail loudly and on purpose.

import Testing
@testable import AuGenda

struct DifficultyEngineTests {

    // MARK: - rank() extremes

    @Test func minimumInputsRankZero() {
        // Easiest possible: low friction/energy, no loads, max interest.
        let rank = DifficultyEngine.rank(
            friction: 1, energy: 1, sensoryLoad: 0,
            socialLoad: 0, initiationCost: 0, interest: 5
        )
        #expect(rank == 0)
        #expect(DifficultyBand(rank: rank) == .trivial)
    }

    @Test func maximumInputsRankNine() {
        // Hardest possible within the documented ranges. Note the achievable
        // ceiling is 9, not 10 (raw max is 26 → 26/3 ≈ 8.67 → 9): rank 10 is
        // unreachable by design. This test pins that fact.
        let rank = DifficultyEngine.rank(
            friction: 4, energy: 4, sensoryLoad: 3,
            socialLoad: 3, initiationCost: 3, interest: 1
        )
        #expect(rank == 9)
        #expect(DifficultyBand(rank: rank) == .demanding)
    }

    @Test func midRangeExample() {
        // friction3·2 + energy2·1.5 + sensory1 + social1 + init1·2 - (3-1)
        // = 6 + 3 + 1 + 1 + 2 - 2 = 11 → 11/3 ≈ 3.67 → 4
        let rank = DifficultyEngine.rank(
            friction: 3, energy: 2, sensoryLoad: 1,
            socialLoad: 1, initiationCost: 1, interest: 3
        )
        #expect(rank == 4)
        #expect(DifficultyBand(rank: rank) == .easy)
    }

    // MARK: - Interest absorbs difficulty

    @Test func higherInterestLowersRank() {
        func rankFor(interest: Int) -> Int {
            DifficultyEngine.rank(
                friction: 3, energy: 3, sensoryLoad: 1,
                socialLoad: 1, initiationCost: 2, interest: interest
            )
        }
        let tedious = rankFor(interest: 1)
        let engaging = rankFor(interest: 5)
        #expect(engaging < tedious)
        // Exact lock: 16.5/3 = 5.5 → 6 ; 12.5/3 ≈ 4.17 → 4
        #expect(tedious == 6)
        #expect(engaging == 4)
    }

    // MARK: - Defensive clamping (stored data may drift out of range)

    @Test func inputsAboveRangeClampToMax() {
        let absurd = DifficultyEngine.rank(
            friction: 99, energy: 99, sensoryLoad: 99,
            socialLoad: 99, initiationCost: 99, interest: 99
        )
        let clamped = DifficultyEngine.rank(
            friction: 4, energy: 4, sensoryLoad: 3,
            socialLoad: 3, initiationCost: 3, interest: 5
        )
        #expect(absurd == clamped)
    }

    @Test func inputsBelowRangeClampToMin() {
        let negative = DifficultyEngine.rank(
            friction: -5, energy: -5, sensoryLoad: -5,
            socialLoad: -5, initiationCost: -5, interest: -5
        )
        let clamped = DifficultyEngine.rank(
            friction: 1, energy: 1, sensoryLoad: 0,
            socialLoad: 0, initiationCost: 0, interest: 1
        )
        #expect(negative == clamped)
    }

    // MARK: - Band boundaries

    @Test func bandBoundaries() {
        #expect(DifficultyBand(rank: 0) == .trivial)
        #expect(DifficultyBand(rank: 2) == .trivial)
        #expect(DifficultyBand(rank: 3) == .easy)
        #expect(DifficultyBand(rank: 4) == .easy)
        #expect(DifficultyBand(rank: 5) == .moderate)
        #expect(DifficultyBand(rank: 6) == .moderate)
        #expect(DifficultyBand(rank: 7) == .hard)
        #expect(DifficultyBand(rank: 8) == .hard)
        #expect(DifficultyBand(rank: 9) == .demanding)
        #expect(DifficultyBand(rank: 10) == .demanding)
    }

    // MARK: - Density-mode ceilings (the filter the dashboard relies on)

    @Test func densityCeilings() {
        #expect(DensityMode.survival.maxDifficultyRank == 4)
        #expect(DensityMode.low.maxDifficultyRank == 6)
        #expect(DensityMode.functional.maxDifficultyRank == 8)
        #expect(DensityMode.high.maxDifficultyRank == 10)
    }

    // MARK: - passes(densityFilter:) on a real model

    @MainActor
    @Test func densityFilterAndSpecialInterestBypass() {
        // A demanding task (rank 9) is filtered out of survival but shown in high.
        let hard = AgendaTask(title: "Tax appeal letter",
                              frictionLevel: 4, energyRequired: 4, interestLevel: 1)
        hard.sensoryLoad = 3
        hard.socialLoad = 3
        hard.initiationCost = 3
        #expect(hard.difficultyRank == 9)
        #expect(hard.passes(densityFilter: .high))
        #expect(!hard.passes(densityFilter: .survival))

        // specialInterest is the hyperfocus override — bypasses the ceiling.
        hard.specialInterest = true
        #expect(hard.passes(densityFilter: .survival))
    }
}
