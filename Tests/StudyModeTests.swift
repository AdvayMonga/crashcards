import Testing
@testable import crashcards

/// A mode is never entered with nothing it can show.
@Suite struct StudyModeTests {
    private let flip = Card(content: .flip(front: "f", back: "b"), setID: "s.md", setTitle: "S")
    private var question: Card {
        Card(content: .multipleChoice(question: "q", choices: [
            Choice(text: "right", isCorrect: true),
            Choice(text: "wrong", isCorrect: false),
        ]), setID: "s.md", setTitle: "S")
    }
    private func set(_ cards: [Card]) -> FlashcardSet {
        FlashcardSet(id: "s.md", title: "S", cards: cards)
    }

    /// Both modes take every card now: quiz picks from the ones with options and types
    /// the rest, so a deck of pure flip cards is quizzable rather than turned away.
    @Test func bothModesUseEveryCard() {
        let mixed = [set([flip, question])]
        #expect(StudyMode.quiz.usableCards(in: mixed).count == 2)
        #expect(StudyMode.flashcards.usableCards(in: mixed).count == 2)
    }

    @Test func aDeckOfOnlyFlipCardsCanStillBeQuizzed() {
        #expect(StudyMode.quiz.unavailableReason(for: [set([flip])]) == nil)
        #expect(StudyMode.flashcards.unavailableReason(for: [set([flip])]) == nil)
    }

    @Test(arguments: StudyMode.allCases)
    func noSetsAndNoCardsAreExplainedForEveryMode(mode: StudyMode) {
        #expect(mode.unavailableReason(for: []) == .noSetsSelected)
        #expect(mode.unavailableReason(for: [set([])]) == .noCards)
    }

    @Test func aSetWithQuestionsStartsInAnyMode() {
        let usable = [set([flip, question])]
        for mode in StudyMode.allCases {
            #expect(mode.unavailableReason(for: usable) == nil, "\(mode.title) should start")
        }
    }
}
