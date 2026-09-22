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
    /// Every scheduled-focus activity is named with this prefix, so they can be told apart
    /// from `relockActivity` without keeping a second list of what's registered.
    static let scheduleActivityPrefix = "focus-"

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    private static let selectionKey = "blockSelection"
    private static let blockingKey = "isBlocking"
    private static let unlockKey = "unlockedUntil"
    private static let schedulesKey = "focusSchedules"
    private static let questionsKey = "questionsToUnlock"
    private static let minutesKey = "unlockMinutes"

    static var selection: FamilyActivitySelection {
        get {
            guard let data = defaults.data(forKey: selectionKey),
                  let saved = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
            else { return FamilyActivitySelection() }
            return saved
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: selectionKey) }
    }

    /// The manual switch on the Focus tab. Schedules block independently of it.
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

    // MARK: - Schedules

    static var schedules: [FocusSchedule] {
        get {
            guard let data = defaults.data(forKey: schedulesKey),
                  let saved = try? JSONDecoder().decode([FocusSchedule].self, from: data)
            else { return [] }
            return saved
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: schedulesKey) }
    }

    /// The schedule running right now, if any. Read by the app and by both extensions.
    static func activeSchedule(at date: Date = Date()) -> FocusSchedule? {
        schedules.first { $0.isActive(at: date) }
    }

    // MARK: - Unlock rules

    static let defaultQuestions = 3
    static let defaultMinutes = 10

    /// Correct answers required to lift the shield.
    static var questionsToUnlock: Int {
        get { (defaults.object(forKey: questionsKey) as? Int) ?? defaultQuestions }
        set { defaults.set(newValue, forKey: questionsKey) }
    }

    /// How long the shield stays down once you've earned it.
    static var unlockMinutes: Int {
        get { (defaults.object(forKey: minutesKey) as? Int) ?? defaultMinutes }
        set { defaults.set(newValue, forKey: minutesKey) }
    }

    // MARK: - The shield

    /// Should apps be shielded at this instant?
    ///
    /// Derived rather than stored, so nothing has to stay in sync: the manual switch, any
    /// schedule and a running unlock are read fresh every time. A missed DeviceActivity
    /// callback therefore can't strand the shield — the next call puts it right.
    static var shouldShield: Bool {
        guard !isUnlocked else { return false }
        return isBlocking || activeSchedule() != nil
    }

    /// Single source of truth for the shield.
    static func applyShield() {
        let store = ManagedSettingsStore()
        guard shouldShield else {
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
