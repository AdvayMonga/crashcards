import Testing
import Foundation
@testable import crashcards

struct DeckPromptTests {
    @Test func putsTheTopicInThePrompt() {
        let prompt = DeckPrompt.text(topic: "Krebs cycle")
        #expect(prompt.contains("flashcard deck on: Krebs cycle"))
        #expect(!prompt.contains("TOPIC"))
    }

    @Test func standsInForAnEmptyTopic() {
        #expect(!DeckPrompt.text(topic: "   ").contains("TOPIC"))
    }

    /// The prompt is also handed over as a `?q=` parameter, where length is not free.
    @Test func staysShortEnoughToSurviveALink() {
        let escaped = DeckPrompt.text(topic: "photosynthesis")
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        #expect(escaped.count < 4000)
    }

    @Test func prefillsTheProvidersThatSupportIt() throws {
        let claude = try #require(AIProvider.all.first { $0.id == "claude" })
        let url = try #require(claude.url(prompt: "make me cards"))
        #expect(url.absoluteString.hasPrefix("https://claude.ai/new?q="))
        #expect(url.absoluteString.contains("make"))
    }

    /// Gemini has no prefill parameter, so it must still open rather than fail.
    @Test func opensTheProvidersThatDoNot() throws {
        let gemini = try #require(AIProvider.all.first { $0.id == "gemini" })
        let url = try #require(gemini.url(prompt: "make me cards"))
        #expect(url.absoluteString == "https://gemini.google.com/app")
    }
}

struct FencedPasteTests {
    private let deck = """
    # Space

    Which planet spins slowest?
    - [x] Venus
    - [ ] Mars
    - [ ] Mercury
    """

    @Test func readsADeckWrappedInACodeFence() {
        let pasted = "```markdown\n\(deck)\n```"
        let result = ImportParser.parse(pasted, title: "Space")
        #expect(result.layout == .markdown)
        #expect(result.cards.count == 1)
    }

    @Test func ignoresTheChatterAroundTheFence() {
        let pasted = "Sure! Here is your deck:\n\n```\n\(deck)\n```\n\nLet me know if you'd like more."
        #expect(ImportParser.parse(pasted, title: "Space").cards.count == 1)
    }

    @Test func takesTheDeckWhenAFenceIsLeftOpen() {
        #expect(ImportParser.parse("```\n\(deck)", title: "Space").cards.count == 1)
    }

    @Test func leavesUnfencedTextAlone() {
        #expect(ImportParser.parse(deck, title: "Space").cards.count == 1)
    }

    /// A fence containing nothing must not blank out a paste that had cards outside it.
    @Test func ignoresAnEmptyFence() {
        #expect(ImportParser.parse("\(deck)\n\n```\n```", title: "Space").cards.count == 1)
    }
}

struct StarterDeckTests {
    /// The seeded files have to survive the same parser every other set goes through.
    @Test(arguments: StarterDecks.names)
    func parseIntoTwentyQuestions(name: String) throws {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "md"),
                               "\(name).md is not in the app bundle")
        let text = try String(contentsOf: url, encoding: .utf8)
        let parsed = MarkdownParser.parse(text, filename: "\(name).md")

        // `allSatisfy` is rethrows, which the #expect expansion can't infer through.
        let questions = parsed.set.cards.filter(\.isMultipleChoice).count
        #expect(parsed.issues.isEmpty)
        #expect(parsed.set.cards.count == 20)
        #expect(questions == 20)
    }

    /// If the right answer is reliably the longest, the deck can be passed without knowing
    /// anything — the one deck-quality rule worth enforcing in code.
    @Test(arguments: StarterDecks.names)
    func doNotGiveTheAnswerAwayByLength(name: String) throws {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "md"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let cards = MarkdownParser.parse(text, filename: "\(name).md").set.cards

        let longestIsCorrect = cards.filter { card in
            guard case .multipleChoice(_, let choices) = card.content,
                  let longest = choices.max(by: { $0.text.count < $1.text.count }) else { return false }
            return longest.isCorrect
        }
        #expect(longestIsCorrect.count <= cards.count / 2)
    }
}

struct ExplainPromptTests {
    private func question(_ text: String, right: String, wrong: [String]) -> Card {
        let choices = [Choice(text: right, isCorrect: true)]
            + wrong.map { Choice(text: $0, isCorrect: false) }
        return Card(content: .multipleChoice(question: text, choices: choices),
                    setID: "s", setTitle: "Set")
    }

    /// The distractors have to go over too — "why was the one I picked tempting" is the
    /// question you actually have, and an answer key alone can't answer it.
    @Test func sendsTheWholeCardNotJustTheAnswer() {
        let prompt = ExplainPrompt.text(for: [question("Why is the sky blue?",
                                                       right: "Rayleigh scattering",
                                                       wrong: ["Reflected ocean", "Ozone colour"])])
        #expect(prompt.contains("Why is the sky blue?"))
        #expect(prompt.contains("Rayleigh scattering"))
        #expect(prompt.contains("Reflected ocean"))
        #expect(prompt.contains("Ozone colour"))
    }

    @Test func marksWhichOptionWasCorrect() {
        let prompt = ExplainPrompt.text(for: [question("Q", right: "Right", wrong: ["Wrong"])])
        #expect(prompt.contains("- Right  <- correct"))
        #expect(prompt.contains("- Wrong"))
        #expect(!prompt.contains("- Wrong  <- correct"))
    }

    @Test func numbersABatchButNotASingleCard() {
        let one = ExplainPrompt.text(for: [question("A", right: "r", wrong: ["w"])])
        #expect(one.contains("this flashcard"))
        #expect(!one.contains("1. "))

        let many = ExplainPrompt.text(for: [question("A", right: "r", wrong: ["w"]),
                                            question("B", right: "r", wrong: ["w"])])
        #expect(many.contains("these 2 flashcards"))
        #expect(many.contains("2. B"))
    }

    @Test func handlesAFlipCard() {
        let card = Card(content: .flip(front: "Capital of France", back: "Paris"),
                        setID: "s", setTitle: "Set")
        let prompt = ExplainPrompt.text(for: [card])
        #expect(prompt.contains("Capital of France"))
        #expect(prompt.contains("Answer: Paris"))
    }

    /// Explain is study-mode only, so it must survive a long run of misses in a link.
    @Test func staysUsableForAWholeRunOfMisses() {
        let cards = (1...20).map { question("Question \($0)?", right: "Right", wrong: ["A", "B", "C"]) }
        let escaped = ExplainPrompt.text(for: cards)
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        #expect(escaped.count < 16000)
    }

    @Test func followsThePreferredProvider() {
        let original = Prefs.preferredProviderID
        defer { Prefs.preferredProviderID = original }

        Prefs.preferredProviderID = "chatgpt"
        #expect(AIProvider.preferred.id == "chatgpt")
        Prefs.preferredProviderID = "nonsense"
        #expect(AIProvider.preferred.id == "claude")   // falls back rather than vanishing
    }
}
