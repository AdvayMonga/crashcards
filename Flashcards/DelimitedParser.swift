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
        let title = filename.replacingOccurrences(
            of: #"\.(csv|tsv)$"#, with: "", options: [.regularExpression, .caseInsensitive]
        )
        let separator: Character = filename.lowercased().hasSuffix(".tsv") ? "\t" : ","
        var contents: [CardContent] = []
        var issues: [ParseIssue] = []

        let rows = rows(in: text, separator: separator)
        for (index, row) in rows.enumerated() {
            let cells = row.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if cells.isEmpty { continue }
            if index == 0, isHeader(cells) { continue }

            guard cells.count >= 2 else {
                issues.append(ParseIssue(line: index + 1, kind: .shortRow, excerpt: cells[0]))
                continue
            }
            if cells.count == 2 {
                contents.append(.flip(front: cells[0], back: cells[1]))
            } else {
                let choices = [Choice(text: cells[1], isCorrect: true)]
                    + cells[2...].map { Choice(text: $0, isCorrect: false) }
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
            case "\"" where field.isEmpty: inQuotes = true
            case separator: row.append(field); field = ""
            case "\n": row.append(field); rows.append(row); row = []; field = ""
            default: field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
