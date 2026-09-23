import Testing
@testable import crashcards

/// Which cards the unlock gate can actually build a question from. The Focus tab offers the
/// gate on this same answer, so a disagreement here is a live button that lands on an empty
/// screen — the state you reach by deleting your last set while apps are blocked.
struct UnlockGateTests {

    private func flip(_ front: String, _ back: String) -> Card {
        Card(content: .flip(front: front, back: back), setID: "s.md", setTitle: "Set")
    }

    private func question(_ prompt: String) -> Card {
        Card(content: .multipleChoice(question: prompt, choices: [
            Choice(text: "right", isCorrect: true),
            Choice(text: "wrong", isCorrect: false),
        ]), setID: "s.md", setTitle: "Set")
    }

    @Test func anEmptyLibraryHasNothingToAsk() {
        #expect(UnlockView.answerable(in: []).isEmpty)
    }

    /// A multiple-choice card carries its own distractors, so one is enough.
    @Test func oneQuestionIsEnoughOnItsOwn() {
        #expect(UnlockView.answerable(in: [question("only")]).count == 1)
    }

    /// A flip card is quizzed by borrowing another card's answer as a wrong option, so a
    /// lone flip card can't be asked — there's nothing to offer beside the right answer.
    @Test func aLoneFlipCardCannotBeAsked() {
        #expect(UnlockView.answerable(in: [flip("front", "back")]).isEmpty)
    }

    @Test func twoFlipCardsWithDifferentAnswersCanBothBeAsked() {
        let cards = [flip("a", "apple"), flip("b", "banana")]
        #expect(UnlockView.answerable(in: cards).count == 2)
    }

    /// The case that reads as a full library and asks nothing: plenty of cards, one answer
    /// between them, so no card has a distractor to borrow.
    @Test func flipCardsSharingOneAnswerCannotBeAsked() {
        let cards = [flip("a", "same"), flip("b", "same"), flip("c", "same")]
        #expect(UnlockView.answerable(in: cards).isEmpty)
    }

    /// Distractors are borrowed from every card's answer, a question's included — so adding
    /// one question to flip cards that all share an answer makes the whole deck askable,
    /// not just the question.
    @Test func aQuestionsAnswerIsBorrowableByFlipCardsToo() {
        let cards = [flip("a", "same"), flip("b", "same"), question("real")]
        #expect(UnlockView.answerable(in: cards).count == 3)
    }
}
