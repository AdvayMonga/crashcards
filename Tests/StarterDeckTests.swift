import Testing
import Foundation
@testable import crashcards

struct StarterDeckTests {
    private func cards(in name: String) throws -> [Card] {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "md"),
                               "\(name).md is not in the app bundle")
        let text = try String(contentsOf: url, encoding: .utf8)
        let parsed = MarkdownParser.parse(text, filename: "\(name).md")
        #expect(parsed.issues.isEmpty)
        return parsed.set.cards
    }

    /// The seeded files have to survive the same parser every other set goes through.
    @Test(arguments: StarterDecks.names)
    func parseIntoTwentyCards(name: String) throws {
        #expect(try cards(in: name).count == 20)
    }

    /// The two decks are the tutorial for the two ways of answering, so each has to be
    /// wholly one kind — a mixed starter deck teaches neither.
    @Test func eachDeckDemonstratesOneAnswerStyle() throws {
        let multipleChoice = try cards(in: "Weird But True").filter(\.isMultipleChoice).count
        #expect(multipleChoice == 20)

        let typed = try cards(in: "Riddles").filter { $0.typedAnswers != nil }.count
        #expect(typed == 20)
    }

    /// Riddles are typed, so the accepted spellings have to survive normalisation — and
    /// two riddles must never accept the same answer.
    @Test func riddleAnswersAreDistinctAndNonEmpty() throws {
        var seen: Set<String> = []
        for card in try cards(in: "Riddles") {
            let accepted = try #require(card.typedAnswers)
            #expect(!accepted.isEmpty)
            for answer in accepted {
                let key = AnswerMatcher.normalise(answer)
                #expect(!key.isEmpty, "empty accepted answer on: \(card.prompt)")
                #expect(!seen.contains(key), "two riddles both accept \"\(answer)\"")
                seen.insert(key)
            }
        }
    }

    /// If the right answer is reliably the longest, the deck can be passed without knowing
    /// anything — the one deck-quality rule worth enforcing in code.
    @Test func doNotGiveTheAnswerAwayByLength() throws {
        let cards = try cards(in: "Weird But True")
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

    @Test func prefillsTheProvidersThatSupportIt() throws {
        let claude = try #require(AIProvider.all.first { $0.id == "claude" })
        let url = try #require(claude.url(prompt: "explain this card"))
        #expect(url.absoluteString.hasPrefix("https://claude.ai/new?q="))
        #expect(url.absoluteString.contains("explain"))
    }

    /// Gemini has no prefill parameter, so it must still open rather than fail.
    @Test func opensTheProvidersThatDoNot() throws {
        let gemini = try #require(AIProvider.all.first { $0.id == "gemini" })
        let url = try #require(gemini.url(prompt: "explain this card"))
        #expect(url.absoluteString == "https://gemini.google.com/app")
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
