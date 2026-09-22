import Testing
@testable import crashcards

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
        #expect(session.current != nil)
    }

    @Test func runsOutAfterTheLastCard() {
        let session = StudySession(cards: deck(2))
        session.next()
        session.next()
        #expect(session.isFinished)
        #expect(session.current == nil)
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

    // MARK: - Handing the run to the stats store

    @Test func hasNothingToRecordBeforeAnythingIsAnswered() {
        let session = StudySession(cards: deck(3))
        #expect(session.consumeRun() == nil)
    }

    @Test func recordsTheRunOnlyOnce() {
        let session = StudySession(cards: deck(2))
        session.record(true)
        session.next()

        let run = session.consumeRun()
        #expect(run?.answered == 1)
        #expect(session.consumeRun() == nil)
    }

    @Test func aRunLeftPartWayThroughIsNotComplete() {
        let session = StudySession(cards: deck(3))
        session.record(true)
        session.next()

        let run = session.consumeRun()
        #expect(run?.isComplete == false)
        #expect(run?.correct == 1)
    }

    @Test func aRunPlayedToTheEndIsComplete() {
        let session = StudySession(cards: deck(2))
        session.record(true)
        session.next()
        session.record(false)
        session.next()

        let run = session.consumeRun()
        #expect(run?.isComplete == true)
        #expect(run?.answered == 2)
        #expect(run?.correct == 1)
    }

    @Test func startingOverMakesAFreshRunToRecord() {
        let session = StudySession(cards: deck(2))
        session.record(true)
        session.next()
        _ = session.consumeRun()

        session.restart()
        session.record(true)
        #expect(session.consumeRun()?.answered == 1)
    }
}
