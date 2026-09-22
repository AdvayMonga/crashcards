import Foundation
import Testing
@testable import crashcards

/// Daily rollups: what a run adds, and how streaks read across days.
@Suite struct StatsStoreTests {
    /// A store over its own defaults suite, optionally pre-loaded with past days.
    private func store(seeded days: [DayStats] = []) -> StatsStore {
        let suite = UserDefaults(suiteName: "stats-test-\(UUID().uuidString)")!
        if !days.isEmpty, let data = try? JSONEncoder().encode(days) {
            suite.set(data, forKey: StatsStore.key)
        }
        return StatsStore(defaults: suite)
    }

    /// The day key `offset` days before today.
    private func day(_ offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
        return StatsStore.dayKey(date)
    }

    // MARK: - Recording

    @Test func foldsEveryRunIntoTheSameDay() {
        let stats = store()
        stats.record(StudyRun(answered: 4, correct: 3, seconds: 30, isComplete: true))
        stats.record(StudyRun(answered: 6, correct: 2, seconds: 45, isComplete: true))

        #expect(stats.days.count == 1)
        #expect(stats.today.answered == 10)
        #expect(stats.today.correct == 5)
        #expect(stats.today.seconds == 75)
        #expect(stats.today.sessions == 2)
    }

    @Test func ignoresARunWithNothingAnsweredInIt() {
        let stats = store()
        stats.record(StudyRun())
        #expect(stats.days.isEmpty)
        #expect(stats.totalSessions == 0)
    }

    @Test func aRunLeftEarlyCountsAsActivityButNeverAsABest() {
        let stats = store()
        stats.record(StudyRun(answered: 5, correct: 5, score: 900, isComplete: false))

        #expect(stats.totalAnswered == 5)
        #expect(stats.today.score == 900)   // still banked toward a future tier system
        #expect(stats.bestScore == 0)
    }

    @Test func aFinishedRunSetsTheBestScoreAndKeepsTheHighestOne() {
        let stats = store()
        stats.record(StudyRun(answered: 3, correct: 3, score: 400, isComplete: true))
        stats.record(StudyRun(answered: 3, correct: 3, score: 250, isComplete: true))

        #expect(stats.bestScore == 400)
        #expect(stats.today.score == 650)
    }

    @Test func keepsTheLongestAnswerStreakAcrossRuns() {
        let stats = store()
        stats.record(StudyRun(answered: 5, correct: 5, bestStreak: 5, isComplete: true))
        stats.record(StudyRun(answered: 9, correct: 4, bestStreak: 2, isComplete: true))
        #expect(stats.bestStreak == 5)
    }

    @Test func survivesAReloadThroughTheSameDefaults() {
        let suite = UserDefaults(suiteName: "stats-test-\(UUID().uuidString)")!
        let first = StatsStore(defaults: suite)
        first.record(StudyRun(answered: 7, correct: 6, score: 300, isComplete: true))

        let second = StatsStore(defaults: suite)
        #expect(second.totalAnswered == 7)
        #expect(second.bestScore == 300)
    }

    // MARK: - Accuracy

    @Test func hasNoAccuracyUntilSomethingIsAnswered() {
        #expect(store().accuracy == nil)
    }

    @Test func reportsLifetimeAccuracyAcrossEveryDay() {
        let stats = store(seeded: [DayStats(day: day(1), answered: 10, correct: 5)])
        stats.record(StudyRun(answered: 10, correct: 10, isComplete: true))
        #expect(stats.accuracy == 75)
    }

    // MARK: - Day streaks

    @Test func countsDaysStudiedBackToBack() {
        let stats = store(seeded: [
            DayStats(day: day(2), answered: 3, correct: 3),
            DayStats(day: day(1), answered: 3, correct: 3),
            DayStats(day: day(0), answered: 3, correct: 3),
        ])
        #expect(stats.dayStreak == 3)
    }

    @Test func aDayNotYetStartedDoesNotBreakTheStreak() {
        let stats = store(seeded: [
            DayStats(day: day(2), answered: 3, correct: 3),
            DayStats(day: day(1), answered: 3, correct: 3),
        ])
        #expect(stats.dayStreak == 2)
    }

    @Test func aMissedDayBreaksTheStreak() {
        let stats = store(seeded: [
            DayStats(day: day(3), answered: 3, correct: 3),
            DayStats(day: day(2), answered: 3, correct: 3),
        ])
        #expect(stats.dayStreak == 0)
    }

    @Test func remembersTheLongestRunOfDaysEver() {
        let stats = store(seeded: [
            DayStats(day: day(9), answered: 1, correct: 1),
            DayStats(day: day(8), answered: 1, correct: 1),
            DayStats(day: day(7), answered: 1, correct: 1),
            DayStats(day: day(4), answered: 1, correct: 1),
            DayStats(day: day(0), answered: 1, correct: 1),
        ])
        #expect(stats.longestDayStreak == 3)
        #expect(stats.dayStreak == 1)
    }

    // MARK: - The activity strip

    @Test func linesUpRecentDaysOldestFirstWithGapsLeftEmpty() {
        let stats = store(seeded: [
            DayStats(day: day(2), answered: 4, correct: 4),
            DayStats(day: day(0), answered: 6, correct: 2),
        ])
        let week = stats.recent(3)

        #expect(week.count == 3)
        #expect(week[0]?.answered == 4)   // two days ago
        #expect(week[1] == nil)           // nothing yesterday
        #expect(week[2]?.answered == 6)   // today
    }
}
