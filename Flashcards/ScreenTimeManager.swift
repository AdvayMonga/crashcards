import Foundation
import FamilyControls
import ManagedSettings
import Observation

/// Blocks user-chosen apps via Screen Time (Family Controls). Opening a blocked app shows
/// the system shield. Real behavior is device-only; the simulator can't shield apps.
@MainActor
@Observable
final class ScreenTimeManager {
    var selection = FamilyActivitySelection()
    var isAuthorized = false
    var isBlocking = false
    var errorText: String?

    private let store = ManagedSettingsStore()
    private let selectionKey = "blockSelection"
    private let blockingKey = "isBlocking"

    init() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        isBlocking = UserDefaults.standard.bool(forKey: blockingKey)
        if let data = UserDefaults.standard.data(forKey: selectionKey),
           let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = saved
        }
    }

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
            errorText = nil
        } catch {
            errorText = error.localizedDescription
            isAuthorized = false
        }
    }

    func saveSelection() {
        if let data = try? JSONEncoder().encode(selection) {
            UserDefaults.standard.set(data, forKey: selectionKey)
        }
        if isBlocking { startBlocking() }   // keep an active shield in sync with edits
    }

    func startBlocking() {
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
        isBlocking = true
        UserDefaults.standard.set(true, forKey: blockingKey)
    }

    func stopBlocking() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        isBlocking = false
        UserDefaults.standard.set(false, forKey: blockingKey)
    }
}
