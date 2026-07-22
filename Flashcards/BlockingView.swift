import SwiftUI
import FamilyControls

/// Choose apps to block and toggle the shield on/off.
struct BlockingView: View {
    @State private var manager = ScreenTimeManager()
    @State private var pickerShown = false

    var body: some View {
        @Bindable var manager = manager
        List {
            if !manager.isAuthorized {
                Section {
                    Text("Allow Screen Time access so Flashcards can block apps.")
                        .foregroundStyle(.secondary)
                    Button("Authorize") { Task { await manager.requestAuthorization() } }
                }
            } else {
                Section("Apps to block") {
                    Button { pickerShown = true } label: {
                        Label(selectionSummary, systemImage: "apps.iphone")
                    }
                }
                Section {
                    if manager.isBlocking {
                        Button("Stop blocking", role: .destructive) { manager.stopBlocking() }
                    } else {
                        Button("Start blocking") { manager.startBlocking() }
                            .disabled(!manager.hasSelection)
                    }
                } footer: {
                    Text("When blocking is on, opening a chosen app shows a block screen. Real blocking works on a physical device only.")
                }
            }

            if let error = manager.errorText {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("App Blocking")
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(isPresented: $pickerShown, selection: $manager.selection)
        .onChange(of: pickerShown) { _, shown in
            if !shown { manager.saveSelection() }
        }
    }

    private var selectionSummary: String {
        let count = manager.selection.applicationTokens.count + manager.selection.categoryTokens.count
        return count == 0 ? "Choose apps…" : "\(count) selected"
    }
}
