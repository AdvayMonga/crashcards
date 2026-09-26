import SwiftUI

/// The three tabs. A folder is optional — the app's own library works on its own — so
/// setup is offered from the Study tab's empty state, not demanded up front.
///
/// Re-scans on first appearance and whenever the app returns to the foreground. Two things
/// can interrupt that arrival: arriving while blocked, which shows the questions and hands
/// you back to the app you were opening; and text waiting from the share extension, which
/// opens the importer.
///
/// Nothing here is a `TabView`, a sheet or an alert: the tabs cross-fade rather than slide,
/// and everything that covers the screen is a layer in this one `ZStack`.
struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(FlagStore.self) private var flags
    @Environment(ScreenTimeManager.self) private var blocking
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = Tab.study
    @State private var prompt: GatePrompt?
    @State private var share: PendingShare?
    @State private var collectedShareFile: URL?

    /// A request to show the questions: from the shield's Answer button, which knows the app
    /// you tapped, or from arriving while shielded some other way, which knows nothing. One
    /// piece of state for both, so they can't race to present over each other on the same
    /// foreground.
    private struct GatePrompt: Identifiable {
        let id = UUID()
        var tapped: PendingGate?
    }

    private struct PendingShare: Identifiable {
        let id = UUID()
        let text: String
        let title: String
    }

    private enum Tab: Hashable { case study, focus, settings }

    var body: some View {
        ZStack {
            TableBackground()

            tabs
                .safeAreaInset(edge: .bottom) { tabBar }

            if let request = prompt {
                UnlockView(cards: library.gateCards, manager: blocking,
                           tapped: request.tapped) {
                    prompt = nil
                }
                .transition(.dealIn)
                .zIndex(2)
            }

            if let pending = share {
                ImportSetView(initialText: pending.text, initialTitle: pending.title,
                              onClose: finishShare) {
                    library.reload()
                }
                .environment(library)
                .zIndex(3)
            }

            if let message = flags.writeError {
                CrashAlert(title: "Couldn't write \(FlagStore.filename)",
                           message: message) { flags.writeError = nil }
                    .zIndex(4)
            }
        }
        .animation(Motion.deal, value: prompt?.id)
        .animation(Motion.deal, value: share?.id)
        .animation(Motion.pop, value: flags.writeError)
        .task {
            StarterDecks.seedIfNeeded()   // before the first scan, so they appear on launch
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

    /// Tabs cross-fade in place. A horizontal slide between them is the stock motion this
    /// app is trying not to have.
    @ViewBuilder private var tabs: some View {
        ZStack {
            switch tab {
            case .study: SetListView()
            case .focus: FocusView()
            case .settings: SettingsView()
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .animation(Motion.snap, value: tab)
    }

    private var tabBar: some View {
        CrashTabBar(tabs: [(.study, .cards, "Study"),
                           (.focus, .lockClosed, "Focus"),
                           (.settings, .gear, "Settings")],
                    selection: $tab)
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
        share = nil
        collectShare()
    }

    /// Arriving while blocked usually means you just tried to open a blocked app — and if
    /// you came through the shield's Answer button, the extension left a note of which one.
    private func offerUnlock() {
        guard prompt == nil, share == nil,
              blocking.isShieldActive, !library.gateCards.isEmpty else { return }
        tab = .focus
        prompt = GatePrompt(tapped: BlockingShared.takePendingGate())
    }
}
