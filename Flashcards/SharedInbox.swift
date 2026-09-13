import Foundation

/// Hand-off between the share extension and the app.
///
/// The extension only captures text — parsing and the preview happen in the app, so a
/// share never guesses at your format behind your back. Files wait in the App Group
/// container until the app next opens.
enum InboxError: LocalizedError {
    case noContainer

    var errorDescription: String? {
        "Flashcards can't reach its shared storage, so the share wasn't saved. The app's App Group entitlement is missing or misconfigured."
    }
}

enum SharedInbox {
    /// Same group as BlockingShared, repeated so the share extension needn't import
    /// Family Controls just to read a constant.
    static let appGroup = "group.com.advaymonga.Flashcards"

    private static var directory: URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else { return nil }
        let url = container.appendingPathComponent("Inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Called by the share extension. Throws rather than dropping the share on the floor.
    static func deposit(_ text: String, title: String) throws {
        guard let directory else { throw InboxError.noContainer }
        let name = title.isEmpty ? "Shared" : title
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined()
        let url = directory.appendingPathComponent("\(Date().timeIntervalSince1970)-\(safe.prefix(40)).txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The oldest waiting share, if any. Called by the app.
    static func next() -> (text: String, title: String, url: URL)? {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
              ).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }),
              let first = files.first,
              let text = try? String(contentsOf: first, encoding: .utf8)
        else { return nil }

        // "1757・title.txt" → "title"
        let name = first.deletingPathExtension().lastPathComponent
        let title = name.split(separator: "-", maxSplits: 1).last.map(String.init) ?? "Shared"
        return (text, title, first)
    }

    static func clear(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
