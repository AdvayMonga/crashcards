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
        case longOption
        case orphanOptions
        case blankLineBeforeOptions
        case unclosedFence
        case notText          // produced by FolderAccess, not the parser
        case shortRow         // produced by DelimitedParser: a row with nothing to answer
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
            return "A question needs at least one option under it."
        case .noCorrectOption:
            return "None of these options is marked correct, so the card was skipped."
        case .multipleCorrectOptions:
            return "More than one option is marked `[x]` while others are `[ ]`, so the wrong ones can't be told apart. Mark only the right one, or mark them all `[x]` to make it a typed answer."
        case .malformedOption:
            return "This looks like an option but isn't written as `- [ ]` or `- [x]`."
        case .longOption:
            return "This option is longer than \(MarkdownParser.optionLimit) characters, so it won't fit on the answer button and will be cut short. Shorten it, or move the detail into the question."
        case .orphanOptions:
            return "These options have no question line above them."
        case .blankLineBeforeOptions:
            return "The options are separated from their question by a blank line."
        case .unclosedFence:
            return "This code fence is never closed, so everything below it was skipped."
        case .notText:
            return "This file isn't readable as text, so it was skipped."
        case .shortRow:
            return "This row has only one column, so there's no answer to show."
        }
    }

    /// The format that was expected — shown verbatim so it can be copied.
    var expected: String {
        switch kind {
        case .emptyFront, .emptyBack:
            return "Front of card :: Back of card"
        case .tooFewOptions, .noCorrectOption, .multipleCorrectOptions,
             .malformedOption, .longOption, .orphanOptions, .blankLineBeforeOptions:
            return MarkdownParser.questionExample
        case .unclosedFence:
            return MarkdownParser.fenceExample
        case .noCards, .notText:
            return MarkdownParser.formatGuide
        case .shortRow:
            return DelimitedParser.formatGuide
        }
    }
}

/// One file's parse result: the set (possibly with no cards) plus everything wrong with it.
struct ParsedFile {
    let set: FlashcardSet
    let issues: [ParseIssue]
}

/// Parses a flashcard `.md` file into flip cards, multiple-choice cards and typed cards.
///
/// Format:
///   # Deck Title            → names the set (first heading; falls back to filename)
///   Front :: Back           → a flip card
///   Question?               → a multiple-choice card, when *immediately* followed by a
///   - [ ] wrong               checkbox list. `- [x]` marks the correct option.
///   - [x] correct
///
///   Question?               → a typed card, when every option is `[x]`: there is nothing
///   - [x] answer              to rule out, so each one is a spelling that counts.
///   - [x] variant
///
/// YAML frontmatter, fenced code blocks, and other prose are ignored. Anything that looks
/// like a card but doesn't parse becomes a `ParseIssue` rather than being dropped silently.
enum MarkdownParser {
    /// How long an option can be and still be read on the answer button: two lines at the
    /// smallest scale the quiz will shrink text to. Measured against the widest phone the
    /// app supports, then rounded down, so the limit holds on the narrowest one too.
    static let optionLimit = 90

    /// A correct multiple-choice question, shown when one is malformed or missing.
    static let questionExample = """
    Which planet is closest to the Sun?
    - [ ] Venus
    - [x] Mercury
    - [ ] Mars
    """

    /// A closed code fence, shown when one was left open.
    static let fenceExample = """
    ```
    code goes here
    ```
    """

    /// The canonical file format, shown when a file has no usable cards.
    static let formatGuide = """
    # Deck Title

    Front of card :: Back of card

    \(questionExample)
    """

    static func parse(_ text: String, filename: String) -> ParsedFile {
        var title = SetFile.title(from: filename)
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
                // Running off the end means the fence never closed — say so, rather than
                // swallowing every card below it in silence.
                if j == lines.count {
                    issues.append(ParseIssue(line: i + 1, kind: .unclosedFence, excerpt: line))
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
                        // Reported, never rejected: the card still works, it just can't be
                        // read in full on the button, and only the author can fix that.
                        if choice.text.count > MarkdownParser.optionLimit {
                            issues.append(ParseIssue(line: j + 1, kind: .longOption, excerpt: raw))
                        }
                    } else {
                        // Keep scanning, so one bad option doesn't truncate the question.
                        issues.append(ParseIssue(line: j + 1, kind: .malformedOption, excerpt: raw))
                    }
                    j += 1
                }

                // Options with nothing to rule out are answers to type, not options to pick
                // from — so a riddle needs no invented distractors, and every `[x]` on it
                // is another spelling that counts.
                let correct = choices.filter(\.isCorrect)
                if choices.isEmpty {
                    issues.append(ParseIssue(line: i + 1, kind: .tooFewOptions, excerpt: line))
                } else if correct.isEmpty {
                    issues.append(ParseIssue(line: i + 1, kind: .noCorrectOption, excerpt: line))
                } else if correct.count == choices.count {
                    contents.append(.typed(question: line, accepted: correct.map(\.text)))
                } else {
                    // Some options are ruled out and more than one is not: still a card, and
                    // any marked option counts, but say so — the distinction is lost.
                    if correct.count > 1 {
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
