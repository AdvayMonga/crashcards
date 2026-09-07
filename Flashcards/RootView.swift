import SwiftUI

/// Shows folder setup until a folder is chosen, then the set list.
/// Re-scans the folder on first appearance and whenever the app returns to the foreground.
struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(FlagStore.self) private var flags
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if library.hasFolders {
                SetListView()
            } else {
                FolderSetupView()
            }
        }
        .task { reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload() }
        }
    }

    /// Re-read the folders and Flagged.md, so edits made in Obsidian show up here.
    private func reload() {
        library.reload()
        flags.load()
    }
}
