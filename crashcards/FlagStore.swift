import Foundation
import Observation

/// A reason offered by the flag picker. The stored reason is free text, so reasons you
/// write by hand in `Flagged.md` survive a rewrite.
enum FlagReason: String, CaseIterable, Identifiable {
    case remove = "remove"
    case tooEasy = "too easy"
    case tooWordy = "too wordy"
    case tooObscure = "too obscure"
    case wrongAnswer = "wrong answer"
    case reword = "reword"

    var id: String { rawValue }
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// One flagged card: enough to find it again in its source `.md`.
struct Flag: Identifiable, Hashable {
    let setID: String
    let setTitle: String
    let prompt: String
    let answer: String
    var reason: String
    var done = false

    /// Cards get a fresh UUID on every parse, so flags key off the source line instead.
    var id: String { "\(setID)|\(prompt)" }
}

/// Reads and writes `Flagged.md` in the primary flashcards folder.
///
/// That file is the only state: it's re-read on launch and foreground, so deleting an
/// entry in Obsidian unflags the card in the app.
@Observable
final class FlagStore {
    static let filename = "Flagged.md"

    private(set) var flags: [Flag] = []
    /// Why the file couldn't be read, if it exists but wouldn't open.
    private(set) var loadError: String?
    /// True when the file is present but unreadable. Flagging is disabled rather than risk
    /// rewriting a file whose contents we never saw.
    private(set) var isLocked = false
    var writeError: String?

    func load() {
        switch FolderAccess.readAppFile(Self.filename) {
        case .missing:
            flags = []
            loadError = nil
            isLocked = false
        case .contents(let text):
            flags = Self.parse(text)
            loadError = nil
            isLocked = false
        case .failure(let message):
            // Never overwrite a file we failed to read — that would destroy every flag in it.
            flags = []
            loadError = message
            isLocked = true
        }
    }

    func reason(for card: Card?) -> String? {
        guard let card else { return nil }
        return flags.first { $0.id == key(for: card) }?.reason
    }

    func flag(_ card: Card, as reason: FlagReason) {
        guard !isLocked else { reportLocked(); return }
        let previous = flags
        let entry = Flag(setID: card.setID, setTitle: card.setTitle,
                         prompt: card.prompt, answer: card.answer, reason: reason.rawValue)
        if let i = flags.firstIndex(where: { $0.id == entry.id }) {
            flags[i].reason = reason.rawValue
        } else {
            flags.append(entry)
        }
        save(rollingBackTo: previous)
    }

    func unflag(_ card: Card) {
        guard !isLocked else { reportLocked(); return }
        let previous = flags
        flags.removeAll { $0.id == key(for: card) }
        save(rollingBackTo: previous)
    }

    private func key(for card: Card) -> String { "\(card.setID)|\(card.prompt)" }

    private func reportLocked() {
        writeError = "\(Self.filename) couldn't be read, so it won't be overwritten and flagging is paused. \(loadError ?? "")"
    }

    /// The file is the only state, so a failed write must not leave the UI showing a flag
    /// that isn't in it — the card would read as flagged until the next reload silently
    /// reverted it.
    private func save(rollingBackTo previous: [Flag]) {
        do {
            try FolderAccess.writeAppFile(Self.filename, contents: render())
            writeError = nil
        } catch {
            flags = previous
            writeError = error.localizedDescription
        }
    }

    // MARK: - File format

    private func render() -> String {
        var out = [
            "# Flagged Cards",
            "",
            "Cards flagged while studying. Fix each one in its source file, then delete its",
            "line here. The app rewrites this file, so it only keeps the entry lines below.",
            "",
        ]
        let groups = Dictionary(grouping: flags, by: \.setID)
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        for (setID, entries) in groups {
            out.append("## \(entries[0].setTitle) (\(setID))")
            out.append("")
            for entry in entries {
                out.append("- [\(entry.done ? "x" : " ")] **\(entry.reason)** — \(entry.prompt) :: \(entry.answer)")
            }
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    /// Split "Set Title (filename.md)" into its two halves.
    ///
    /// Not at the last bracket: a title may have brackets of its own, and a set called
    /// "Bio (1)" renders as "Bio (1) (Bio (1).md)", which split that way hands back an id of
    /// "1).md" — every flag in that set orphaned, permanently, since the id never matches a
    /// real one again.
    ///
    /// Nor at the first: "1) (Bio (1).md" ends in .md too. What tells the two apart is that
    /// a filename's brackets are balanced and a mid-title fragment's are not. So: the first
    /// candidate that both looks like a set file and reads as one whole.
    static func splitHeading(_ heading: String) -> (title: String, id: String) {
        guard heading.hasSuffix(")") else { return (heading, heading) }
        let body = heading.dropLast()

        func named(_ candidate: String) -> Bool {
            SetFile.allExtensions.contains { candidate.lowercased().hasSuffix(".\($0)") }
        }
        func whole(_ candidate: String) -> Bool {
            var depth = 0
            for character in candidate {
                if character == "(" { depth += 1 }
                if character == ")" { depth -= 1 }
                if depth < 0 { return false }
            }
            return depth == 0
        }

        var from = body.startIndex
        while let open = body[from...].firstIndex(of: "(") {
            let candidate = String(body[body.index(after: open)...])
            if named(candidate), whole(candidate) {
                let title = String(body[..<open]).trimmingCharacters(in: .whitespaces)
                return (title.isEmpty ? candidate : title, candidate)
            }
            from = body.index(after: open)
        }

        // Nothing in the line looks like a set file — a heading someone wrote by hand, say.
        // Read it the old way rather than dropping the group and its flags with it.
        guard let open = body.lastIndex(of: "(") else { return (heading, heading) }
        let id = String(body[body.index(after: open)...])
        let title = String(body[..<open]).trimmingCharacters(in: .whitespaces)
        return (title.isEmpty ? id : title, id)
    }

    private static func parse(_ text: String) -> [Flag] {
        var result: [Flag] = []
        var setID = "", setTitle = ""

        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)

            // "## Set Title (filename.md)"
            if line.hasPrefix("## ") {
                let heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                (setTitle, setID) = splitHeading(heading)
                continue
            }

            if let flag = parseEntry(line, setID: setID, setTitle: setTitle) { result.append(flag) }
        }
        return result
    }

    /// "- [ ] **reason** — prompt :: answer"
    private static func parseEntry(_ line: String, setID: String, setTitle: String) -> Flag? {
        let chars = Array(line)
        guard chars.count > 5, line.hasPrefix("- ["), chars[4] == "]" else { return nil }
        let done = chars[3] == "x" || chars[3] == "X"

        var rest = String(chars[5...]).trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix("**") else { return nil }
        rest = String(rest.dropFirst(2))
        guard let close = rest.range(of: "**") else { return nil }
        let reason = String(rest[..<close.lowerBound]).trimmingCharacters(in: .whitespaces)

        rest = String(rest[close.upperBound...]).trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("—") { rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces) }

        guard let sep = rest.range(of: " :: ") else { return nil }
        let prompt = String(rest[..<sep.lowerBound]).trimmingCharacters(in: .whitespaces)
        let answer = String(rest[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !reason.isEmpty, !prompt.isEmpty else { return nil }

        return Flag(setID: setID, setTitle: setTitle, prompt: prompt, answer: answer,
                    reason: reason, done: done)
    }
}
