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

    static var isEmpty: Bool { (try? files().isEmpty) ?? true }

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

    static func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    /// A filename derived from the title, with a numbered suffix if it's taken.
    private static func uniqueURL(for title: String) -> URL {
        let base = sanitized(title)
        var candidate = directory.appendingPathComponent("\(base).md")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(n).md")
            n += 1
        }
        return candidate
    }

    private static func sanitized(_ title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Set" : String(cleaned.prefix(60))
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

    /// Parse a file's text according to its extension.
    static func parse(_ text: String, filename: String) -> ParsedFile {
        let ext = (filename as NSString).pathExtension.lowercased()
        if tableExtensions.contains(ext) {
            return DelimitedParser.parse(text, filename: filename)
        }
        return MarkdownParser.parse(text, filename: filename)
    }
}
