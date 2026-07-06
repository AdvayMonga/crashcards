import Foundation
import Observation

/// Holds the parsed sets in memory. Re-scans the folder on demand (app launch/foreground).
@Observable
final class LibraryStore {
    private(set) var sets: [FlashcardSet] = []
    var loadError: String?

    var hasFolder: Bool { FolderAccess.hasFolder }

    /// Re-read and parse the chosen folder. No-op (empties) if no folder is set.
    func reload() {
        guard FolderAccess.hasFolder else {
            sets = []
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

    func setFolder(_ url: URL) {
        do {
            try FolderAccess.setFolder(url)
            reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func clearFolder() {
        FolderAccess.clearFolder()
        sets = []
        loadError = nil
    }
}
