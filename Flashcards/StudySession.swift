import Foundation
import Observation

/// Classic-mode study state: the selected cards, shuffled, plus per-card results.
@Observable
final class StudySession {
    private let cards: [Card]
    private(set) var order: [Int]
    private(set) var position = 0
    var isFlipped = false
    private var results: [Int: Bool] = [:]   // cards-index → answered correctly

    init(cards: [Card]) {
        self.cards = cards
        order = Array(cards.indices).shuffled()
    }

    var total: Int { order.count }
    var isEmpty: Bool { order.isEmpty }
    var isFinished: Bool { position >= order.count }
    var current: Card? { card(at: position) }
    var progressText: String { "\(min(position + 1, total)) / \(total)" }

    /// The card on a given page. The pager renders neighbours, not just the current one.
    func card(at index: Int) -> Card? {
        guard order.indices.contains(index) else { return nil }
        return cards[order[index]]
    }

    var correctCount: Int { results.values.filter { $0 }.count }
    /// Cards not answered correctly this session (wrong or skipped), in study order.
    var missedCards: [Card] { order.filter { results[$0] != true }.map { cards[$0] } }

    func flip() { isFlipped.toggle() }

    /// Record whether the current card was answered correctly.
    func record(_ correct: Bool) {
        guard position < order.count else { return }
        results[order[position]] = correct
    }

    func next() {
        guard position < order.count else { return }
        position += 1
        isFlipped = false
    }

    /// Scroll to a page. The last page, one past the cards, is the summary.
    func go(to index: Int) {
        guard index >= 0, index <= order.count, index != position else { return }
        position = index
        isFlipped = false
    }

    func restart() {
        order = Array(cards.indices).shuffled()
        position = 0
        isFlipped = false
        results.removeAll()
    }
}
