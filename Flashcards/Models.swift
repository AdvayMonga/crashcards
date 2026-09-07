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
    /// Where the card came from — filename and title of its `.md`. Used to group flags.
    let setID: String
    let setTitle: String

    /// The side shown first: the front, or the question.
    var prompt: String {
        switch content {
        case .flip(let front, _): return front
        case .multipleChoice(let question, _): return question
        }
    }

    /// The correct response: the back, or the correct choice.
    var answer: String {
        switch content {
        case .flip(_, let back): return back
        case .multipleChoice(_, let choices): return choices.first(where: \.isCorrect)?.text ?? ""
        }
    }
}

/// How a session presents its cards. Both modes draw from the same sets.
enum StudyMode: String, Identifiable, CaseIterable {
    case flashcards   // prompt → tap to reveal the answer
    case quiz         // multiple-choice options to pick from

    var id: String { rawValue }
    var title: String { self == .flashcards ? "Flashcards" : "Quiz" }
}

/// One `.md` file's worth of cards. `id` is the filename (unique within the folder).
struct FlashcardSet: Identifiable, Hashable {
    let id: String
    let title: String
    let cards: [Card]
}
