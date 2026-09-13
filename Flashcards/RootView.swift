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
    @State private var prompt: GatePrompt?

    /// A request to show the questions: from a gate link, which has an app to return to,
    /// or from arriving while shielded, which doesn't. One piece of state for both, so the
    /// two can't race to present over each other on the same foreground.
    private struct GatePrompt: Identifiable {
        let id = UUID()
        var target: GatedApp?
    }

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
            guard GatedApps.isGate(url) else { return }
            openGate(for: GatedApps.target(of: url))
        }
        .fullScreenCover(item: $prompt) { request in
            NavigationStack {
                UnlockView(cards: library.quizCards, manager: blocking, target: request.target)
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
        guard prompt == nil, blocking.isShieldActive, !library.quizCards.isEmpty else { return }
        tab = .focus
        prompt = GatePrompt(target: nil)
    }

    /// Inside an unlock window there's nothing left to earn, so hand the user straight on.
    private func openGate(for app: GatedApp?) {
        guard blocking.isUnlockedNow else {
            prompt = GatePrompt(target: app)
            return
        }
        guard let app, let url = app.returnURL, !GatedApps.justRedirected(to: app) else { return }
        GatedApps.recordRedirect(to: app)
        openURL(url) { opened in if !opened { prompt = GatePrompt(target: app) } }
    }
}
