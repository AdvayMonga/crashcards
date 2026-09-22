import Testing
@testable import crashcards

struct TypedCardTests {
    private func parse(_ body: String) -> ParsedFile {
        MarkdownParser.parse("# T\n\n" + body, filename: "T.md")
    }

    /// The whole point of the format change: a riddle needs no invented distractors.
    @Test func optionsWithNothingToRuleOutBecomeATypedCard() throws {
        let parsed = parse("""
        What gets wetter the more it dries?
        - [x] a towel
        - [x] towel
        """)
        #expect(parsed.issues.isEmpty)
        let card = try #require(parsed.set.cards.first)
        #expect(card.typedAnswers == ["a towel", "towel"])
        #expect(!card.isMultipleChoice)
    }

    @Test func aSingleCheckedOptionIsTypedNotMalformed() throws {
        let parsed = parse("Which planet spins backwards?\n- [x] Venus")
        #expect(parsed.issues.isEmpty)
        #expect(try #require(parsed.set.cards.first).typedAnswers == ["Venus"])
    }

    @Test func optionsWithSomethingToRuleOutStayMultipleChoice() throws {
        let parsed = parse("""
        Which planet spins backwards?
        - [x] Venus
        - [ ] Mars
        """)
        #expect(parsed.issues.isEmpty)
        #expect(try #require(parsed.set.cards.first).isMultipleChoice)
    }

    /// Still flagged: with some options ruled out, two right answers can't be told apart.
    /// The card survives — any marked option counts — but the file gets a complaint.
    @Test func twoCorrectAmongWrongOnesIsStillFlagged() throws {
        let parsed = parse("""
        Which are planets?
        - [x] Venus
        - [x] Mars
        - [ ] Ceres
        """)
        #expect(parsed.issues.contains { $0.kind == .multipleCorrectOptions })
        #expect(try #require(parsed.set.cards.first).isMultipleChoice)
    }

    @Test func aQuestionWithNoCorrectOptionIsStillSkipped() {
        let parsed = parse("Which planet?\n- [ ] Venus\n- [ ] Mars")
        #expect(parsed.issues.contains { $0.kind == .noCorrectOption })
        #expect(parsed.set.cards.isEmpty)
    }

    /// Flip cards are typed in quiz mode, so the back is their one accepted answer.
    @Test func flipCardsAnswerTypedToo() {
        let card = Card(content: .flip(front: "Capital of France", back: "Paris"),
                        setID: "s", setTitle: "S")
        #expect(card.typedAnswers == ["Paris"])
    }

    @Test func typedCardsSurviveARoundTripThroughMarkdown() throws {
        let original = parse("Riddle?\n- [x] one\n- [x] two").set.cards
        let rewritten = MarkdownParser.parse(
            ImportParser.markdown(title: "T", cards: original), filename: "T.md")
        #expect(try #require(rewritten.set.cards.first).typedAnswers == ["one", "two"])
    }
}

struct AnswerMatcherTests {
    @Test(arguments: ["a towel", "towel", "A Towel", "  towel  ", "Towel.", "the towel"])
    func forgivesCasePunctuationAndArticles(attempt: String) {
        #expect(AnswerMatcher.matches(attempt, anyOf: ["a towel"]))
    }

    @Test func acceptsAnyOfTheListedSpellings() {
        let accepted = ["an hourglass", "egg timer", "sand timer"]
        #expect(AnswerMatcher.matches("Egg Timer", anyOf: accepted))
        #expect(AnswerMatcher.matches("hourglass", anyOf: accepted))
    }

    /// It must not guess: a near miss is a miss, or the grade means nothing.
    @Test(arguments: ["tow", "towels", "a wet towel", "cloth", ""])
    func refusesWhatIsNotTheAnswer(attempt: String) {
        #expect(!AnswerMatcher.matches(attempt, anyOf: ["a towel"]))
    }

    /// "a" is an answer in its own right, so the article strip must not empty it.
    @Test func keepsASingleWordThatIsAlsoAnArticle() {
        #expect(AnswerMatcher.matches("A", anyOf: ["a"]))
    }
}
