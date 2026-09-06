import Foundation

/// A problem found while loading a `.md` file.
///
/// Issues are *reported only* — the app never edits your files. Each one carries the line
/// to look at, what's wrong, and the format it expected, so you can fix it in Obsidian.
struct ParseIssue: Identifiable, Hashable {
    enum Kind {
        case noCards
        case emptyFront
        case emptyBack
        case tooFewOptions
        case noCorrectOption
        case multipleCorrectOptions
        case malformedOption
        case orphanOptions
        case blankLineBeforeOptions
        case notText          // produced by FolderAccess, not the parser
    }

    let id = UUID()
    /// 1-based line in the file. `0` when the issue is about the file as a whole.
    let line: Int
    let kind: Kind
    /// The offending line, trimmed, for context. Empty for whole-file issues.
    let excerpt: String

    /// What's wrong, in one sentence.
    var message: String {
        switch kind {
        case .noCards:
            return "No usable cards in this file."
        case .emptyFront:
            return "Nothing before `::` — a flip card needs both a front and a back."
        case .emptyBack:
            return "Nothing after `::` — a flip card needs both a front and a back."
        case .tooFewOptions:
            return "A multiple-choice question needs at least two options."
        case .noCorrectOption:
            return "None of these options is marked correct, so the card was skipped."
        case .multipleCorrectOptions:
            return "More than one option is marked `[x]`; only the first is used as the answer."
        case .malformedOption:
            return "This looks like an option but isn't written as `- [ ]` or `- [x]`."
        case .orphanOptions:
            return "These options have no question line above them."
        case .blankLineBeforeOptions:
            return "The options are separated from their question by a blank line."
        case .notText:
            return "This file isn't readable as text, so it was skipped."
        }
    }

    /// The format that was expected — shown verbatim so it can be copied.
    var expected: String {
        switch kind {
        case .emptyFront, .emptyBack:
            return "Front of card :: Back of card"
        case .tooFewOptions, .noCorrectOption, .multipleCorrectOptions,
             .malformedOption, .orphanOptions, .blankLineBeforeOptions:
            return MarkdownParser.questionExample
        case .noCards, .notText:
            return MarkdownParser.formatGuide
        }
    }
}

/// One file's parse result: the set (possibly with no cards) plus everything wrong with it.
struct ParsedFile {
    let set: FlashcardSet
    let issues: [ParseIssue]
}

/// Parses a flashcard `.md` file into flip cards and multiple-choice cards.
///
/// Format:
///   # Deck Title            → names the set (first heading; falls back to filename)
///   Front :: Back           → a flip card
///   Question?               → a multiple-choice card, when *immediately* followed by a
///   - [ ] wrong               checkbox list. `- [x]` marks the correct option.
///   - [x] correct
///
/// YAML frontmatter, fenced code blocks, and other prose are ignored. Anything that looks
/// like a card but doesn't parse becomes a `ParseIssue` rather than being dropped silently.
enum MarkdownParser {
    /// A correct multiple-choice question, shown when one is malformed or missing.
    static let questionExample = """
    Which planet is closest to the Sun?
    - [ ] Venus
    - [x] Mercury
    - [ ] Mars
    """

    /// The canonical file format, shown when a file has no usable cards.
    static let formatGuide = """
    # Deck Title

    Front of card :: Back of card

    \(questionExample)
    """

    static func parse(_ text: String, filename: String) -> ParsedFile {
        var title = filename.replacingOccurrences(
            of: #"\.md$"#, with: "", options: [.regularExpression, .caseInsensitive]
        )
        var titleFromHeading = false
        var contents: [CardContent] = []
        var issues: [ParseIssue] = []

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = skippingFrontmatter(lines)

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { i += 1; continue }

            // Fenced code block — `std::cout` inside one is code, not a card.
            if let fence = codeFence(line) {
                var j = i + 1
                while j < lines.count, codeFence(lines[j].trimmingCharacters(in: .whitespaces)) != fence {
                    j += 1
                }
                i = min(j + 1, lines.count)
                continue
            }

            // "# Heading" (a bare "#tag" is not a heading).
            if isHeading(line) {
                if !titleFromHeading {
                    let heading = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                    if !heading.isEmpty { title = heading; titleFromHeading = true }
                }
                i += 1
                continue
            }

            // Options reached at top level had no question line consume them.
            if looksLikeOption(line) {
                var j = i
                while j < lines.count, looksLikeOption(lines[j].trimmingCharacters(in: .whitespaces)) {
                    j += 1
                }
                let kind: ParseIssue.Kind = hasQuestionAbove(lines, before: i)
                    ? .blankLineBeforeOptions : .orphanOptions
                issues.append(ParseIssue(line: i + 1, kind: kind, excerpt: line))
                i = j
                continue
            }

            // Flip card: any line with "::".
            if let sep = line.range(of: "::") {
                let front = line[..<sep.lowerBound].trimmingCharacters(in: .whitespaces)
                let back = line[sep.upperBound...].trimmingCharacters(in: .whitespaces)
                if front.isEmpty {
                    issues.append(ParseIssue(line: i + 1, kind: .emptyFront, excerpt: line))
                } else if back.isEmpty {
                    issues.append(ParseIssue(line: i + 1, kind: .emptyBack, excerpt: line))
                } else {
                    contents.append(.flip(front: front, back: back))
                }
                i += 1
                continue
            }

            // Multiple choice: this line is the question if the next line is a checklist item.
            if i + 1 < lines.count, looksLikeOption(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                var choices: [Choice] = []
                var j = i + 1
                while j < lines.count {
                    let raw = lines[j].trimmingCharacters(in: .whitespaces)
                    guard looksLikeOption(raw) else { break }
                    if let choice = parseChoice(raw) {
                        choices.append(choice)
                    } else {
                        // Keep scanning, so one bad option doesn't truncate the question.
                        issues.append(ParseIssue(line: j + 1, kind: .malformedOption, excerpt: raw))
                    }
                    j += 1
                }

                let correctCount = choices.filter(\.isCorrect).count
                if choices.count < 2 {
                    issues.append(ParseIssue(line: i + 1, kind: .tooFewOptions, excerpt: line))
                } else if correctCount == 0 {
                    issues.append(ParseIssue(line: i + 1, kind: .noCorrectOption, excerpt: line))
                } else {
                    if correctCount > 1 {
                        issues.append(ParseIssue(line: i + 1, kind: .multipleCorrectOptions, excerpt: line))
                    }
                    contents.append(.multipleChoice(question: line, choices: choices.shuffled()))
                }
                i = j
                continue
            }

            i += 1   // plain prose — ignored
        }

        // A file with neither cards nor complaints is just a note; stay quiet about it.
        if contents.isEmpty && !issues.isEmpty {
            issues.insert(ParseIssue(line: 0, kind: .noCards, excerpt: ""), at: 0)
        }

        // Stamped after the loop, once the title heading (if any) has been seen.
        let cards = contents.map { Card(content: $0, setID: filename, setTitle: title) }
        return ParsedFile(set: FlashcardSet(id: filename, title: title, cards: cards), issues: issues)
    }

    // MARK: - Line classification

    /// Index of the first line after a leading `---` YAML block (0 if there isn't one).
    private static func skippingFrontmatter(_ lines: [String]) -> Int {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return 0 }
        var j = 1
        while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces) != "---" { j += 1 }
        return j < lines.count ? j + 1 : 0   // unterminated: treat the file as ordinary text
    }

    /// The fence character of a ``` / ~~~ line, or nil.
    private static func codeFence(_ line: String) -> Character? {
        (line.hasPrefix("```") || line.hasPrefix("~~~")) ? line.first : nil
    }

    /// ATX heading: one or more `#` followed by a space (so `#tag` isn't a title).
    private static func isHeading(_ line: String) -> Bool {
        guard line.hasPrefix("#") else { return false }
        let rest = line.drop { $0 == "#" }
        return rest.isEmpty || rest.first == " "
    }

    /// A bullet followed by `[` — an option, well-formed or not.
    private static func looksLikeOption(_ line: String) -> Bool {
        guard let bullet = line.first, bullet == "-" || bullet == "*" else { return false }
        return line.dropFirst().drop { $0 == " " }.first == "["
    }

    /// Is there a plain (non-option, non-heading) line above `index`, past blank lines?
    private static func hasQuestionAbove(_ lines: [String], before index: Int) -> Bool {
        var j = index - 1
        while j >= 0 {
            let line = lines[j].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { j -= 1; continue }
            return !isHeading(line) && !looksLikeOption(line)
        }
        return false
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
