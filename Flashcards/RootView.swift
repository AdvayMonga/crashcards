import SwiftUI

/// Shows folder setup until a folder is chosen, then the three tabs.
/// Re-scans the folders on first appearance and whenever the app returns to the foreground.
/// A `flashcards://gate?app=…` link — sent by a Shortcuts automation when you open a gated
/// app — goes straight to the questions, and back to that app once you've answered them.
struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(FlagStore.self) private var flags
    @Environment(ScreenTimeManager.self) private var blocking
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var tab = Tab.study
    @State private var unlocking = false
    @State private var gateTarget: GatedApp?

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
        .onOpenURL { url in
            guard let app = GatedApps.target(of: url) else { return }
            openGate(for: app)
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
        .fullScreenCover(item: $gateTarget) { app in
            NavigationStack {
                UnlockView(cards: library.quizCards, manager: blocking, target: app)
            }
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
        guard gateTarget == nil, blocking.isShieldActive, !library.quizCards.isEmpty else { return }
        tab = .focus
        unlocking = true
    }

    /// Inside an unlock window there's nothing to earn, so pass straight through.
    private func openGate(for app: GatedApp) {
        unlocking = false
        guard !blocking.isUnlockedNow, let url = app.returnURL else {
            gateTarget = app
            return
        }
        openURL(url) { opened in if !opened { gateTarget = app } }
    }
}
