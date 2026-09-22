import Foundation

/// Two decks copied into the app's library the first time it runs.
///
/// An empty library is the app at its least convincing, and the generate flow only helps
/// someone who already knows they want a deck. These are copied rather than read from the
/// bundle so they behave like any other set — renamable, deletable, and gone for good once
/// deleted, which the seeded flag is what guarantees.
enum StarterDecks {
    private static let seededKey = "didSeedStarterDecks"

    static func seedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        // Set first: a half-finished copy must not re-run and duplicate what did land.
        UserDefaults.standard.set(true, forKey: seededKey)

        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "md"),
                  let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            _ = try? LocalLibrary.save(contents, named: name)
        }
    }

    /// Named rather than globbed for `.md`, so a stray markdown file added to the target
    /// later doesn't silently become a deck.
    static let names = ["Weird But True", "Riddles"]
}
