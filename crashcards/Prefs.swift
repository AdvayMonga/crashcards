import Foundation

/// Lightweight persisted preferences. (The `.md` files remain the source of truth for cards;
/// this only remembers which sets were last selected.)
enum Prefs {
    private static let selectedKey = "selectedSetIDs"
    private static let gateKey = "gateSetIDs"
    private static let providerKey = "preferredProviderID"
    private static let quizLengthKey = "quizLength"

    static var selectedSetIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: selectedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: selectedKey) }
    }

    /// Which sets the unlock gate asks from. Deliberately separate from `selectedSetIDs`:
    /// what you sit down to study and what stands between you and your apps are different
    /// choices, and changing one shouldn't quietly change the other.
    ///
    /// Empty means every set, so the gate works before it has ever been configured.
    static var gateSetIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: gateKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: gateKey) }
    }

    /// How many questions a quiz asks, or `nil` for the whole selection. Stored as 0 for
    /// "all" so an unset default and a deliberate choice can't be confused.
    static var quizLength: Int? {
        get {
            let stored = UserDefaults.standard.integer(forKey: quizLengthKey)
            return stored > 0 ? stored : nil
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: quizLengthKey) }
    }

    /// Which chatbot "Explain" opens. Also set by using one in the generate panel, so the
    /// setting usually agrees with what you already reach for without being visited.
    static var preferredProviderID: String {
        get { UserDefaults.standard.string(forKey: providerKey) ?? "claude" }
        set { UserDefaults.standard.set(newValue, forKey: providerKey) }
    }
}
