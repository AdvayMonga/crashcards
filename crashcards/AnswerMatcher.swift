import Foundation

/// Decides whether what you typed counts as the answer.
///
/// Forgiving on purpose. Quiz mode types every card that isn't multiple choice, so the
/// answers it grades were written to be *read* — "a towel", "Towel.", "the hourglass" are
/// the same answer, and failing someone on an article or a full stop teaches nothing.
///
/// What it will not do is guess. Matching is on the whole normalised answer, never on a
/// substring or a near-spelling: a card you got wrong should say so plainly, because the
/// only thing worse than a strict matcher is one that tells you a wrong answer was right.
enum AnswerMatcher {
    static func matches(_ typed: String, anyOf accepted: [String]) -> Bool {
        let attempt = normalise(typed)
        guard !attempt.isEmpty else { return false }
        return accepted.contains { normalise($0) == attempt }
    }

    /// Lowercased, accents dropped, stripped of punctuation and outer whitespace, inner
    /// runs collapsed, and with a leading article dropped.
    ///
    /// Accents go because the quiz's own keyboard has no way to type them: "cafe" has to
    /// count for "café" or a language deck can't be answered at all.
    static func normalise(_ text: String) -> String {
        let cleaned = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .unicodeScalars
            .map { CharacterSet.punctuationCharacters.contains($0) ? " " : Character($0) }
        let words = String(cleaned).split(separator: " ").map(String.init)
        // "a towel" and "towel" are one answer; "a" alone is still an answer.
        let articles = ["a", "an", "the"]
        if words.count > 1, let first = words.first, articles.contains(first) {
            return words.dropFirst().joined(separator: " ")
        }
        return words.joined(separator: " ")
    }
}
