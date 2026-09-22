import Foundation

/// Turns pasted or fetched text into cards, whatever shape it arrived in.
///
/// Quizlet exports tab- or comma-separated pairs, notes apps use dashes, and an LLM will
/// happily hand you "Q: … / A: …". Rather than making you reformat, this guesses the
/// separator by seeing which one splits the most lines cleanly, and the caller shows a
/// preview so a wrong guess is obvious and fixable.
enum ImportParser {
    /// How a block of text separates a card's two sides.
    enum Layout: String, CaseIterable, Identifiable {
        case markdown       // our own :: and - [x] syntax
        case tab
        case comma
        case semicolon
        case dash
        case colon
        case questionAnswer // Q: … / A: …

        var id: String { rawValue }

        var title: String {
            switch self {
            case .markdown:       return "Crash Cards format"
            case .tab:            return "Tab"
            case .comma:          return "Comma"
            case .semicolon:      return "Semicolon"
            case .dash:           return "Dash"
            case .colon:          return "Colon"
            case .questionAnswer: return "Q: / A:"
            }
        }

        /// The string that splits a line, for the layouts that work that way.
        var separator: String? {
            switch self {
            case .tab:       return "\t"
            case .comma:     return ","
            case .semicolon: return ";"
            case .dash:      return " - "
            case .colon:     return ":"
            case .markdown, .questionAnswer: return nil
            }
        }
    }

    struct Result {
        var layout: Layout
        var cards: [Card]
        /// Lines that didn't produce a card, so nothing disappears without explanation.
        var skipped: Int
    }

    /// Parse with an explicit layout, or the best guess when none is given.
    static func parse(_ raw: String, as layout: Layout? = nil, title: String) -> Result {
        let text = unfenced(raw)
        let chosen = layout ?? detect(text)
        let contents: [CardContent]
        let lineCount: Int

        switch chosen {
        case .markdown:
            let parsed = MarkdownParser.parse(text, filename: "\(title).md")
            return Result(layout: .markdown, cards: parsed.set.cards,
                          skipped: parsed.issues.filter { $0.kind != .noCards }.count)
        case .questionAnswer:
            (contents, lineCount) = parseQuestionAnswer(text)
        default:
            (contents, lineCount) = parsePairs(text, separator: chosen.separator ?? "\t")
        }

        let cards = contents.map { Card(content: $0, setID: title, setTitle: title) }
        return Result(layout: chosen, cards: cards, skipped: max(0, lineCount - contents.count))
    }

    /// The contents of the largest fenced code block, or the text unchanged when there is none.
    ///
    /// Chatbots put the deck in a code block because that is what gives you a copy button,
    /// and the copy takes the ``` lines with it. `MarkdownParser` *skips* fenced blocks —
    /// right for an Obsidian note full of code samples, fatal for a paste that is nothing
    /// but the block — so the fence is unwrapped here, on the import path only.
    static func unfenced(_ text: String) -> String {
        var blocks: [String] = []
        var open: (fence: String, body: [String])?

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let marker = trimmed.hasPrefix("```") ? "```" : (trimmed.hasPrefix("~~~") ? "~~~" : nil)
            if let current = open, marker == current.fence {
                blocks.append(current.body.joined(separator: "\n"))
                open = nil
            } else if open == nil {
                if let marker { open = (marker, []) }   // rest of the line is the language tag
            } else {
                open?.body.append(line)
            }
        }
        // An unclosed fence still means the text below it was meant as the deck.
        if let current = open { blocks.append(current.body.joined(separator: "\n")) }

        let best = blocks.max { $0.count < $1.count } ?? ""
        return best.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : best
    }

    /// The layout that yields the most cards; ties go to the earlier, more explicit one.
    static func detect(_ text: String) -> Layout {
        if text.contains("::") || text.contains("- [x]") || text.contains("- [ ]") { return .markdown }
        // Explicit labels beat counting: the colon layout reads "Q: What is it?" as a card
        // of its own — two useless cards per pair, which is more than Q/A's one.
        if looksLabelled(text) { return .questionAnswer }

        var best: Layout = .tab
        var bestCount = 0
        for layout in Layout.allCases where layout != .markdown {
            let count = parse(text, as: layout, title: "probe").cards.count
            if count > bestCount {
                best = layout
                bestCount = count
            }
        }
        return best
    }

    /// Does the text mark its questions and answers by name?
    private static func looksLabelled(_ text: String) -> Bool {
        var questions = false
        var answers = false
        for line in lines(in: text) {
            let lowered = line.trimmingCharacters(in: .whitespaces).lowercased()
            if lowered.hasPrefix("q:") || lowered.hasPrefix("question:") { questions = true }
            if lowered.hasPrefix("a:") || lowered.hasPrefix("answer:") { answers = true }
            if questions && answers { return true }
        }
        return false
    }

    // MARK: - Shapes

    /// One card per line: "front<sep>back", or "question<sep>answer<sep>wrong<sep>wrong".
    private static func parsePairs(_ text: String, separator: String) -> ([CardContent], Int) {
        var contents: [CardContent] = []
        var considered = 0

        for raw in lines(in: text) {
            considered += 1
            let parts = raw.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            if parts.count == 2 {
                contents.append(.flip(front: parts[0], back: parts[1]))
            } else {
                let choices = [Choice(text: parts[1], isCorrect: true)]
                    + parts[2...].map { Choice(text: $0, isCorrect: false) }
                contents.append(.multipleChoice(question: parts[0], choices: choices.shuffled()))
            }
        }
        return (contents, considered)
    }

    /// "Q: …" followed by "A: …", the shape chat assistants tend to produce.
    private static func parseQuestionAnswer(_ text: String) -> ([CardContent], Int) {
        var contents: [CardContent] = []
        var pendingQuestion: String?
        var considered = 0

        for raw in lines(in: text) {
            considered += 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let question = strip(line, prefixes: ["q:", "question:"]) {
                pendingQuestion = question
            } else if let answer = strip(line, prefixes: ["a:", "answer:"]), let question = pendingQuestion {
                if !question.isEmpty && !answer.isEmpty {
                    contents.append(.flip(front: question, back: answer))
                }
                pendingQuestion = nil
            }
        }
        return (contents, considered)
    }

    private static func strip(_ line: String, prefixes: [String]) -> String? {
        let lowered = line.lowercased()
        guard let prefix = prefixes.first(where: { lowered.hasPrefix($0) }) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func lines(in text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - Saving

    /// Cards as a `.md` file in our own format, so an import is indistinguishable from a
    /// set you wrote by hand — and stays editable as plain text.
    static func markdown(title: String, cards: [Card]) -> String {
        var out = ["# \(title)", ""]
        for card in cards {
            switch card.content {
            case .flip(let front, let back):
                out.append("\(front) :: \(back)")
                out.append("")
            case .multipleChoice(let question, let choices):
                out.append(question)
                for choice in choices {
                    out.append("- [\(choice.isCorrect ? "x" : " ")] \(choice.text)")
                }
                out.append("")
            }
        }
        return out.joined(separator: "\n")
    }
}
