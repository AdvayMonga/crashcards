import Foundation

/// An app you want to answer questions for, and the URL that reopens it.
///
/// Screen Time tokens are opaque, so the app can't learn which app you picked in the
/// blocking picker — you name the app here so we know where to send you afterwards.
struct GatedApp: Identifiable, Codable, Hashable {
    var id: String        // slug used in flashcards://gate?app=<id>
    var name: String
    var scheme: String    // e.g. "linkedin://"

    /// The link a Shortcuts automation opens to hand control to Flashcards.
    var triggerURL: String { "flashcards://gate?app=\(id)" }
    var returnURL: URL? { URL(string: scheme) }
}

/// The gated apps you've set up, saved between launches.
enum GatedApps {
    private static let key = "gatedApps"

    /// Apps whose URL schemes are well known, offered when adding.
    static let catalogue: [GatedApp] = [
        GatedApp(id: "linkedin", name: "LinkedIn", scheme: "linkedin://"),
        GatedApp(id: "instagram", name: "Instagram", scheme: "instagram://"),
        GatedApp(id: "tiktok", name: "TikTok", scheme: "tiktok://"),
        GatedApp(id: "x", name: "X", scheme: "twitter://"),
        GatedApp(id: "youtube", name: "YouTube", scheme: "youtube://"),
        GatedApp(id: "reddit", name: "Reddit", scheme: "reddit://"),
        GatedApp(id: "facebook", name: "Facebook", scheme: "fb://"),
        GatedApp(id: "snapchat", name: "Snapchat", scheme: "snapchat://"),
        GatedApp(id: "discord", name: "Discord", scheme: "discord://"),
    ]

    static var all: [GatedApp] {
        get {
            guard let data = BlockingShared.defaults.data(forKey: key),
                  let saved = try? JSONDecoder().decode([GatedApp].self, from: data)
            else { return [] }
            return saved
        }
        set { BlockingShared.defaults.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    /// Your list first, then the known-apps list — so a link works before you add the app.
    static func find(_ id: String) -> GatedApp? {
        all.first { $0.id == id } ?? catalogue.first { $0.id == id }
    }

    static func add(_ app: GatedApp) {
        var apps = all
        guard !apps.contains(where: { $0.id == app.id }) else { return }
        apps.append(app)
        all = apps
    }

    static func remove(_ app: GatedApp) {
        all = all.filter { $0.id != app.id }
    }

    static func isGate(_ url: URL) -> Bool {
        url.scheme == "flashcards" && url.host == "gate"
    }

    /// The app `flashcards://gate?app=linkedin` names, or nil if we don't know it — the
    /// gate still opens in that case, it just has nowhere to send you afterwards.
    static func target(of url: URL) -> GatedApp? {
        guard isGate(url),
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "app" })?.value
        else { return nil }
        return find(id)
    }

    /// The app we last handed the user to, and when.
    private static var lastRedirect: (id: String, at: Date)?

    static func recordRedirect(to app: GatedApp) {
        lastRedirect = (app.id, Date())
    }

    /// Deep-linking into an app trips its own "when opened" automation, which sends us
    /// another gate link seconds later. Redirecting again would bounce forever, so a gate
    /// that arrives right behind our own redirect is ignored.
    static func justRedirected(to app: GatedApp) -> Bool {
        guard let lastRedirect, lastRedirect.id == app.id else { return false }
        return Date().timeIntervalSince(lastRedirect.at) < 3
    }
}
