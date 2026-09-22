import Foundation

/// Lightweight persisted preferences. (The `.md` files remain the source of truth for cards;
/// this only remembers which sets were last selected.)
enum Prefs {
    private static let selectedKey = "selectedSetIDs"
    private static let providerKey = "preferredProviderID"

    static var selectedSetIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: selectedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: selectedKey) }
    }

    /// Which chatbot "Explain" opens. Also set by using one in the generate panel, so the
    /// setting usually agrees with what you already reach for without being visited.
    static var preferredProviderID: String {
        get { UserDefaults.standard.string(forKey: providerKey) ?? "claude" }
        set { UserDefaults.standard.set(newValue, forKey: providerKey) }
    }
}
