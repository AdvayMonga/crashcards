import Foundation
import Observation

/// Holds the parsed sets in memory. Re-scans the folders on demand (app launch/foreground).
@Observable
final class LibraryStore {
    private(set) var sets: [FlashcardSet] = []
    /// Per-file format problems from the last scan. Reported only — files are never edited.
    private(set) var fileIssues: [FileIssues] = []
    /// Folders that couldn't be opened or listed.
    private(set) var folderErrors: [String] = []
    /// Set when the scan couldn't run at all.
    var loadError: String?
    /// Set when attaching a folder failed.
    var importError: String?

    var hasFolders: Bool { FolderAccess.hasFolders }

    /// Cards the unlock gate draws from. Its own choice, kept on the Focus tab, so studying
    /// one set doesn't silently change what you're asked to get your apps back.
    var gateCards: [Card] {
        cards(in: Prefs.gateSetIDs)
    }


    /// An empty choice means everything — a selection nobody has made yet shouldn't read
    /// as a selection of nothing.
    private func cards(in ids: Set<String>) -> [Card] {
        let picked = sets.filter { ids.contains($0.id) }
        return (picked.isEmpty ? sets : picked).flatMap(\.cards)
    }
    var folders: [AttachedFolder] { FolderAccess.folders }

    var issueCount: Int {
        folderErrors.count + fileIssues.reduce(0) { $0 + $1.issues.count }
    }

    /// Re-read and parse the local library and every attached folder.
    func reload() {
        do {
            let load = try FolderAccess.loadSets()
            sets = load.sets
            fileIssues = load.fileIssues
            folderErrors = load.folderErrors
            loadError = nil
        } catch {
            sets = []
            fileIssues = []
            folderErrors = []
            loadError = error.localizedDescription
        }
    }

    func addFolder(_ url: URL) {
        do {
            try FolderAccess.addFolder(url)
            importError = nil
            reload()
        } catch {
            importError = error.localizedDescription
        }
    }

    /// The system file picker itself failed (cancelled-with-error, permission denied, …).
    func importFailed(_ error: Error) {
        importError = error.localizedDescription
    }

    /// Delete a set the app owns. Sets read from an attached folder are never touched.
    func deleteSet(_ set: FlashcardSet) {
        guard set.isLocal, let url = set.fileURL else { return }
        do {
            try LocalLibrary.delete(url)
            reload()
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Rename a set the app owns.
    func renameSet(_ set: FlashcardSet, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard set.isLocal, let url = set.fileURL, !trimmed.isEmpty else { return }
        do {
            try LocalLibrary.rename(url, to: trimmed)
            reload()
        } catch {
            importError = error.localizedDescription
        }
    }

    func removeFolder(at index: Int) {
        FolderAccess.removeFolder(at: index)
        reload()
    }
}
