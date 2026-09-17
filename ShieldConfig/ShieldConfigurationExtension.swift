import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Customizes the system block screen. Only these fields are ours — the shield itself is
/// system-rendered, so the questions live in the app, not here.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private var shield: ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.5),
            icon: UIImage(systemName: "rectangle.on.rectangle.angled"),
            title: .init(text: "Blocked", color: .white),
            subtitle: .init(text: "Open Crash Cards and answer \(questionCount) questions to unlock this app for \(unlockMinutes) minutes.",
                            color: .white.withAlphaComponent(0.8)),
            primaryButtonLabel: .init(text: "OK", color: .black),
            primaryButtonBackgroundColor: .white
        )
    }

    // Kept in sync with ScreenTimeManager; extensions can't import the app target.
    private var questionCount: Int { 3 }
    private var unlockMinutes: Int { 10 }

    override func configuration(shielding application: Application) -> ShieldConfiguration { shield }
    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration { shield }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { shield }
    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration { shield }
}
