import SwiftUI
import FamilyControls
import ManagedSettings

/// What the shield covers. Its own screen, because the list is as long as you've made it and
/// the Focus tab only needs to say how many.
///
/// The rows are `Label`s over Screen Time tokens, which FamilyControls draws itself — the app
/// never learns which apps you picked, so an app's own icon and name is the only thing there
/// is to show. Changing the list means the system picker; there is no other way in.
struct BlockedAppsView: View {
    @Environment(ScreenTimeManager.self) private var manager
    let onClose: () -> Void

    @State private var pickerShown = false

    private var apps: [ApplicationToken] { Array(manager.selection.applicationTokens) }
    private var categories: [ActivityCategoryToken] { Array(manager.selection.categoryTokens) }

    var body: some View {
        ZStack {
            TableBackground()

            if !manager.hasSelection {
                EmptyState(glyph: .lockOpen,
                           title: "Nothing blocked yet",
                           message: "Pick the apps the shield should cover.") {
                    Button("Choose apps") { choose() }
                        .buttonStyle(CrashButton(fullWidth: false))
                    Button("Back") { onClose() }
                        .buttonStyle(CrashButton(kind: .ghost, tint: Brand.inkDim, fullWidth: false))
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        if !categories.isEmpty {
                            Panel(title: categories.count == 1 ? "1 category" : "\(categories.count) categories") {
                                ForEach(Array(categories.enumerated()), id: \.element) { index, token in
                                    PanelRow(first: index == 0) {
                                        Label(token)
                                            .font(.reading(15))
                                            .foregroundStyle(Brand.ink)
                                    }
                                }
                            }
                        }
                        if !apps.isEmpty {
                            Panel(title: apps.count == 1 ? "1 app" : "\(apps.count) apps") {
                                ForEach(Array(apps.enumerated()), id: \.element) { index, token in
                                    PanelRow(first: index == 0) {
                                        Label(token)
                                            .font(.reading(15))
                                            .foregroundStyle(Brand.ink)
                                    }
                                }
                            }
                        }
                        Button("Change apps") { choose() }
                            .buttonStyle(.soft)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.top, 4, for: .scrollContent)
            }
        }
        .safeAreaInset(edge: .top) {
            ScreenHeader(title: "Blocked apps") {
                HeaderChip(glyph: .close, name: "Done") { onClose() }
            }
        }
        .familyActivityPicker(isPresented: $pickerShown, selection: pickerBinding)
        .onTable()
    }

    /// The picker renders empty without authorization, so it is asked for on the way in.
    private func choose() {
        Haptics.tap()
        Task {
            if !manager.isAuthorized { await manager.requestAuthorization() }
            guard manager.isAuthorized else { return }
            pickerShown = true
        }
    }

    /// Saved on every edit, so an active shield follows the picker rather than waiting for
    /// the screen to close.
    private var pickerBinding: Binding<FamilyActivitySelection> {
        Binding(get: { manager.selection },
                set: { manager.selection = $0; manager.saveSelection() })
    }
}
