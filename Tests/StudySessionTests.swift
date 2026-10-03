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

    @Test func carriesTheScoreAndStreakIntoWhatItRecords() {
        let session = StudySession(cards: deck(3))
        session.record(true, elapsed: 30)
        session.next()
        session.record(true, elapsed: 30)
        session.next()
        session.record(false, elapsed: 30)
        session.next()

        let run = session.consumeRun()
        #expect(run?.score == 30)        // 10 at x1, 20 at x2, nothing for the miss
        #expect(run?.bestStreak == 2)
    }

    @Test func startingOverWipesTheScore() {
        let session = StudySession(cards: deck(2))
        session.record(true, elapsed: 30)
        session.restart()

        #expect(session.score.total == 0)
        #expect(session.score.streak == 0)
    }

    @Test func aRunKeepsTheOpeningMultItWasStartedWith() {
        let session = StudySession(cards: deck(2), dayStreak: 7)
        session.restart()
        #expect(session.score.baseMult == 2)
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

    // MARK: - Running short

    /// The whole point: a deck too big for the time you have is cut down to the number you
    /// asked for, and the run genuinely ends there.
    @Test func asksOnlyAsManyQuestionsAsYouAskedFor() {
        let session = StudySession(cards: deck(50), limit: 10)
        #expect(session.total == 10)
        for _ in 0..<10 { session.record(true); session.next() }
        #expect(session.isFinished)
    }

    @Test func aLimitBiggerThanTheDeckIsJustTheDeck() {
        #expect(StudySession(cards: deck(4), limit: 10).total == 4)
        #expect(StudySession(cards: deck(4), limit: 4).total == 4)
    }

    @Test func noLimitAsksEverything() {
        #expect(StudySession(cards: deck(37), limit: nil).total == 37)
        #expect(StudySession(cards: deck(37)).total == 37)
    }

    /// Starting over must stay short. Re-dealing from the full deck would quietly turn a
    /// ten-question run into a fifty-question one on the second go.
    @Test func startingOverStaysShort() {
        let session = StudySession(cards: deck(50), limit: 10)
        session.record(true)
        session.next()
        session.restart()
        #expect(session.total == 10)
        #expect(session.position == 0)
        #expect(session.answeredCount == 0)
    }

    /// A short run is a sample of the deck, not its first ten cards — otherwise every run
    /// of a big set drills the same corner of it.
    @Test func shortRunsAreDrawnFromTheWholeDeck() {
        let cards = deck(60)
        var seen = Set<String>()
        for _ in 0..<12 {
            let session = StudySession(cards: cards, limit: 5)
            while let card = session.current { seen.insert(card.prompt); session.next() }
        }
        // Twelve draws of five from sixty hitting ten or fewer distinct cards would mean
        // the cut isn't random. The real number is near sixty.
        #expect(seen.count > 10)
    }

    /// What you missed has to come from the questions you were actually asked.
    @Test func missedCardsStayInsideTheShortRun() {
        let session = StudySession(cards: deck(40), limit: 6)
        for _ in 0..<6 { session.record(false); session.next() }
        #expect(session.missedCards.count == 6)
    }
}
