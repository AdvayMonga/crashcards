import SwiftUI

/// Shows folder setup until a folder is chosen, then the set list.
/// Re-scans the folder on first appearance and whenever the app returns to the foreground.
struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if library.hasFolders {
                SetListView()
            } else {
                FolderSetupView()
            }
        }
        .task { library.reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.reload() }
        }
    }
}
