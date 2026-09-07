import SwiftUI

/// Shows folder setup until a folder is chosen, then the three tabs.
/// Re-scans the folders on first appearance and whenever the app returns to the foreground —
/// and if apps are shielded when you arrive, puts the unlock questions in front of you.
struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(FlagStore.self) private var flags
    @Environment(ScreenTimeManager.self) private var blocking
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = Tab.study
    @State private var unlocking = false

    private enum Tab { case study, focus, settings }

    var body: some View {
        Group {
            if library.hasFolders {
                tabs
            } else {
                FolderSetupView()
            }
        }
        .task { reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                reload()
                offerUnlock()
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            SetListView()
                .tabItem { Label("Study", systemImage: "rectangle.on.rectangle") }
                .tag(Tab.study)
            FocusView()
                .tabItem { Label("Focus", systemImage: "lock") }
                .tag(Tab.focus)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .sheet(isPresented: $unlocking) {
            NavigationStack { UnlockView(cards: library.quizCards, manager: blocking) }
        }
    }

    /// Re-read the folders and Flagged.md, so edits made in Obsidian show up here.
    /// Also expires a finished unlock window, in case the monitor extension hasn't fired.
    private func reload() {
        library.reload()
        flags.load()
        blocking.refresh()
    }

    /// Arriving while blocked usually means you just tried to open a blocked app.
    private func offerUnlock() {
        guard blocking.isShieldActive, !library.quizCards.isEmpty else { return }
        tab = .focus
        unlocking = true
    }
}
