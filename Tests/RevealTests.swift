import Testing
@testable import crashcards

/// Giving up on a question. Reveal shows the answer and moves on, and the point of these is
/// that it is never the cheap way through: it scores exactly as badly as getting it wrong,
/// so a run you revealed your way to can't read as a run you knew.
struct RevealTests {

    private func deck(_ count: Int) -> [Card] {
        (0..<count).map {
            Card(content: .flip(front: "q\($0)", back: "a\($0)"), setID: "s.md", setTitle: "Set")
        }
    }

    /// What `reveal()` does to the session, without the view: record it as not known.
    private func revealCurrent(_ session: StudySession) {
        session.record(false, elapsed: .infinity)
    }

    @Test func aRevealedCardPaysNothing() {
        let session = StudySession(cards: deck(2))
        revealCurrent(session)
        #expect(session.score.total == 0)
        #expect(session.score.lastGain == 0)
    }

    @Test func aRevealedCardBreaksTheStreak() {
        let session = StudySession(cards: deck(3))
        session.record(true, elapsed: 1)
        session.next()
        session.record(true, elapsed: 1)
        let earned = session.score.total
        session.next()

        revealCurrent(session)
        #expect(session.score.streak == 0)
        #expect(session.score.total == earned)   // nothing added, nothing taken away
    }

    @Test func aRevealedCardCountsAsMissedSoItComesBackInTheReviewRound() {
        let session = StudySession(cards: deck(2))
        // The deck is shuffled on entry, so the card revealed is whichever came up first.
        let given = session.current?.prompt
        revealCurrent(session)
        session.next()
        session.record(true, elapsed: 1)

        #expect(session.missedCards.count == 1)
        #expect(session.missedCards.first?.prompt == given)
    }

    /// Revealing every card is still a finished run, and still worth nothing.
    @Test func aRunRevealedAllTheWayThroughEarnsNoPerfectBonus() {
        let session = StudySession(cards: deck(3))
        for _ in 0..<3 {
            revealCurrent(session)
            session.next()
        }
        session.score.finish()

        #expect(session.isFinished)
        #expect(session.score.perfectBonus == 0)
        #expect(session.score.total == 0)
        #expect(session.correctCount == 0)
    }

    /// It counts as activity: you saw the question, and lifetime accuracy should say you
    /// didn't know it rather than quietly skipping the card.
    @Test func aRevealedCardIsStillAnAnsweredQuestion() {
        let session = StudySession(cards: deck(2))
        revealCurrent(session)
        session.next()
        revealCurrent(session)
        session.next()

        let run = session.consumeRun()
        #expect(run?.answered == 2)
        #expect(run?.correct == 0)
    }
}
