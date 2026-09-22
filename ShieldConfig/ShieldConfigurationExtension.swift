import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Customizes the system block screen. Only these fields are ours — the shield itself is
/// system-rendered, so the questions live in the app, not here.
///
/// The joker is the app's sign for a blocked thing: the card you'd rather be playing, face
/// up, with the suit locked in its corners. It's the same card the app icon carries and the
/// same one the Focus tab shows while the shield is up.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private var shield: ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .dark,
            backgroundColor: Table.deep.withAlphaComponent(0.94),
            icon: blockedCards,
            title: .init(text: "The joker's locked", color: Table.ink),
            subtitle: .init(text: "Open Crash Cards and answer \(questionCount) \(questionCount == 1 ? "question" : "questions") to unlock this app for \(unlockMinutes) minutes.",
                            color: Table.inkDim),
            primaryButtonLabel: .init(text: "OK", color: Table.outline),
            primaryButtonBackgroundColor: Table.gold
        )
    }

    /// `alwaysOriginal` so the shield can't flatten the cards into a tint.
    private var blockedCards: UIImage? {
        UIImage(named: "BlockedCards")?.withRenderingMode(.alwaysOriginal)
    }

    /// Kept in sync with `Brand`; an extension can't import the app target.
    private enum Table {
        static let deep = UIColor(red: 0x16 / 255, green: 0x22 / 255, blue: 0x2C / 255, alpha: 1)
        static let gold = UIColor(red: 0xF0 / 255, green: 0xC0 / 255, blue: 0x40 / 255, alpha: 1)
        static let outline = UIColor(red: 0x0E / 255, green: 0x15 / 255, blue: 0x19 / 255, alpha: 1)
        static let ink = UIColor(red: 0xF2 / 255, green: 0xED / 255, blue: 0xE1 / 255, alpha: 1)
        static let inkDim = UIColor(red: 0x9D / 255, green: 0xAE / 255, blue: 0xBB / 255, alpha: 1)
    }

    // The app's own settings, read from the App Group — an extension can't import the
    // app target, but it shares its defaults.
    private var questionCount: Int { BlockingShared.questionsToUnlock }
    private var unlockMinutes: Int { BlockingShared.unlockMinutes }

    override func configuration(shielding application: Application) -> ShieldConfiguration { shield }
    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration { shield }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { shield }
    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration { shield }
}
