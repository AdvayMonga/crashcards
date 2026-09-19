import Foundation

/// Reads `.csv` / `.tsv` exports — Quizlet, Google Sheets, Excel — as cards.
///
/// Layout:
///   Term, Definition                       → a flip card
///   Question, Correct answer, Wrong, Wrong → a multiple-choice card (column 2 is correct)
///
/// A header row (Term/Definition, Question/Answer, Front/Back…) is skipped. The set takes
/// its name from the filename.
enum DelimitedParser {
    static let formatGuide = """
    Term,Definition
    Question,Correct answer,Wrong answer,Wrong answer
    """

    private static let headerWords: Set<String> = [
        "term", "definition", "question", "answer", "front", "back",
        "prompt", "correct", "correct answer", "word", "meaning",
    ]

    static func parse(_ text: String, filename: String) -> ParsedFile {
        let title = SetFile.title(from: filename)
        let separator: Character = filename.lowercased().hasSuffix(".tsv") ? "\t" : ","
        var contents: [CardContent] = []
        var issues: [ParseIssue] = []

        var headerChecked = false
        for (index, row) in rows(in: text, separator: separator).enumerated() {
            // Trailing empties are dropped, inner ones kept: a blank cell must hold its
            // place, or a leading index column would silently shift every card along.
            var cells = row.map { $0.trimmingCharacters(in: .whitespaces) }
            while let last = cells.last, last.isEmpty { cells.removeLast() }
            if cells.isEmpty { continue }

            // The header is the first row with content, which isn't always row one.
            if !headerChecked {
                headerChecked = true
                if isHeader(cells) { continue }
            }

            guard cells.count >= 2, !cells[0].isEmpty, !cells[1].isEmpty else {
                issues.append(ParseIssue(line: index + 1, kind: .shortRow, excerpt: cells[0]))
                continue
            }
            let distractors = cells.dropFirst(2).filter { !$0.isEmpty }
            if distractors.isEmpty {
                contents.append(.flip(front: cells[0], back: cells[1]))
            } else {
                let choices = [Choice(text: cells[1], isCorrect: true)]
                    + distractors.map { Choice(text: $0, isCorrect: false) }
                contents.append(.multipleChoice(question: cells[0], choices: choices.shuffled()))
            }
        }

        if contents.isEmpty {
            issues.append(ParseIssue(line: 0, kind: .noCards, excerpt: ""))
        }
        let cards = contents.map { Card(content: $0, setID: filename, setTitle: title) }
        return ParsedFile(set: FlashcardSet(id: filename, title: title, cards: cards), issues: issues)
    }

    /// A header row names the columns instead of holding a card.
    private static func isHeader(_ cells: [String]) -> Bool {
        cells.prefix(2).allSatisfy { headerWords.contains($0.lowercased()) }
    }

    /// Split into rows and cells, honouring "quoted fields" that contain separators,
    /// newlines, or doubled "" quotes.
    private static func rows(in text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.replacingOccurrences(of: "\r\n", with: "\n").makeIterator()
        var pending: Character?

        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"" where field.allSatisfy(\.isWhitespace): field = ""; inQuotes = true
            case separator: row.append(field); field = ""
            case "\n": row.append(field); rows.append(row); row = []; field = ""
            default: field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
