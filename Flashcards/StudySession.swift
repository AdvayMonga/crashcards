import Foundation
import Observation

/// Classic-mode study state: the selected sets' cards, shuffled into one deck.
@Observable
final class StudySession {
    private let cards: [Card]
    private(set) var order: [Int]
    private(set) var position = 0
    var isFlipped = false

    init(sets: [FlashcardSet]) {
        cards = sets.flatMap(\.cards)
        order = Array(cards.indices).shuffled()
    }

    var total: Int { order.count }
    var isEmpty: Bool { order.isEmpty }
    var isFinished: Bool { position >= order.count }
    var current: Card? { isFinished ? nil : cards[order[position]] }
    var progressText: String { "\(min(position + 1, total)) / \(total)" }

    func flip() { isFlipped.toggle() }

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
    }
}
