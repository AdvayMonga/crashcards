import Foundation

enum FolderError: LocalizedError {
    case noFolder
    var errorDescription: String? {
        switch self {
        case .noFolder: return "No flashcards folder has been chosen yet."
        }
    }
}

/// A folder the user has attached, for display in Settings. `id` is its bookmark index.
struct AttachedFolder: Identifiable, Hashable {
    let id: Int
    let name: String
}

/// Persistent, sandbox-safe access to the user-picked flashcards folders.
///
/// The user can attach several folders (each stored as a security-scoped bookmark); the app
/// reads every `.md` under each one, recursively. No paths are hardcoded.
enum FolderAccess {
    private static let bookmarksKey = "flashcardsFolderBookmarks"
    private static var defaults: UserDefaults { .standard }

    private static func bookmarks() -> [Data] {
        defaults.array(forKey: bookmarksKey) as? [Data] ?? []
    }
    private static func saveBookmarks(_ list: [Data]) {
        defaults.set(list, forKey: bookmarksKey)
    }

    static var hasFolders: Bool { !bookmarks().isEmpty }

    /// Attached folders for display, skipping any that no longer resolve.
    static var folders: [AttachedFolder] {
        bookmarks().enumerated().compactMap { index, data in
            guard let url = try? resolve(data) else { return nil }
            return AttachedFolder(id: index, name: url.lastPathComponent)
        }
    }

    /// Attach a folder the user just picked (ignores exact duplicates).
    static func addFolder(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData()

        var list = bookmarks()
        let newPath = url.standardizedFileURL.path
        let existing = list.compactMap { try? resolve($0).standardizedFileURL.path }
        guard !existing.contains(newPath) else { return }
        list.append(data)
        saveBookmarks(list)
    }

    static func removeFolder(at index: Int) {
        var list = bookmarks()
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        saveBookmarks(list)
    }

    /// Read + parse every `.md` under every attached folder (recursively), sorted by title.
    static func loadSets() throws -> [FlashcardSet] {
        var list = bookmarks()
        guard !list.isEmpty else { throw FolderError.noFolder }

        var sets: [FlashcardSet] = []
        var seenIDs = Set<String>()
        var changed = false

        for i in list.indices {
            var stale = false
            guard let folder = try? URL(resolvingBookmarkData: list[i], bookmarkDataIsStale: &stale)
            else { continue }
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            if stale, let fresh = try? folder.bookmarkData() { list[i] = fresh; changed = true }

            for url in markdownFiles(in: folder) {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let parsed = MarkdownParser.parse(text, filename: url.lastPathComponent)
                guard !parsed.cards.isEmpty else { continue }
                sets.append(uniquelyIdentified(parsed, seen: &seenIDs))
            }
        }

        if changed { saveBookmarks(list) }
        return sets.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Helpers

    /// Filenames can collide across folders; give each set a unique id.
    private static func uniquelyIdentified(_ set: FlashcardSet, seen: inout Set<String>) -> FlashcardSet {
        var uid = set.id
        var n = 2
        while seen.contains(uid) { uid = "\(set.id) (\(n))"; n += 1 }
        seen.insert(uid)
        guard uid != set.id else { return set }
        return FlashcardSet(id: uid, title: set.title, cards: set.cards)
    }

    private static func markdownFiles(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
            result.append(url)
        }
        return result
    }

    private static func resolve(_ data: Data) throws -> URL {
        var stale = false
        return try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
    }
}
