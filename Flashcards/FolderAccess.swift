import Foundation

enum FolderError: LocalizedError {
    case noFolder
    var errorDescription: String? {
        switch self {
        case .noFolder: return "No flashcards folder has been chosen yet."
        }
    }
}

/// Persistent, sandbox-safe access to the user-picked flashcards folder.
///
/// iOS hands out a security-scoped URL from the Files picker; we store a bookmark so the
/// same folder stays readable across launches. No paths are ever hardcoded — the folder is
/// whatever the user chose.
enum FolderAccess {
    private static let bookmarkKey = "flashcardsFolderBookmark"
    private static var defaults: UserDefaults { .standard }

    static var hasFolder: Bool { defaults.data(forKey: bookmarkKey) != nil }

    /// Human-readable name of the chosen folder, for display in Settings.
    static var folderName: String? {
        (try? resolveFolder())?.lastPathComponent
    }

    /// Save a bookmark for a folder the user just picked.
    static func setFolder(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData()
        defaults.set(data, forKey: bookmarkKey)
    }

    static func clearFolder() {
        defaults.removeObject(forKey: bookmarkKey)
    }

    /// Read and parse every `.md` file in the chosen folder, sorted by title.
    static func loadSets() throws -> [FlashcardSet] {
        let folder = try resolveFolder()
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let contents = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )
        let mdFiles = contents.filter { $0.pathExtension.lowercased() == "md" }

        let sets = mdFiles.compactMap { url -> FlashcardSet? in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let set = MarkdownParser.parse(text, filename: url.lastPathComponent)
            return set.cards.isEmpty ? nil : set
        }
        return sets.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Resolve the saved bookmark to a live URL, refreshing it if the OS marks it stale.
    private static func resolveFolder() throws -> URL {
        guard let data = defaults.data(forKey: bookmarkKey) else { throw FolderError.noFolder }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
        if stale { try? setFolder(url) }
        return url
    }
}
