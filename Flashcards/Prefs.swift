import Foundation

/// Lightweight persisted preferences. (The `.md` files remain the source of truth for cards;
/// this only remembers which sets were last selected.)
enum Prefs {
    private static let selectedKey = "selectedSetIDs"

    static var selectedSetIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: selectedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: selectedKey) }
    }
}
