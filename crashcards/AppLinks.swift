import Foundation

/// How the gate sends you back to the app you were opening.
///
/// Screen Time never hands over a blocked app's bundle ID — the token is opaque — so the
/// only thing we learn is the display name the shield extension recorded when you tapped
/// Answer. This maps the names people actually block onto the URL schemes that reopen them.
/// An app that isn't here just doesn't get the automatic return; you switch back yourself.
enum AppLinks {
    /// Keyed by the display name reduced to letters and digits, so "TikTok" and "Tik Tok"
    /// both land on the same row.
    private static let schemes: [String: String] = [
        "instagram": "instagram://",
        "tiktok": "tiktok://",
        "x": "twitter://",
        "twitter": "twitter://",
        "youtube": "youtube://",
        "reddit": "reddit://",
        "facebook": "fb://",
        "messenger": "fb-messenger://",
        "snapchat": "snapchat://",
        "discord": "discord://",
        "linkedin": "linkedin://",
        "whatsapp": "whatsapp://",
        "telegram": "tg://",
        "twitch": "twitch://",
        "netflix": "nflx://",
        "spotify": "spotify://",
        "pinterest": "pinterest://",
    ]

    static func key(for name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The URL that reopens the app called `name`, or nil when we don't know one.
    static func url(forAppNamed name: String?) -> URL? {
        guard let name, let scheme = schemes[key(for: name)] else { return nil }
        return URL(string: scheme)
    }
}
