import Testing
import Foundation
@testable import crashcards

/// What the unlock gate is allowed to put in front of you. The gate is a tapping screen, so
/// every card becomes multiple choice — which means the wrong options have to actually be
/// wrong, and a typed card accepts more than one spelling.
@Suite struct GateQuestionTests {

    private func typed(_ question: String, _ accepted: [String]) -> Card {
        Card(content: .typed(question: question, accepted: accepted), setID: "s", setTitle: "s")
    }

    private func flip(_ front: String, _ back: String) -> Card {
        Card(content: .flip(front: front, back: back), setID: "s", setTitle: "s")
    }

    /// The bug this guards: only the printed answer used to be held out, so a second
    /// spelling the card would have accepted turned up as a wrong option.
    @Test func everySpellingACardAcceptsIsKeptOutOfTheDistractors() {
        let card = typed("French for coffee?", ["café", "coffee shop"])
        let library = [card, flip("q", "Coffee Shop"), flip("q", "Venus")]

        let wrong = UnlockView.distractors(for: card, in: library)

        #expect(wrong == ["Venus"])
    }

    /// Case, accents, punctuation and a leading article are not a different answer.
    @Test func answersThatOnlyLookDifferentAreOneAnswer() {
        let card = flip("Capital of France?", "Paris")
        let library = [card, flip("q", "paris"), flip("q", "PARIS."), flip("q", "Rome")]

        #expect(UnlockView.distractors(for: card, in: library) == ["Rome"])
    }

    @Test func distractorsAreDistinctFromEachOther() {
        let card = flip("q", "right")
        let library = [card, flip("q", "Towel"), flip("q", "a towel"), flip("q", "Rome")]

        let wrong = UnlockView.distractors(for: card, in: library)

        #expect(wrong.count == 2)
        #expect(Set(wrong.map(AnswerMatcher.normalise)).count == 2)
    }

    @Test func neverMoreThanThree() {
        let card = flip("q", "right")
        let library = [card] + (1...9).map { flip("q", "wrong \($0)") }

        #expect(UnlockView.distractors(for: card, in: library).count == 3)
    }

    /// A card with nothing to stand against it yields no distractors, and the gate is
    /// expected to move on to another card rather than ask a one-option question.
    @Test func aCardThatAcceptsEverythingHasNothingToAsk() {
        let card = typed("q", ["cat", "feline"])
        let library = [card, flip("q", "Feline")]

        #expect(UnlockView.distractors(for: card, in: library).isEmpty)
    }

    /// `answerable` counts on the same rule, so it can't promise a question that the two
    /// answers behind it would collapse into one.
    @Test func answerableCountsSpellingsAsOneAnswer() {
        #expect(UnlockView.answerable(in: [flip("q", "Paris"), flip("q", "paris")]).isEmpty)
        #expect(UnlockView.answerable(in: [flip("q", "Paris"), flip("q", "Rome")]).count == 2)
    }

    /// A multiple-choice card brings its own options, so it is always askable.
    @Test func multipleChoiceCardsNeedNothingBorrowed() {
        let card = Card(content: .multipleChoice(question: "q", choices: [
            Choice(text: "right", isCorrect: true),
            Choice(text: "wrong", isCorrect: false),
        ]), setID: "s", setTitle: "s")

        #expect(UnlockView.answerable(in: [card]).count == 1)
    }
}
