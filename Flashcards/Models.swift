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

extension Card {
    var isMultipleChoice: Bool {
        if case .multipleChoice = content { return true }
        return false
    }
    var isFlip: Bool { !isMultipleChoice }
}

/// One `.md` file's worth of cards. `id` is the filename (unique within the folder).
struct FlashcardSet: Identifiable, Hashable {
    let id: String
    let title: String
    let cards: [Card]

    var multipleChoiceCount: Int { cards.filter(\.isMultipleChoice).count }
    var flipCount: Int { cards.filter(\.isFlip).count }
}

/// What a study mode needs from a set, so a mode is never entered with nothing to show.
///
/// Quiz-style modes need multiple-choice questions; a set of pure `::` flip cards can't
/// supply them. `StudyMode.unavailableReason` turns that into a message, not an empty screen.
enum StudyMode: String, CaseIterable, Identifiable {
    case classic
    case voice
    case quiz

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .voice:   return "Voice"
        case .quiz:    return "Quiz"
        }
    }

    /// Cards this mode can actually present.
    func usableCards(in sets: [FlashcardSet]) -> [Card] {
        let cards = sets.flatMap(\.cards)
        switch self {
        case .classic, .voice: return cards
        case .quiz:            return cards.filter(\.isMultipleChoice)
        }
    }

    /// Why this mode can't start with these sets, or nil if it can.
    func unavailableReason(for sets: [FlashcardSet]) -> ModeUnavailable? {
        if sets.isEmpty { return .noSetsSelected }
        if sets.allSatisfy({ $0.cards.isEmpty }) { return .noCards }
        if usableCards(in: sets).isEmpty, self == .quiz { return .noQuestions }
        return nil
    }
}

/// A reason a study mode can't start, with the fix spelled out.
enum ModeUnavailable {
    case noSetsSelected
    case noCards
    case noQuestions

    var title: String {
        switch self {
        case .noSetsSelected: return "No sets selected"
        case .noCards:        return "These sets have no cards"
        case .noQuestions:    return "No quiz questions here"
        }
    }

    var symbol: String {
        switch self {
        case .noSetsSelected: return "square.dashed"
        case .noCards:        return "tray"
        case .noQuestions:    return "checklist.unchecked"
        }
    }

    var message: String {
        switch self {
        case .noSetsSelected:
            return "Pick at least one set on the Sets screen, then start again."
        case .noCards:
            return "The selected files parsed without producing any cards. Check File Problems in Settings for the reason."
        case .noQuestions:
            return "Quiz mode needs multiple-choice questions, and the selected sets only have flip cards. Add a question to one of your .md files in this format, then reopen the app:"
        }
    }

    /// The format to write, shown only when that's the actual fix.
    var expected: String? {
        switch self {
        case .noQuestions: return MarkdownParser.questionExample
        case .noSetsSelected, .noCards: return nil
        }
    }
}
