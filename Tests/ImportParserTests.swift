import Testing
@testable import Flashcards

/// Pasted text, in whatever shape it arrived.
@Suite struct ImportParserTests {
    @Test(arguments: [
        ("Mitochondrion\tPowerhouse", ImportParser.Layout.tab),
        ("Mitochondrion,Powerhouse", ImportParser.Layout.comma),
        ("Mitochondrion;Powerhouse", ImportParser.Layout.semicolon),
        ("Mitochondrion - Powerhouse", ImportParser.Layout.dash),
        ("Q: What is it?\nA: A thing", ImportParser.Layout.questionAnswer),
        ("Mitochondrion: Powerhouse", ImportParser.Layout.colon),
        ("Mitochondrion :: Powerhouse", ImportParser.Layout.markdown),
    ])
    func detectsTheLayoutItWasGiven(text: String, expected: ImportParser.Layout) {
        #expect(ImportParser.detect(text) == expected)
    }

    @Test func ourOwnSyntaxIsRecognisedEvenWhenItAlsoContainsCommas() {
        let text = "Paris, France :: The capital\nBerlin, Germany :: Also a capital"
        #expect(ImportParser.detect(text) == .markdown)
        #expect(ImportParser.parse(text, title: "t").cards.count == 2)
    }

    /// Before labels won over counting, the colon layout split each line into its own card
    /// — "Q :: What is it?" and "A :: A thing" — and two junk cards beat one real one.
    @Test func labelledPairsBecomeOneCardEach() {
        let result = ImportParser.parse("Q: What is it?\nA: A thing\nQ: Second?\nA: Yes", title: "t")
        #expect(result.layout == .questionAnswer)
        #expect(result.cards.count == 2)
        #expect(result.cards.first?.prompt == "What is it?")
        #expect(result.cards.first?.answer == "A thing")
    }

    @Test func anAnswerWithNoQuestionAboveItIsIgnored() {
        let result = ImportParser.parse("A: orphan\nQ: Real?\nA: Yes", as: .questionAnswer, title: "t")
        #expect(result.cards.count == 1)
        #expect(result.cards.first?.prompt == "Real?")
    }

    @Test func aQuizletExportBecomesCards() {
        let result = ImportParser.parse("Mitochondrion\tPowerhouse\nOsmosis\tWater", title: "Bio")
        #expect(result.layout == .tab)
        #expect(result.cards.count == 2)
        #expect(result.skipped == 0)
    }

    @Test func linesThatMakeNoCardAreCountedNotDropped() {
        let result = ImportParser.parse("a\tb\nnot a card line", as: .tab, title: "t")
        #expect(result.cards.count == 1)
        #expect(result.skipped == 1)
    }

    @Test func threeColumnsBecomeAQuestion() {
        let result = ImportParser.parse("Capital?\tParis\tLyon", as: .tab, title: "t")
        #expect(result.cards.first?.isMultipleChoice == true)
        #expect(result.cards.first?.answer == "Paris")
    }

    @Test func emptyTextMakesNoCards() {
        #expect(ImportParser.parse("   \n\n", as: .tab, title: "t").cards.isEmpty)
    }

    /// What we write must be what we read: an import is indistinguishable from a hand-written set.
    @Test func savedMarkdownParsesBackToTheSameCards() {
        let original = ImportParser.parse(
            "Mitochondrion\tPowerhouse\nCapital?\tParis\tLyon\tNice",
            as: .tab, title: "Bio"
        )
        let markdown = ImportParser.markdown(title: "Bio", cards: original.cards)
        let reparsed = MarkdownParser.parse(markdown, filename: "Bio.md")

        #expect(reparsed.set.title == "Bio")
        #expect(reparsed.issues.isEmpty)
        #expect(reparsed.set.cards.map(\.prompt) == original.cards.map(\.prompt))
        #expect(reparsed.set.cards.map(\.answer) == original.cards.map(\.answer))
    }
}
