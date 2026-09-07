import SwiftUI
import FamilyControls

/// Focus tab: what's blocked, whether the shield is up, and the way past it.
struct FocusView: View {
    @Environment(ScreenTimeManager.self) private var manager
    @Environment(LibraryStore.self) private var library
    @State private var pickerShown = false
    @State private var unlocking = false
    @State private var startAfterPicking = false

    /// Keeps the countdown honest while the screen is open.
    private let tick = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                Section { status.listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }

                Section {
                    Toggle("Block apps", isOn: blockingBinding)
                } footer: {
                    Text("Opening a blocked app shows a block screen. Answer \(ScreenTimeManager.questionsToUnlock) questions here to unlock everything for \(ScreenTimeManager.unlockMinutes) minutes.")
                }

                Section("Blocked apps") {
                    ForEach(Array(manager.selection.applicationTokens), id: \.self) { token in
                        Label(token)
                    }
                    ForEach(Array(manager.selection.categoryTokens), id: \.self) { token in
                        Label(token)
                    }
                    Button(manager.hasSelection ? "Change apps" : "Choose apps") { pickerShown = true }
                }

                if let error = manager.errorText {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Focus")
            .familyActivityPicker(isPresented: $pickerShown, selection: pickerBinding)
            .sheet(isPresented: $unlocking) {
                NavigationStack { UnlockView(cards: library.quizCards, manager: manager) }
            }
            .onReceive(tick) { _ in manager.refresh() }
        }
    }

    /// The one thing this screen is really answering: can I open my apps right now?
    @ViewBuilder private var status: some View {
        VStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 52))
                .foregroundStyle(statusColor)
            Text(statusTitle)
                .font(.title2.weight(.semibold))
            if let until = manager.unlockedUntil {
                Text(until, style: .timer)
                    .font(.system(.title3, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if manager.isShieldActive {
                Button("Answer \(ScreenTimeManager.questionsToUnlock) questions to unlock") {
                    unlocking = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(library.quizCards.isEmpty)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var statusIcon: String {
        if manager.isShieldActive { return "lock.fill" }
        return manager.isBlocking ? "lock.open.fill" : "lock.slash"
    }
    private var statusColor: Color {
        if manager.isShieldActive { return .accentColor }
        return manager.isBlocking ? .green : .secondary
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
