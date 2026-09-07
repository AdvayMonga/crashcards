import Foundation

/// Parses a flashcard `.md` file into flip cards and multiple-choice cards.
///
/// Format:
///   # Deck Title            → names the set (first heading; falls back to filename)
///   Front :: Back           → a flip card
///   Question?               → a multiple-choice card, when immediately followed by a
///   - [ ] wrong             checkbox list. `- [x]` marks the correct option.
///   - [x] correct
///
/// Blank lines and other prose are ignored.
enum MarkdownParser {
    static func parse(_ text: String, filename: String) -> FlashcardSet {
        var title = filename.replacingOccurrences(
            of: #"\.md$"#, with: "", options: [.regularExpression, .caseInsensitive]
        )
        var titleFromHeading = false
        var contents: [CardContent] = []

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { i += 1; continue }

            if line.hasPrefix("#") {
                if !titleFromHeading {
                    let heading = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                    if !heading.isEmpty { title = heading; titleFromHeading = true }
                }
                i += 1
                continue
            }

            // Flip card: any line with "::".
            if let sep = line.range(of: "::") {
                let front = line[..<sep.lowerBound].trimmingCharacters(in: .whitespaces)
                let back = line[sep.upperBound...].trimmingCharacters(in: .whitespaces)
                if !front.isEmpty && !back.isEmpty {
                    contents.append(.flip(front: front, back: back))
                }
                i += 1
                continue
            }

            // Multiple choice: this line is the question if the next line is a checklist item.
            if i + 1 < lines.count, parseChoice(lines[i + 1]) != nil {
                var choices: [Choice] = []
                var j = i + 1
                while j < lines.count, let choice = parseChoice(lines[j]) {
                    choices.append(choice)
                    j += 1
                }
                // Valid MC needs at least two options and a marked correct answer.
                if choices.count >= 2 && choices.contains(where: \.isCorrect) {
                    contents.append(.multipleChoice(question: line, choices: choices.shuffled()))
                }
                i = j
                continue
            }

            i += 1   // plain prose — ignored
        }

        // Stamped after the loop, once the title heading (if any) has been seen.
        let cards = contents.map { Card(content: $0, setID: filename, setTitle: title) }
        return FlashcardSet(id: filename, title: title, cards: cards)
    }

    /// Parse a single `- [ ] text` / `- [x] text` checklist line into a `Choice`, or nil.
    private static func parseChoice(_ raw: String) -> Choice? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard let bullet = line.first, bullet == "-" || bullet == "*" else { return nil }
        let chars = Array(line.dropFirst().drop { $0 == " " })
        guard chars.count >= 3, chars[0] == "[", chars[2] == "]" else { return nil }

        let isCorrect: Bool
        switch chars[1] {
        case " ": isCorrect = false
        case "x", "X": isCorrect = true
        default: return nil
        }

        let optionText = String(chars[3...]).trimmingCharacters(in: .whitespaces)
        guard !optionText.isEmpty else { return nil }
        return Choice(text: optionText, isCorrect: isCorrect)
    }
}
