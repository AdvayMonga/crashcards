import Foundation

/// Sets kept inside the app, for people who don't want to manage files at all.
///
/// Always available — no folder, no Files app, no iCloud. Imported and pasted sets land
/// here when no folder is attached, written as the same `.md` the folder scanner reads,
/// so nothing is trapped in a private database.
enum LocalLibrary {
    /// Documents/Sets, created on first use. Visible in Files when the app is file-sharing.
    static var directory: URL {
        let url = URL.documentsDirectory.appendingPathComponent("Sets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func files() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ).filter { SetFile.canRead($0) }
    }

    /// Save a new set, never overwriting: a clashing name gets a numbered suffix.
    @discardableResult
    static func save(_ contents: String, named title: String) throws -> URL {
        let url = uniqueURL(for: title)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Delete a set the app owns.
    static func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    /// Rename a set: retitle its heading and move it to a matching filename.
    ///
    /// Both halves matter — the displayed title comes from the `# Heading` when there is
    /// one and from the filename otherwise, so changing only one of them would leave the
    /// name looking unchanged.
    @discardableResult
    static func rename(_ url: URL, to newTitle: String) throws -> URL {
        let body = retitled(try String(contentsOf: url, encoding: .utf8), to: newTitle)
        let base = SetFile.filename(from: newTitle)
        var destination = directory.appendingPathComponent("\(base).md")
        var n = 2
        while destination != url, FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(base) \(n).md")
            n += 1
        }
        try body.write(to: destination, atomically: true, encoding: .utf8)
        if destination != url { try FileManager.default.removeItem(at: url) }
        return destination
    }

    /// Replace the first ATX heading, or add one when the file has none. These are files
    /// the app wrote itself, so there is no frontmatter to step around.
    private static func retitled(_ text: String, to title: String) -> String {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard let i = lines.firstIndex(where: {
            let line = $0.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#") else { return false }
            let rest = line.drop { $0 == "#" }
            return rest.isEmpty || rest.first == " "
        }) else {
            return "# \(title)\n\n" + text
        }
        lines[i] = "# \(title)"
        return lines.joined(separator: "\n")
    }

    /// A filename derived from the title, with a numbered suffix if it's taken.
    private static func uniqueURL(for title: String) -> URL {
        let base = SetFile.filename(from: title)
        var candidate = directory.appendingPathComponent("\(base).md")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(n).md")
            n += 1
        }
        return candidate
    }
}

/// The file types a set can be stored as, and which parser reads each.
enum SetFile {
    /// Plain-text formats read with the markdown card syntax.
    static let textExtensions = ["md", "markdown", "txt", "text"]
    /// Spreadsheet exports — Quizlet, Google Sheets, Excel.
    static let tableExtensions = ["csv", "tsv"]

    static var allExtensions: [String] { textExtensions + tableExtensions }

    static func canRead(_ url: URL) -> Bool {
        allExtensions.contains(url.pathExtension.lowercased())
    }

    /// A set's name from its filename, without the extension.
    static func title(from filename: String) -> String {
        URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
    }

    /// A filename base safe to write: no path separators, and no leading dot — a dotfile
    /// would save without error and then never appear, since scans skip hidden files.
    static func filename(from title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = cleaned.drop { $0 == "." }.trimmingCharacters(in: .whitespaces)
        return visible.isEmpty ? "Set" : String(visible.prefix(60))
    }

    /// Parse a file's text according to its extension.
    static func parse(_ text: String, filename: String) -> ParsedFile {
        let ext = (filename as NSString).pathExtension.lowercased()
        if tableExtensions.contains(ext) {
            return DelimitedParser.parse(text, filename: filename)
        }
        return MarkdownParser.parse(text, filename: filename)
    }
}


extension FlashcardSet {
    /// Sets in the app's own library — the only ones it may rename or delete. A file in a
    /// folder you attached is yours, and the app never edits those.
    var isLocal: Bool {
        guard let fileURL else { return false }
        let home = LocalLibrary.directory.standardizedFileURL.path
        return fileURL.standardizedFileURL.path.hasPrefix(home.hasSuffix("/") ? home : home + "/")
    }
}
