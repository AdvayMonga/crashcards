import SwiftUI
import FamilyControls

/// Focus tab: what's blocked, whether the shield is up, and the way past it.
struct FocusView: View {
    @Environment(ScreenTimeManager.self) private var manager
    @Environment(LibraryStore.self) private var library
    @State private var pickerShown = false
    @State private var unlocking = false
    @State private var startAfterPicking = false
    @State private var gatedApps = GatedApps.all
    @State private var addingApp = false
    @State private var copied: String?

    /// Keeps the countdown honest while the screen is open.
    private let tick = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                status
                blockingPanel
                gatedPanel
                appsPanel
                if let error = manager.errorText {
                    Text(error)
                        .font(.reading(14))
                        .foregroundStyle(Brand.mult)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .slab(Brand.surface)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top) { ScreenHeader("Focus") }
        .familyActivityPicker(isPresented: $pickerShown, selection: pickerBinding)
        .screenLayer(isPresented: $addingApp) {
            AddGatedAppView(onClose: { addingApp = false }) { app in
                GatedApps.add(app)
                gatedApps = GatedApps.all
            }
        }
        .screenLayer(isPresented: $unlocking) {
            UnlockView(cards: library.quizCards, manager: manager) { unlocking = false }
        }
        .onReceive(tick) { _ in manager.refresh() }
    }

    /// The one thing this screen is really answering: can I open my apps right now?
    private var status: some View {
        VStack(spacing: 14) {
            PixelIcon(glyph: statusGlyph, size: 54, color: statusColor)
                .padding(24)
                .slab(Brand.surfaceHigh, radius: Brand.cardRadius)
                .breathing(manager.isShieldActive ? 1.6 : 0.8, period: 3.0)

            Text(statusTitle)
                .font(.brandTitle)
                .foregroundStyle(Brand.ink)

            if let until = manager.unlockedUntil {
                Text(until, style: .timer)
                    .font(.pixel(30))
                    .foregroundStyle(Brand.green)
                    .monospacedDigit()
            } else if !statusDetail.isEmpty {
                Text(statusDetail)
                    .font(.reading(15))
                    .foregroundStyle(Brand.inkDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if manager.isShieldActive {
                Button("Answer \(ScreenTimeManager.questionsToUnlock) questions to unlock") {
                    Haptics.thud()
                    unlocking = true
                }
                .buttonStyle(.solid)
                .disabled(library.quizCards.isEmpty)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
    }

    private var blockingPanel: some View {
        Panel(footnote: "Opening a blocked app shows a block screen. Answer \(ScreenTimeManager.questionsToUnlock) questions here to unlock everything for \(ScreenTimeManager.unlockMinutes) minutes.") {
            PanelRow(first: true) {
                CrashToggle(label: "Block apps", isOn: blockingBinding)
            }
        }
    }

    /// Apps that hand you to the questions and take you back when you're done.
    private var gatedPanel: some View {
        Panel(title: "Straight to the questions",
              footnote: "Set this up once per app in Shortcuts: Automation → When \(gatedApps.first?.name ?? "an app") is opened → Run Immediately → Open URL, pasted from the row above. Opening that app then jumps here for the questions and back to it when you pass.") {
            ForEach(Array(gatedApps.enumerated()), id: \.element.id) { index, app in
                PanelRow(first: index == 0) {
                    HStack(spacing: 10) {
                        Button { copy(app) } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name)
                                        .font(.brandLabel)
                                        .foregroundStyle(Brand.ink)
                                    Text(copied == app.id ? "Link copied" : app.triggerURL)
                                        .font(.reading(12))
                                        .foregroundStyle(copied == app.id ? Brand.green : Brand.inkFaint)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                PixelIcon(glyph: .copy, size: 16, color: Brand.inkDim)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)

                        Button {
                            Haptics.tap()
                            GatedApps.remove(app)
                            gatedApps = GatedApps.all
                        } label: {
                            PixelIcon(glyph: .close, size: 14, color: Brand.mult)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Remove \(app.name)")
                    }
                }
            }
            PanelRow(first: gatedApps.isEmpty) {
                Button("Add an app") {
                    Haptics.tap()
                    addingApp = true
                }
                .buttonStyle(CrashButton(kind: .ghost, tint: Brand.gold, fullWidth: false))
            }
        }
    }

    /// The tokens are rendered by FamilyControls, which only ever draws them its own way.
    private var appsPanel: some View {
        Panel(title: "Blocked apps") {
            let apps = Array(manager.selection.applicationTokens)
            let categories = Array(manager.selection.categoryTokens)

            ForEach(Array(apps.enumerated()), id: \.element) { index, token in
                PanelRow(first: index == 0) {
                    Label(token).font(.reading(15)).foregroundStyle(Brand.ink)
                }
            }
            ForEach(Array(categories.enumerated()), id: \.element) { index, token in
                PanelRow(first: apps.isEmpty && index == 0) {
                    Label(token).font(.reading(15)).foregroundStyle(Brand.ink)
                }
            }
            PanelRow(first: apps.isEmpty && categories.isEmpty) {
                Button(manager.hasSelection ? "Change apps" : "Choose apps") {
                    Haptics.tap()
                    pickerShown = true
                }
                .buttonStyle(CrashButton(kind: .ghost, tint: Brand.gold, fullWidth: false))
            }
        }
    }

    private func copy(_ app: GatedApp) {
        Haptics.tap()
        UIPasteboard.general.string = app.triggerURL
        copied = app.id
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copied == app.id { copied = nil }
        }
    }

    private var statusGlyph: PixelGlyph {
        manager.isShieldActive ? .lockClosed : .lockOpen
    }
    private var statusColor: Color {
        if manager.isShieldActive { return Brand.gold }
        return manager.isBlocking ? Brand.green : Brand.inkFaint
    }
    private var statusTitle: String {
        if manager.isShieldActive { return "Apps blocked" }
        return manager.isBlocking ? "Unlocked" : "Focus off"
    }
    private var statusDetail: String {
        manager.isBlocking ? "" : "Turn on blocking to put your apps behind a few questions."
    }

    /// Turning blocking on walks the whole setup: permission, then apps, then shield.
    private var blockingBinding: Binding<Bool> {
        Binding(
            get: { manager.isBlocking },
            set: { on in
                guard on else { manager.stopBlocking(); return }
                Task {
                    if !manager.isAuthorized { await manager.requestAuthorization() }
                    guard manager.isAuthorized else { return }
                    if manager.hasSelection {
                        manager.startBlocking()
                    } else {
                        startAfterPicking = true
                        pickerShown = true
                    }
                }
            }
        )
    }

    /// Saving on every edit keeps an active shield in sync with the picker.
    private var pickerBinding: Binding<FamilyActivitySelection> {
        Binding(
            get: { manager.selection },
            set: { newValue in
                manager.selection = newValue
                manager.saveSelection()
                if startAfterPicking, manager.hasSelection {
                    startAfterPicking = false
                    manager.startBlocking()
                }
            }
        )
    }
}
