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

    init(cards: [Card]) {
        self.cards = cards
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

    /// Record whether the current card was answered correctly.
    func record(_ correct: Bool) {
        guard position < order.count else { return }
        results[order[position]] = correct
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
                        isComplete: isFinished)
    }
}
