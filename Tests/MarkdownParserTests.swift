import Testing
@testable import crashcards

/// The `.md` card syntax, and the complaints it makes about files that nearly parse.
@Suite struct MarkdownParserTests {
    @Test func readsFlipCardsAndTakesTitleFromHeading() {
        let parsed = MarkdownParser.parse(
            """
            # Biology

            Mitochondrion :: Powerhouse of the cell
            Osmosis :: Water across a membrane
            """,
            filename: "bio.md"
        )
        #expect(parsed.set.title == "Biology")
        #expect(parsed.set.cards.count == 2)
        #expect(parsed.set.cards.first?.prompt == "Mitochondrion")
        #expect(parsed.set.cards.first?.answer == "Powerhouse of the cell")
        #expect(parsed.issues.isEmpty)
    }

    @Test func titleFallsBackToFilenameWithoutItsExtension() {
        for name in ["Spanish.md", "Spanish.txt", "Spanish.markdown", "Spanish.text"] {
            let parsed = MarkdownParser.parse("Hola :: Hello", filename: name)
            #expect(parsed.set.title == "Spanish", "title from \(name)")
        }
    }

    @Test func readsAQuestionWithItsOptions() {
        let parsed = MarkdownParser.parse(
            """
            What carries oxygen in blood?
            - [ ] Plasma
            - [x] Hemoglobin
            - [ ] Platelets
            """,
            filename: "bio.md"
        )
        #expect(parsed.set.cards.count == 1)
        #expect(parsed.set.cards.first?.answer == "Hemoglobin")
        #expect(parsed.set.cards.first?.isMultipleChoice == true)
        #expect(parsed.issues.isEmpty)
    }

    /// Each of these nearly parses, and each must say so rather than vanishing.
    @Test(arguments: [
        ("A question?\n- [x] Only one", ParseIssue.Kind.tooFewOptions),
        ("A question?\n- [ ] One\n- [ ] Two", ParseIssue.Kind.noCorrectOption),
        ("A question?\n- [x] One\n- [x] Two", ParseIssue.Kind.multipleCorrectOptions),
        ("A question?\n\n- [ ] One\n- [x] Two", ParseIssue.Kind.blankLineBeforeOptions),
        ("- [ ] One\n- [x] Two", ParseIssue.Kind.orphanOptions),
        (" :: no front", ParseIssue.Kind.emptyFront),
        ("no back ::", ParseIssue.Kind.emptyBack),
    ])
    func reportsNearMisses(text: String, expected: ParseIssue.Kind) {
        let parsed = MarkdownParser.parse(text, filename: "x.md")
        #expect(parsed.issues.contains { $0.kind == expected })
    }

    /// The warning promises that any marked option counts, and grading reads `isCorrect`
    /// on whichever option was tapped — so both must stay flagged. Asserting the revealed
    /// answer instead would pass even if the parser demoted the second `[x]`.
    @Test func everyOptionMarkedCorrectStaysCorrect() {
        let parsed = MarkdownParser.parse(
            "Pick one\n- [x] First\n- [x] Second\n- [ ] Third",
            filename: "x.md"
        )
        guard case .multipleChoice(_, let choices) = parsed.set.cards.first?.content else {
            Issue.record("expected a multiple-choice card")
            return
        }
        #expect(choices.filter(\.isCorrect).count == 2)
        #expect(choices.count == 3)
    }

    @Test func ignoresFrontmatterAndCodeFences() {
        let parsed = MarkdownParser.parse(
            """
            ---
            tags: :: not a card
            ---

            ```cpp
            std::cout << x;
            ```

            Real :: Card
            """,
            filename: "x.md"
        )
        #expect(parsed.set.cards.count == 1)
        #expect(parsed.set.cards.first?.prompt == "Real")
    }

    /// Prose is not a failed card — a notes file shouldn't nag.
    @Test func quietAboutAFileWithNoCardsAndNoNearMisses() {
        let parsed = MarkdownParser.parse("Just some notes.\nNothing card-shaped here.", filename: "x.md")
        #expect(parsed.set.cards.isEmpty)
        #expect(parsed.issues.isEmpty)
    }

    @Test func flagsAFileThatOnlyAlmostHasCards() {
        let parsed = MarkdownParser.parse("no back ::", filename: "x.md")
        #expect(parsed.issues.first?.kind == .noCards)
    }
}
