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

    /// Cards the unlock quiz draws from: your selected sets, or everything if none are selected.
    var quizCards: [Card] {
        let selected = sets.filter { Prefs.selectedSetIDs.contains($0.id) }
        return (selected.isEmpty ? sets : selected).flatMap(\.cards)
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

    func removeFolder(at index: Int) {
        FolderAccess.removeFolder(at: index)
        reload()
    }
}
