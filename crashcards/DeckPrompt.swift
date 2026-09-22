import Foundation

/// The ready-made prompt that turns a chatbot into a deck generator.
///
/// The app has no API key and no backend: you copy this, paste it wherever you already
/// have a subscription, and share the answer back. So the prompt has to carry every rule
/// the importer enforces — there is no second chance to correct the model.
enum DeckPrompt {
    /// Where the topic goes. Replaced before the prompt is handed over.
    private static let placeholder = "TOPIC"

    static func text(topic: String) -> String {
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        return template.replacingOccurrences(
            of: placeholder,
            with: trimmed.isEmpty ? "a topic I'll describe below" : trimmed)
    }

    /// Kept under ~1600 characters so it still fits in a `?q=` link after escaping.
    private static let template = """
    Make me a flashcard deck on: TOPIC

    If I've attached notes, a photo, or a file, build the deck from that. Otherwise use your own knowledge of the topic.

    Reply with ONE fenced code block containing only the deck. No preamble, no notes after it.

    Format is a title line, then cards. Each card is a question followed immediately by four options:

    # Deck Title

    What happens to the volume of a gas when you double its temperature at constant pressure?
    - [ ] It halves, because temperature and volume trade off
    - [x] It doubles, because volume rises in step with absolute temperature
    - [ ] It stays the same, because pressure is what sets volume
    - [ ] It quadruples, because the relationship is squared

    Rules, which the importer enforces strictly:
    - Exactly one option marked [x]. Every other option is [ ].
    - No blank line between a question and its first option.
    - One blank line between cards.
    - One line per option. No sub-bullets, no numbering, no bold.
    - Never write "all of the above" or "both A and B" — options get shuffled.

    What makes a good card:
    - Test whether I understand the thing, not whether I've seen the word. Ask how it works, why it's that way, or what breaks if you change one part.
    - Every wrong option should be something a person who half-learned this would genuinely pick. Nothing absurd or obviously padded.
    - Keep the four options within a few words of each other in length. If the correct one is always the longest, I can pass the deck without knowing anything.
    - Keep questions to one or two lines and options short.

    Make as many cards as the material genuinely supports. If I gave you source material, cover all of it rather than stopping at a round number. Stop at 200 cards.
    """

    /// A chatbot worth sending the prompt to.
    ///
    /// The `https://` links are deliberate: iOS opens the provider's app when it's installed
    /// and falls back to the browser when it isn't, which a custom scheme can't do.
    struct Provider: Identifiable {
        let id: String
        let name: String
        /// Nil where the provider has no documented way to prefill a new chat.
        private let query: String?
        private let home: String

        func url(prompt: String) -> URL? {
            guard let query,
                  let escaped = prompt.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
            else { return URL(string: home) }
            return URL(string: query + escaped) ?? URL(string: home)
        }

        static let all = [
            Provider(id: "claude", name: "Claude",
                     query: "https://claude.ai/new?q=", home: "https://claude.ai"),
            Provider(id: "chatgpt", name: "ChatGPT",
                     query: "https://chatgpt.com/?q=", home: "https://chatgpt.com"),
            // Gemini has no prefill parameter, so it opens cold and relies on the clipboard.
            Provider(id: "gemini", name: "Gemini",
                     query: nil, home: "https://gemini.google.com/app"),
        ]
    }
}
