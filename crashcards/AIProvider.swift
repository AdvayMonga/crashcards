import Foundation

/// A chatbot the app can hand a prompt to.
///
/// Handing over is all it does: there is no API key and no network call anywhere in the
/// app, so every feature built on this opens a chat with the prompt ready and the answer
/// stays over there. Shared by deck generation and by explaining a card.
///
/// The `https://` links are deliberate: iOS opens the provider's app when it's installed
/// and falls back to the browser when it isn't, which a custom scheme can't do.
struct AIProvider: Identifiable, Hashable {
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
        AIProvider(id: "claude", name: "Claude",
                   query: "https://claude.ai/new?q=", home: "https://claude.ai"),
        AIProvider(id: "chatgpt", name: "ChatGPT",
                   query: "https://chatgpt.com/?q=", home: "https://chatgpt.com"),
        // Gemini has no prefill parameter, so it opens cold and relies on the clipboard.
        AIProvider(id: "gemini", name: "Gemini",
                   query: nil, home: "https://gemini.google.com/app"),
    ]

    /// The one "Explain" goes to, since that button has no room to ask which.
    static var preferred: AIProvider {
        all.first { $0.id == Prefs.preferredProviderID } ?? all[0]
    }
}
