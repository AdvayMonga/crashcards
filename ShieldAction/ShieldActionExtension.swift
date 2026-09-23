import ManagedSettings
import UserNotifications

/// Answers the shield's buttons. Answer hands you to Crash Cards for the questions; Not now
/// closes the blocked app.
///
/// iOS 26.5 can open the parent app straight from here. Older systems can't — an extension
/// has no UIApplication — so they get a local notification whose tap opens the app instead.
/// Either way the tapped app is left in the App Group so the gate knows where you were going.
class ShieldActionExtension: ShieldActionDelegate {
    /// `ShieldActionResponse.openParentalControlsApp`, new in iOS 26.5. The 26.2 SDK this
    /// builds against has no name for it, so it's built from its raw value: the fourth case
    /// after none, close and defer. Replace with the named case once Xcode is on 26.5.
    private static let openParentApp = 3

    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, tapped: application, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, tapped: nil, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, tapped: nil, completionHandler: completionHandler)
    }

    private func respond(to action: ShieldAction, tapped: ApplicationToken?,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard action == .primaryButtonPressed else { completionHandler(.close); return }

        let name = tapped.flatMap { Application(token: $0).localizedDisplayName }
        BlockingShared.pendingGate = PendingGate(token: tapped, name: name, at: Date())

        if #available(iOS 26.5, *), let open = ShieldActionResponse(rawValue: Self.openParentApp) {
            completionHandler(open)
            return
        }
        notify(about: name) { completionHandler(.none) }
    }

    /// The shield stays up behind the banner; tapping the banner opens Crash Cards.
    private func notify(about name: String?, then done: @escaping () -> Void) {
        let questions = BlockingShared.questionsToUnlock
        let content = UNMutableNotificationContent()
        content.title = "Answer to unlock"
        content.body = "\(questions) \(questions == 1 ? "question" : "questions") in Crash Cards opens "
            + "\(name ?? "the app") for \(BlockingShared.unlockMinutes) minutes."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "gate", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in done() }
    }
}
