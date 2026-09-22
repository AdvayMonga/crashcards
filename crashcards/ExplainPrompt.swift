import Foundation

/// The prompt behind "Explain": the cards you got wrong, handed to a chatbot verbatim.
///
/// The whole card goes over, distractors included, because the useful explanation is
/// usually about why the option you picked was tempting — an answer key alone can't say
/// that. Nothing comes back into the app, so this is a one-way handoff.
enum ExplainPrompt {
    /// Batched on purpose: finishing a run and asking about all five misses at once beats
    /// bouncing out to a chat five times.
    static func text(for cards: [Card]) -> String {
        let body = cards.enumerated().map { index, card in
            let heading = cards.count == 1 ? "" : "\n\(index + 1). "
            return heading + describe(card)
        }.joined(separator: "\n")

        return """
        I got \(cards.count == 1 ? "this flashcard" : "these \(cards.count) flashcards") wrong. \
        For each one, explain why the correct answer is right, and why the other options are \
        wrong in a way that would tempt someone who half-knows the topic. Keep each \
        explanation to a short paragraph, and tell me the underlying idea I'm missing rather \
        than restating the answer.
        \(body)
        """
    }

    private static func describe(_ card: Card) -> String {
        switch card.content {
        case .flip(let front, let back):
            return "\(front)\nAnswer: \(back)"
        case .multipleChoice(let question, let choices):
            let options = choices.map { choice in
                "- \(choice.text)\(choice.isCorrect ? "  <- correct" : "")"
            }.joined(separator: "\n")
            return "\(question)\n\(options)"
        }
    }
}
