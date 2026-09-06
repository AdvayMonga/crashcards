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
    var current: Card? { isFinished ? nil : cards[order[position]] }
    var progressText: String { "\(min(position + 1, total)) / \(total)" }

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

    func prev() {
        guard position > 0 else { return }
        position -= 1
        isFlipped = false
    }

    func restart() {
        order = Array(cards.indices).shuffled()
        position = 0
        isFlipped = false
        results.removeAll()
    }
}
