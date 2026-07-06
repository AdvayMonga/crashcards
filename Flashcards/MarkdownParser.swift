import Foundation

/// Parses a flashcard `.md` file.
///
/// Format:
///   # Deck Title
///   Front of card :: Back of card
///
/// - The first `#` heading names the set (falls back to the filename).
/// - Every line containing `::` is a card: text before `::` is the front, after is the back.
/// - Blank lines and lines without `::` (other than the title) are ignored.
enum MarkdownParser {
    static func parse(_ text: String, filename: String) -> FlashcardSet {
        var title = filename.replacingOccurrences(
            of: #"\.md$"#, with: "", options: [.regularExpression, .caseInsensitive]
        )
        var titleFromHeading = false
        var cards: [Card] = []

        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#") {
                if !titleFromHeading {
                    let heading = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                    if !heading.isEmpty {
                        title = heading
                        titleFromHeading = true
                    }
                }
                continue
            }

            guard let sep = line.range(of: "::") else { continue }
            let front = line[..<sep.lowerBound].trimmingCharacters(in: .whitespaces)
            let back = line[sep.upperBound...].trimmingCharacters(in: .whitespaces)
            if front.isEmpty || back.isEmpty { continue }
            cards.append(Card(front: front, back: back))
        }

        return FlashcardSet(id: filename, title: title, cards: cards)
    }
}
