import Testing
@testable import crashcards

/// Options too long to be read on the answer button. The quiz shrinks text to fit two lines
/// and truncates past that, so the fix belongs in the deck — these check the file is told
/// about it rather than the answer being quietly cut.
struct LongOptionTests {

    private func option(_ length: Int) -> String {
        String(repeating: "a", count: length)
    }

    private func deck(correct: String, wrong: String) -> String {
        "A question?\n- [x] \(correct)\n- [ ] \(wrong)"
    }

    @Test func reportsAnOptionPastTheLimit() {
        let text = deck(correct: option(MarkdownParser.optionLimit + 1), wrong: "short")
        let parsed = MarkdownParser.parse(text, filename: "x.md")
        #expect(parsed.issues.contains { $0.kind == .longOption })
    }

    @Test func staysQuietAtExactlyTheLimit() {
        let text = deck(correct: option(MarkdownParser.optionLimit), wrong: "short")
        let parsed = MarkdownParser.parse(text, filename: "x.md")
        #expect(!parsed.issues.contains { $0.kind == .longOption })
    }

    /// Reported, not rejected: a deck full of long answers is still a deck you can study.
    @Test func keepsTheCardItComplainsAbout() {
        let text = deck(correct: option(200), wrong: "short")
        let parsed = MarkdownParser.parse(text, filename: "x.md")

        #expect(parsed.set.cards.count == 1)
        #expect(parsed.issues.contains { $0.kind == .longOption })
        guard case .multipleChoice(_, let choices) = parsed.set.cards[0].content else {
            Issue.record("expected a multiple-choice card"); return
        }
        #expect(choices.contains { $0.text.count == 200 })
    }

    /// One complaint per offending option, on its own line, so File Problems points at the
    /// line to edit rather than at the question above it.
    @Test func namesEveryLongOptionByItsOwnLine() {
        let long = option(120)
        let text = "A question?\n- [x] \(long)\n- [ ] short\n- [ ] \(long)"
        let parsed = MarkdownParser.parse(text, filename: "x.md")

        let flagged = parsed.issues.filter { $0.kind == .longOption }
        #expect(flagged.count == 2)
        #expect(flagged.map(\.line) == [2, 4])
    }

    /// Typed cards are answers you spell, not buttons you read, so length isn't the same
    /// problem — but they run through the same option parsing, so check the rule still lands.
    @Test func appliesToTypedAnswersToo() {
        let text = "A riddle?\n- [x] \(option(150))"
        let parsed = MarkdownParser.parse(text, filename: "x.md")
        #expect(parsed.issues.contains { $0.kind == .longOption })
    }

    @Test func theDeckPromptTellsTheModelTheSameLimit() {
        #expect(DeckPrompt.text(topic: "anything").contains("\(MarkdownParser.optionLimit) characters"))
    }
}
