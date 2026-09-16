import Testing
@testable import Flashcards

/// Spreadsheet exports. Every case here is one that shipped broken at some point.
@Suite struct DelimitedParserTests {
    private func cards(_ text: String, _ file: String = "x.csv") -> [Card] {
        DelimitedParser.parse(text, filename: file).set.cards
    }

    @Test func twoColumnsMakeAFlipCard() {
        let parsed = cards("Mitochondrion,Powerhouse")
        #expect(parsed.count == 1)
        #expect(parsed.first?.prompt == "Mitochondrion")
        #expect(parsed.first?.answer == "Powerhouse")
    }

    @Test func extraColumnsBecomeDistractors() {
        let parsed = cards("Capital of France?,Paris,Lyon,Marseille")
        #expect(parsed.count == 1)
        #expect(parsed.first?.isMultipleChoice == true)
        #expect(parsed.first?.answer == "Paris")
        if case .multipleChoice(_, let choices) = parsed.first?.content {
            #expect(choices.count == 3)
        }
    }

    @Test func tabsSplitATSV() {
        #expect(cards("Osmosis\tWater across a membrane", "x.tsv").count == 1)
    }

    /// A blank cell must hold its place, or a leading index column shifts every card along.
    @Test func aBlankFirstColumnIsSkippedNotShifted() {
        let parsed = DelimitedParser.parse(",Paris,France\nBerlin,Germany", filename: "x.csv")
        #expect(parsed.set.cards.count == 1)
        #expect(parsed.set.cards.first?.prompt == "Berlin")
        #expect(parsed.issues.contains { $0.kind == .shortRow })
    }

    /// Sheets pads rows to the widest one; trailing blanks aren't distractors.
    @Test func trailingBlankColumnsDoNotMakeAQuestion() {
        let parsed = cards("Dog,Perro,,")
        #expect(parsed.first?.isMultipleChoice == false)
    }

    @Test func quotedFieldsSurviveSeparatorsNewlinesAndDoubledQuotes() {
        #expect(cards("\"a,b\",second").first?.prompt == "a,b")
        #expect(cards("\"multi\nline\",second").first?.prompt == "multi\nline")
        #expect(cards("\"say \"\"hi\"\"\",second").first?.prompt == "say \"hi\"")
    }

    /// Excel writes `a, "b,c"`; the space must not defeat the quote.
    @Test func aSpaceBeforeAQuoteIsStillAQuotedField() {
        let parsed = cards("a, \"b,c\"")
        #expect(parsed.count == 1)
        #expect(parsed.first?.answer == "b,c")
    }

    @Test(arguments: ["Term,Definition\nDog,Perro", "\nTerm,Definition\nDog,Perro"])
    func headerRowsAreSkippedWhereverTheyStart(text: String) {
        let parsed = cards(text)
        #expect(parsed.count == 1)
        #expect(parsed.first?.prompt == "Dog")
    }

    @Test func aRowWithOneColumnIsReported() {
        let parsed = DelimitedParser.parse("Lonely", filename: "x.csv")
        #expect(parsed.set.cards.isEmpty)
        #expect(parsed.issues.contains { $0.kind == .shortRow })
    }

    @Test func aTrailingNewlineIsNotAPhantomRow() {
        #expect(cards("Dog,Perro\n").count == 1)
    }
}
