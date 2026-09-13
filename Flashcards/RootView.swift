import SwiftUI

/// The three tabs. A folder is optional — the app's own library works on its own — so
/// setup is offered from the Study tab's empty state, not demanded up front.
/// Re-scans the folders on first appearance and whenever the app returns to the foreground —
/// and if apps are shielded when you arrive, puts the unlock questions in front of you.
struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(FlagStore.self) private var flags
    @Environment(ScreenTimeManager.self) private var blocking
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = Tab.study
    @State private var unlocking = false
    @State private var shared: (text: String, title: String, url: URL)?

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
        .sheet(isPresented: .init(get: { shared != nil }, set: { if !$0 { finishShare() } })) {
            if let shared {
                ImportSetView(initialText: shared.text, initialTitle: shared.title) {
                    library.reload()
                }
                .environment(library)
            }
        }
    }

    /// A share waiting from the extension becomes an import, preview and all.
    private func collectShare() {
        guard shared == nil, let waiting = SharedInbox.next() else { return }
        unlocking = false   // one sheet at a time; the questions can wait
        shared = waiting
        tab = .study
    }

    /// Whether it was imported or abandoned, the share is consumed once it's been shown —
    /// then the next one queued behind it comes up.
    private func finishShare() {
        if let shared { SharedInbox.clear(shared.url) }
        shared = nil
        collectShare()
    }

    /// Re-read the folders and Flagged.md, so edits made in Obsidian show up here.
    /// Also expires a finished unlock window, in case the monitor extension hasn't fired.
    private func reload() {
        library.reload()
        flags.load()
        blocking.refresh()
    }

    /// Arriving while blocked usually means you just tried to open a blocked app. Skipped
    /// while a share is up: two sheets on the same view can't both present.
    private func offerUnlock() {
        guard shared == nil, blocking.isShieldActive, !library.quizCards.isEmpty else { return }
        tab = .focus
        unlocking = true
    }
}
