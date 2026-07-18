import Foundation

/// One option in a multiple-choice question.
struct Choice: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let isCorrect: Bool
}

/// A card is either a two-sided flip card or a multiple-choice question.
enum CardContent: Hashable {
    case flip(front: String, back: String)
    case multipleChoice(question: String, choices: [Choice])
}

struct Card: Identifiable, Hashable {
    let id = UUID()
    let content: CardContent
}

/// One `.md` file's worth of cards. `id` is the filename (unique within the folder).
struct FlashcardSet: Identifiable, Hashable {
    let id: String
    let title: String
    let cards: [Card]
}
