import Testing
@testable import Flashcards

/// Deck navigation and scoring.
@Suite struct StudySessionTests {
    private func deck(_ count: Int) -> [Card] {
        (1...count).map {
            Card(content: .flip(front: "front \($0)", back: "back \($0)"),
                 setID: "s.md", setTitle: "Set")
        }
    }

    @Test func startsOnTheFirstCardOfTheWholeDeck() {
        let session = StudySession(cards: deck(3))
        #expect(session.total == 3)
        #expect(session.position == 0)
        #expect(session.isFinished == false)
        #expect(session.progressText == "1 / 3")
    }

    @Test func runsOutAfterTheLastCard() {
        let session = StudySession(cards: deck(2))
        session.next()
        session.next()
        #expect(session.isFinished)
        #expect(session.current == nil)
    }

    @Test func scrollingToAPageMovesThereAndHidesTheAnswer() {
        let session = StudySession(cards: deck(4))
        session.isFlipped = true
        session.go(to: 2)
        #expect(session.position == 2)
        #expect(session.isFlipped == false)
    }

    /// The page past the last card is the summary, so it's a valid destination.
    @Test func scrollingStopsAtTheSummaryAndAtZero() {
        let session = StudySession(cards: deck(3))
        session.go(to: 3)
        #expect(session.position == 3)
        session.go(to: 99)
        #expect(session.position == 3)
        session.go(to: -1)
        #expect(session.position == 3)
        session.go(to: 0)
        #expect(session.position == 0)
    }

    @Test func everyPageHasItsCardAndNothingBeyond() {
        let session = StudySession(cards: deck(3))
        #expect(session.card(at: 0) != nil)
        #expect(session.card(at: 2) != nil)
        #expect(session.card(at: 3) == nil)
        #expect(session.card(at: -1) == nil)
    }

    @Test func scoresWhatYouAnsweredAndCountsTheRestAsMissed() {
        let session = StudySession(cards: deck(3))
        session.record(true)
        session.next()
        session.record(false)
        session.next()
        // third card left unanswered
        #expect(session.correctCount == 1)
        #expect(session.missedCards.count == 2)
    }

    @Test func restartClearsTheScoreAndReturnsToTheStart() {
        let session = StudySession(cards: deck(3))
        session.record(true)
        session.next()
        session.restart()
        #expect(session.position == 0)
        #expect(session.correctCount == 0)
        #expect(session.missedCards.count == 3)
    }

    @Test func anEmptyDeckIsImmediatelyFinished() {
        let session = StudySession(cards: [])
        #expect(session.isEmpty)
        #expect(session.isFinished)
        #expect(session.current == nil)
    }
}
