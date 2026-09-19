import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity

/// State shared between the app and its Screen Time extensions, via the App Group.
/// The extensions run in their own processes, so this is the only channel between them.
enum BlockingShared {
    static let appGroup = "group.com.advaymonga.crashcards"
    /// The scheduled window whose start re-applies the shield after an unlock expires.
    static let relockActivity = DeviceActivityName("relock")

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    private static let selectionKey = "blockSelection"
    private static let blockingKey = "isBlocking"
    private static let unlockKey = "unlockedUntil"

    static var selection: FamilyActivitySelection {
        get {
            guard let data = defaults.data(forKey: selectionKey),
                  let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
            else { return FamilyActivitySelection() }
            return saved
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: selectionKey) }
    }

    static var isBlocking: Bool {
        get { defaults.bool(forKey: blockingKey) }
        set { defaults.set(newValue, forKey: blockingKey) }
    }

    /// When the current unlock window ends; nil when apps are shielded.
    static var unlockedUntil: Date? {
        get { defaults.object(forKey: unlockKey) as? Date }
        set { defaults.set(newValue, forKey: unlockKey) }
    }

    static var isUnlocked: Bool {
        guard let until = unlockedUntil else { return false }
        return until > Date()
    }

    /// Single source of truth for the shield: on when blocking and not inside an unlock window.
    static func applyShield() {
        let store = ManagedSettingsStore()
        guard isBlocking, !isUnlocked else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            return
        }
        let selection = selection
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
    }

    /// End any unlock window early and re-shield. Called by the monitor extension on schedule.
    static func endUnlock() {
        unlockedUntil = nil
        applyShield()
    }
}
