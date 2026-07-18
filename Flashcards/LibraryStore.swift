import Foundation
import Observation

/// Holds the parsed sets in memory. Re-scans the folders on demand (app launch/foreground).
@Observable
final class LibraryStore {
    private(set) var sets: [FlashcardSet] = []
    var loadError: String?

    var hasFolders: Bool { FolderAccess.hasFolders }
    var folders: [AttachedFolder] { FolderAccess.folders }

    /// Re-read and parse all attached folders. No-op (empties) if none are set.
    func reload() {
        guard FolderAccess.hasFolders else {
            sets = []
            loadError = nil
            return
        }
        do {
            sets = try FolderAccess.loadSets()
            loadError = nil
        } catch {
            sets = []
            loadError = error.localizedDescription
        }
    }

    func addFolder(_ url: URL) {
        do {
            try FolderAccess.addFolder(url)
            reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func removeFolder(at index: Int) {
        FolderAccess.removeFolder(at: index)
        reload()
    }
}
