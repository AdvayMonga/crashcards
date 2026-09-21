import Foundation

enum FolderError: LocalizedError {
    case noFolder
    case primaryUnavailable
    case duplicateFolder
    case nestedFolder
    case notAppFile(String)

    var errorDescription: String? {
        switch self {
        case .noFolder:
            return "No flashcards folder has been chosen yet."
        case .primaryUnavailable:
            return "Your first flashcards folder isn't available right now, so \(FlagStore.filename) can't be read or written. It may be offline in iCloud, moved, or deleted — check it in Settings."
        case .duplicateFolder:
            return "That folder is already attached."
        case .nestedFolder:
            return "That folder overlaps one you've already added, so every set inside it would load twice."
        case .notAppFile(let name):
            return "Crash Cards only ever writes \(FlagStore.filename); it refused to write “\(name)”."
        }
    }
}

/// A folder the user has attached, for display in Settings. `id` is its bookmark index.
struct AttachedFolder: Identifiable, Hashable {
    let id: Int
    let name: String
}

/// Problems found in one file. Reported to the user; the file is never modified.
struct FileIssues: Identifiable, Hashable {
    let id: String        // path shown to the user, unique per file
    let filename: String
    let issues: [ParseIssue]
}

/// Everything a folder scan produced: the sets, plus what went wrong along the way.
struct LibraryLoad {
    var sets: [FlashcardSet] = []
    var fileIssues: [FileIssues] = []
    var folderErrors: [String] = []
}

/// The result of reading a file the app owns, keeping "not there yet" distinct from
/// "there but unreadable" — overwriting the latter would destroy the user's data.
enum AppFileRead {
    case missing
    case contents(String)
    case failure(String)
}

/// Persistent, sandbox-safe access to the user-picked flashcards folders.
///
/// The user can attach several folders (each stored as a security-scoped bookmark); the app
/// reads every set file under each one, recursively. No paths are hardcoded. The app's own
/// local library is always scanned too, so no folder is required to use the app.
///
/// Read-only by design: the *only* file this app ever writes is `Flagged.md`, in the first
/// attached folder — or in the local library when no folder is attached, so flagging works
/// on the folderless path too. `writeAppFile` refuses anything else, so a source deck can
/// never be modified by the app.
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

    /// Attached folders for display. Ones that no longer resolve are still listed — under a
    /// placeholder name — so the user can remove them instead of wondering where they went.
    static var folders: [AttachedFolder] {
        bookmarks().enumerated().map { index, data in
            let name = (try? resolve(data))?.lastPathComponent ?? "Unavailable folder"
            return AttachedFolder(id: index, name: name)
        }
    }

    /// Attach a folder the user just picked.
    static func addFolder(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let newPath = url.standardizedFileURL.path
        let existing = bookmarks().compactMap { try? resolve($0).standardizedFileURL.path }
        guard !existing.contains(newPath) else { throw FolderError.duplicateFolder }
        guard !existing.contains(where: { contains($0, newPath) || contains(newPath, $0) })
        else { throw FolderError.nestedFolder }

        let data = try url.bookmarkData()
        saveBookmarks(bookmarks() + [data])
    }

    static func removeFolder(at index: Int) {
        var list = bookmarks()
        guard list.indices.contains(index) else { return }
        list.remove(at: index)
        saveBookmarks(list)
    }

    /// Read + parse every set file in the local library and under every attached folder
    /// (recursively), sorted by title. Files and folders that fail are reported in the
    /// result, never skipped silently.
    static func loadSets() throws -> LibraryLoad {
        var list = bookmarks()

        var load = LibraryLoad()
        var seenIDs = Set<String>()
        var changed = false

        // The app's own sets, always present and needing no permission.
        if let local = try? LocalLibrary.files() {
            for url in local { read(url, into: &load, seen: &seenIDs) }
        }

        for i in list.indices {
            var stale = false
            guard let folder = try? URL(resolvingBookmarkData: list[i], bookmarkDataIsStale: &stale)
            else {
                load.folderErrors.append(
                    "Folder \(i + 1) couldn't be opened. It may have been moved, deleted, or not yet downloaded from iCloud. Remove and re-add it in Settings."
                )
                continue
            }
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            if stale, let fresh = try? folder.bookmarkData() { list[i] = fresh; changed = true }

            guard let files = markdownFiles(in: folder) else {
                load.folderErrors.append("Couldn't list the contents of “\(folder.lastPathComponent)”.")
                continue
            }
            if files.isEmpty && !scoped {
                load.folderErrors.append(
                    "Permission to read “\(folder.lastPathComponent)” was lost. Remove and re-add it in Settings."
                )
                continue
            }

            for url in files { read(url, into: &load, seen: &seenIDs) }
        }

        if changed { saveBookmarks(list) }
        load.sets.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        load.fileIssues.sort { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }
        return load
    }

    // MARK: - Helpers

    /// Parse one set file into the load, recording why it failed instead of dropping it.
    private static func read(_ url: URL, into load: inout LibraryLoad, seen: inout Set<String>) {
        let name = url.lastPathComponent
        guard let text = readText(at: url) else {
            load.fileIssues.append(FileIssues(
                id: url.path, filename: name,
                issues: [ParseIssue(line: 0, kind: .notText, excerpt: "")]
            ))
            return
        }
        let parsed = SetFile.parse(text, filename: name)
        if !parsed.issues.isEmpty {
            load.fileIssues.append(FileIssues(id: url.path, filename: name, issues: parsed.issues))
        }
        guard !parsed.set.cards.isEmpty else { return }
        load.sets.append(uniquelyIdentified(parsed.set, seen: &seen))
    }

    /// Is `path` inside directory `parent`?
    private static func contains(_ parent: String, _ path: String) -> Bool {
        path.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/")
    }

    /// UTF-8, falling back to whatever encoding the file declares. nil if it isn't text.
    private static func readText(at url: URL) -> String? {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        var encoding: String.Encoding = .utf8
        return try? String(contentsOf: url, usedEncoding: &encoding)
    }

    /// Filenames can collide across folders; give each set a unique id.
    private static func uniquelyIdentified(_ set: FlashcardSet, seen: inout Set<String>) -> FlashcardSet {
        var uid = set.id
        var n = 2
        while seen.contains(uid) { uid = "\(set.id) (\(n))"; n += 1 }
        seen.insert(uid)
        guard uid != set.id else { return set }
        return FlashcardSet(id: uid, title: set.title, cards: set.cards)
    }

    /// Every readable set file under `folder`, or nil if the folder can't be enumerated.
    private static func markdownFiles(in folder: URL) -> [URL]? {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return nil }

        var result: [URL] = []
        for case let url as URL in enumerator where SetFile.canRead(url) {
            // A directory named "foo.md" is not a deck.
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            // The app writes Flagged.md itself; don't read it back in as a set.
            guard url.lastPathComponent.caseInsensitiveCompare(FlagStore.filename) != .orderedSame
            else { continue }
            result.append(url)
        }
        return result
    }

    // MARK: - App-written files

    /// The first attached folder. Deliberately *not* "the first one that resolves": app files
    /// must always live in the same place, so an offline folder is an error, not a silent move.
    private static func primaryFolder() throws -> URL {
        guard let data = bookmarks().first else { throw FolderError.noFolder }
        guard let url = try? resolve(data) else { throw FolderError.primaryUnavailable }
        return url
    }

    /// Where the app's own files live: the first attached folder, or the local library when
    /// there isn't one. A folder is optional everywhere else in the app, so app files can't
    /// require one either.
    private static func appFileFolder() throws -> URL {
        bookmarks().isEmpty ? LocalLibrary.directory : try primaryFolder()
    }

    /// Read a file the app owns.
    static func readAppFile(_ name: String) -> AppFileRead {
        let folder: URL
        do {
            folder = try appFileFolder()
        } catch {
            return .failure(error.localizedDescription)
        }

        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let url = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            return .contents(try String(contentsOf: url, encoding: .utf8))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Write a file the app owns, atomically.
    ///
    /// Writes to a hidden temp file first and swaps it in, so a failure part-way through
    /// leaves the existing file intact rather than truncated.
    static func writeAppFile(_ name: String, contents: String) throws {
        // The single point where this app can modify the user's folder. Keep it to one file.
        guard name == FlagStore.filename else { throw FolderError.notAppFile(name) }

        let folder = try appFileFolder()
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let target = folder.appendingPathComponent(name)
        let temp = folder.appendingPathComponent(".\(name).tmp")
        try contents.write(to: temp, atomically: false, encoding: .utf8)
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: target)
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    /// Create a *new* set file in the primary folder. Never overwrites: a clashing name
    /// gets a numbered suffix, so an import can't clobber a deck you already had.
    @discardableResult
    static func createSetFile(named title: String, contents: String) throws -> URL {
        let folder = try primaryFolder()
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let name = SetFile.filename(from: title)
        var url = folder.appendingPathComponent("\(name).md")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(name) \(n).md")
            n += 1
        }
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func resolve(_ data: Data) throws -> URL {
        var stale = false
        return try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
    }
}
