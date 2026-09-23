import Foundation

/// One option in a multiple-choice question.
struct Choice: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let isCorrect: Bool
}

/// A card is a two-sided flip card, a multiple-choice question, or a question you type
/// the answer to.
///
/// `typed` carries every spelling that counts, because one accepted answer is rarely
/// enough — "a towel" and "towel" are the same answer, and the author is the only one who
/// knows which variants are fair.
enum CardContent: Hashable {
    case flip(front: String, back: String)
    case multipleChoice(question: String, choices: [Choice])
    case typed(question: String, accepted: [String])
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
        case .typed(let question, _): return question
        }
    }

    /// The correct response: the back, or the correct choice.
    var answer: String {
        switch content {
        case .flip(_, let back): return back
        case .multipleChoice(_, let choices): return choices.first(where: \.isCorrect)?.text ?? ""
        case .typed(_, let accepted): return accepted.first ?? ""
        }
    }
}

extension Card {
    var isMultipleChoice: Bool {
        if case .multipleChoice = content { return true }
        return false
    }
    var isFlip: Bool {
        if case .flip = content { return true }
        return false
    }

    /// Every spelling that counts as right when this card is typed, or nil if it is
    /// answered by tapping instead.
    ///
    /// A flip card answers here too: quiz mode types every card that isn't multiple
    /// choice, so the back of a `::` card is simply its one accepted answer.
    var typedAnswers: [String]? {
        switch content {
        case .multipleChoice: return nil
        case .flip(_, let back): return [back]
        case .typed(_, let accepted): return accepted
        }
    }
}

/// One `.md` file's worth of cards. `id` is the filename (unique within the folder).
struct FlashcardSet: Identifiable, Hashable {
    let id: String
    let title: String
    let cards: [Card]
    /// Where the set was read from. Nil only for sets built in memory (imports, tests).
    var fileURL: URL?

    var flipCount: Int { cards.filter(\.isFlip).count }
}

/// What a study mode needs from a set, so a mode is never entered with nothing to show.
///
/// `StudyMode.unavailableReason` turns an unusable selection into a message rather than an
/// empty screen.
enum StudyMode: String, CaseIterable, Identifiable {
    case flashcards   // prompt → tap to reveal the answer
    case quiz         // graded: pick an option, or type the answer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flashcards: return "Flashcards"
        case .quiz:       return "Quiz"
        }
    }

    /// Cards this mode can actually present.
    func usableCards(in sets: [FlashcardSet]) -> [Card] {
        let cards = sets.flatMap(\.cards)
        switch self {
        case .flashcards: return cards
        // Every card can be quizzed now: the ones with options are picked from, and the
        // rest are typed.
        case .quiz:       return cards
        }
    }

    /// Why this mode can't start with these sets, or nil if it can.
    func unavailableReason(for sets: [FlashcardSet]) -> ModeUnavailable? {
        if sets.isEmpty { return .noSetsSelected }
        if sets.allSatisfy({ $0.cards.isEmpty }) { return .noCards }
        return nil
    }
}

/// A reason a study mode can't start, with the fix spelled out.
enum ModeUnavailable {
    case noSetsSelected
    case noCards

    var title: String {
        switch self {
        case .noSetsSelected: return "No sets selected"
        case .noCards:        return "These sets have no cards"
        }
    }

    var message: String {
        switch self {
        case .noSetsSelected:
            return "Pick at least one set on the Sets screen, then start again."
        case .noCards:
            return "The selected files parsed without producing any cards. Check File Problems in Settings for the reason."
        }
    }

}
