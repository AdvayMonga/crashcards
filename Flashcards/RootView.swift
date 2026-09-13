import SwiftUI

/// The three tabs. A folder is optional — the app's own library works on its own — so
/// setup is offered from the Study tab's empty state, not demanded up front.
///
/// Re-scans on first appearance and whenever the app returns to the foreground. Two things
/// can interrupt that arrival: a `flashcards://gate?app=…` link (a Shortcuts automation
/// reacting to you opening a blocked app), which shows the questions and hands you back to
/// that app; and text waiting from the share extension, which opens the importer.
struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(FlagStore.self) private var flags
    @Environment(ScreenTimeManager.self) private var blocking
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var tab = Tab.study
    @State private var prompt: GatePrompt?
    @State private var share: PendingShare?
    @State private var collectedShareFile: URL?

    /// A request to show the questions: from a gate link, which has an app to return to,
    /// or from arriving while shielded, which doesn't. One piece of state for both, so the
    /// two can't race to present over each other on the same foreground.
    private struct GatePrompt: Identifiable {
        let id = UUID()
        var target: GatedApp?
    }

    private struct PendingShare: Identifiable {
        let id = UUID()
        let text: String
        let title: String
    }

    private enum Tab { case study, focus, settings }

    var body: some View {
        tabs
            .task {
                reload()
                collectShare()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    reload()
                    collectShare()
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
            .sheet(item: $share, onDismiss: finishShare) { pending in
                ImportSetView(initialText: pending.text, initialTitle: pending.title) {
                    library.reload()
                }
                .environment(library)
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

    /// A share waiting from the extension becomes an import, preview and all.
    private func collectShare() {
        guard share == nil, prompt == nil, let waiting = SharedInbox.next() else { return }
        collectedShareFile = waiting.url
        share = PendingShare(text: waiting.text, title: waiting.title)
    }

    /// Whether it was imported or abandoned, a share is consumed once it's been shown —
    /// then anything queued behind it comes up.
    private func finishShare() {
        if let collectedShareFile { SharedInbox.clear(collectedShareFile) }
        collectedShareFile = nil
        collectShare()
    }

    /// Arriving while blocked usually means you just tried to open a blocked app.
    private func offerUnlock() {
        guard prompt == nil, share == nil,
              blocking.isShieldActive, !library.quizCards.isEmpty else { return }
        tab = .focus
        prompt = GatePrompt(target: nil)
    }

    /// Inside an unlock window there's nothing left to earn, so hand the user straight on.
    private func openGate(for app: GatedApp?) {
        // Mid-import: don't swap a sheet for a cover in one update, which drops the cover.
        // Nothing is lost — the shield is still up, and Focus has the same questions.
        guard share == nil else { return }

        guard blocking.isUnlockedNow else {
            prompt = GatePrompt(target: app)
            return
        }
        guard let app, let url = app.returnURL, !GatedApps.justRedirected(to: app) else { return }
        GatedApps.recordRedirect(to: app)
        openURL(url) { opened in if !opened { prompt = GatePrompt(target: app) } }
    }
}
