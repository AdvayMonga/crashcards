import Foundation
import Testing
@testable import crashcards

/// Chips, mult, and what a miss costs.
@Suite struct ScoringTests {
    /// Slower than any speed tier, so a test says what it means about timing.
    private let slow: TimeInterval = 30

    // MARK: - Chips

    @Test func aPlainCorrectAnswerPaysTheBaseChips() {
        let run = ScoreRun()
        #expect(run.record(correct: true, elapsed: slow) == 10)
        #expect(run.total == 10)
    }

    @Test func answeringFastPaysMore() {
        let fast = ScoreRun()
        let brisk = ScoreRun()
        let slowRun = ScoreRun()

        #expect(fast.record(correct: true, elapsed: 1) == 25)      // 10 + 15
        #expect(brisk.record(correct: true, elapsed: 5) == 15)     // 10 + 5
        #expect(slowRun.record(correct: true, elapsed: slow) == 10)
    }

    @Test func theSpeedTiersIncludeTheirOwnBoundary() {
        let onFast = ScoreRun()
        let onBrisk = ScoreRun()
        #expect(onFast.record(correct: true, elapsed: ScoreRules.fastSeconds) == 25)
        #expect(onBrisk.record(correct: true, elapsed: ScoreRules.briskSeconds) == 15)
    }

    @Test func aWrongAnswerPaysNothing() {
        let run = ScoreRun()
        #expect(run.record(correct: false, elapsed: 1) == 0)
        #expect(run.total == 0)
    }

    // MARK: - Mult

    @Test func theFirstCorrectAnswerScoresAtTheBaseMult() {
        let run = ScoreRun()
        run.record(correct: true, elapsed: slow)
        #expect(run.mult == 1)
        #expect(run.total == 10)
    }

    @Test func theMultClimbsWithEveryAnswerInARow() {
        let run = ScoreRun()
        run.record(correct: true, elapsed: slow)   // x1 -> 10
        run.record(correct: true, elapsed: slow)   // x2 -> 20
        run.record(correct: true, elapsed: slow)   // x3 -> 30
        #expect(run.mult == 3)
        #expect(run.total == 60)
    }

    @Test func aMissTakesTheWholeMult() {
        let run = ScoreRun()
        run.record(correct: true, elapsed: slow)
        run.record(correct: true, elapsed: slow)
        run.record(correct: true, elapsed: slow)   // riding x3
        run.record(correct: false, elapsed: slow)

        #expect(run.streak == 0)
        run.record(correct: true, elapsed: slow)   // back to the base rate
        #expect(run.total == 70)
    }

    @Test func remembersTheLongestStreakEvenAfterItBreaks() {
        let run = ScoreRun()
        for _ in 0..<4 { run.record(correct: true, elapsed: slow) }
        run.record(correct: false, elapsed: slow)
        run.record(correct: true, elapsed: slow)

        #expect(run.streak == 1)
        #expect(run.bestStreak == 4)
    }

    // MARK: - The daily streak

    @Test func showingUpDayAfterDayRaisesTheOpeningMult() {
        #expect(ScoreRun(dayStreak: 0).baseMult == 1)
        #expect(ScoreRun(dayStreak: 2).baseMult == 1)
        #expect(ScoreRun(dayStreak: 3).baseMult == 1.5)
        #expect(ScoreRun(dayStreak: 6).baseMult == 1.5)
        #expect(ScoreRun(dayStreak: 7).baseMult == 2)
        #expect(ScoreRun(dayStreak: 40).baseMult == 2)
    }

    @Test func aWeekLongHabitDoublesWhatTheRunPays() {
        let fresh = ScoreRun(dayStreak: 0)
        let habitual = ScoreRun(dayStreak: 7)
        fresh.record(correct: true, elapsed: slow)
        habitual.record(correct: true, elapsed: slow)

        #expect(fresh.total == 10)
        #expect(habitual.total == 20)
    }

    @Test func aMissDropsBackToTheEarnedBaseNotToNothing() {
        let run = ScoreRun(dayStreak: 7)
        run.record(correct: true, elapsed: slow)
        run.record(correct: true, elapsed: slow)
        run.record(correct: false, elapsed: slow)
        run.record(correct: true, elapsed: slow)   // x2 again, not x1

        #expect(run.total == 20 + 30 + 20)
    }

    // MARK: - Finishing

    @Test func aFlawlessRunPaysABonusThatGrowsWithIt() {
        let short = ScoreRun()
        for _ in 0..<3 { short.record(correct: true, elapsed: slow) }

        let long = ScoreRun()
        for _ in 0..<10 { long.record(correct: true, elapsed: slow) }

        #expect(short.finish() == 150)
        #expect(long.finish() == 500)
    }

    @Test func oneMissCostsTheWholePerfectBonus() {
        let run = ScoreRun()
        run.record(correct: true, elapsed: slow)
        run.record(correct: false, elapsed: slow)
        run.record(correct: true, elapsed: slow)

        #expect(run.isPerfect == false)
        #expect(run.finish() == 0)
        #expect(run.perfectBonus == 0)
    }

    @Test func theBonusIsPaidOnlyOnce() {
        let run = ScoreRun()
        run.record(correct: true, elapsed: slow)
        #expect(run.finish() == 50)
        #expect(run.finish() == 0)
        #expect(run.total == 60)
    }

    @Test func aRunWithNothingInItEarnsNoBonus() {
        let run = ScoreRun()
        #expect(run.isPerfect == false)
        #expect(run.finish() == 0)
    }

    // MARK: - What the header reads

    @Test func offersTheMultTheNextAnswerWouldScoreAt() {
        let run = ScoreRun()
        #expect(run.pendingMult == 1)
        run.record(correct: true, elapsed: slow)
        #expect(run.pendingMult == 2)
        run.record(correct: false, elapsed: slow)
        #expect(run.pendingMult == 1)
    }
}
