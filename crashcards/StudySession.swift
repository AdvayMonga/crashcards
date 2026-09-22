import Foundation
import Observation

/// Quiz state: the selected cards, shuffled, plus which were answered correctly.
/// Flashcards mode keeps no state of its own — it doesn't grade.
@Observable
final class StudySession {
    private let cards: [Card]
    private(set) var order: [Int]
    private(set) var position = 0
    private var results: [Int: Bool] = [:]   // cards-index → answered correctly
    private var startedAt = Date()
    /// Whether this run's activity has already gone to the stats store.
    private var recorded = false

    /// How many days in a row you've studied, held so starting over — or practising the
    /// ones you missed — opens on the same mult this run did.
    let dayStreak: Int
    private(set) var score: ScoreRun

    init(cards: [Card], dayStreak: Int = 0) {
        self.cards = cards
        self.dayStreak = dayStreak
        score = ScoreRun(dayStreak: dayStreak)
        order = Array(cards.indices).shuffled()
    }

    var total: Int { order.count }
    var isEmpty: Bool { order.isEmpty }
    var isFinished: Bool { position >= order.count }
    var current: Card? {
        guard order.indices.contains(position) else { return nil }
        return cards[order[position]]
    }

    var answeredCount: Int { results.count }
    var correctCount: Int { results.values.filter { $0 }.count }
    /// Cards not answered correctly this session (wrong or skipped), in study order.
    var missedCards: [Card] { order.filter { results[$0] != true }.map { cards[$0] } }

    /// Record whether the current card was answered correctly, and what it scored.
    ///
    /// `elapsed` defaults to never — a caller that isn't timing the question simply doesn't
    /// earn the speed chips.
    func record(_ correct: Bool, elapsed: TimeInterval = .infinity) {
        guard position < order.count else { return }
        results[order[position]] = correct
        score.record(correct: correct, elapsed: elapsed)
    }

    func next() {
        guard position < order.count else { return }
        position += 1
    }

    func restart() {
        order = Array(cards.indices).shuffled()
        position = 0
        results.removeAll()
        startedAt = Date()
        recorded = false
        score = ScoreRun(dayStreak: dayStreak)
    }

    /// This run's activity, handed over once — a second call returns nil, so finishing and
    /// then closing can't count the same questions twice.
    ///
    /// A run left part-way through is still activity; `isComplete` is what keeps it out of
    /// the personal bests.
    func consumeRun() -> StudyRun? {
        guard !recorded, !results.isEmpty else { return nil }
        recorded = true
        return StudyRun(answered: answeredCount,
                        correct: correctCount,
                        seconds: StatsStore.studySeconds(since: startedAt, answered: answeredCount),
                        bestStreak: score.bestStreak,
                        score: score.total,
                        isComplete: isFinished)
    }
}
