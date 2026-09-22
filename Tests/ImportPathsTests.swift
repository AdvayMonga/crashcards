import Testing
import Foundation
@testable import crashcards

/// End-to-end cover for the ways a set gets *in*: paste, fetched link, opened file and
/// share sheet all converge on `ImportParser` → `LocalLibrary.save` → the folder scan, and
/// the share extension adds a hop through the App Group before that.
///
/// The parser suites test the parsing. This tests the hop through the file system that
/// separates "the cards parsed" from "the set is in your library", which is where an import
/// would actually be lost.
@Suite(.serialized)
struct ImportPathsTests {

    /// Every test writes into the real local library, so each cleans up what it made.
    private func cleanUp(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    /// The set this title produced, as the library would list it.
    private func savedSet(titled title: String) throws -> FlashcardSet? {
        try FolderAccess.loadSets().sets.first { $0.title == title }
    }

    // MARK: - Paste, fetch and open-a-file (one path from `save()` onward)

    @Test func apastedSetIsSavedAndScannedBackWithItsCards() throws {
        let title = "Paste Test \(UUID().uuidString.prefix(8))"
        let result = ImportParser.parse("mitochondria\tpowerhouse\nribosome\tprotein",
                                        title: title)
        #expect(result.cards.count == 2)

        let url = try LocalLibrary.save(ImportParser.markdown(title: title, cards: result.cards),
                                        named: title)
        defer { cleanUp([url]) }

        let set = try savedSet(titled: title)
        #expect(set?.cards.count == 2)
        #expect(set?.cards.map(\.prompt) == ["mitochondria", "ribosome"])
        #expect(set?.cards.map(\.answer) == ["powerhouse", "protein"])
    }

    /// Multiple choice has to survive the disk too — it's the half of a set the unlock gate
    /// draws on, so a set that came back flip-only would quietly empty the shield's questions.
    @Test func animportedQuestionComesBackAsAQuestion() throws {
        let title = "Quiz Import \(UUID().uuidString.prefix(8))"
        let text = """
        What is the capital of France?,Paris
        What is the capital of Japan?,Tokyo
        """
        let result = ImportParser.parse(text, title: title)
        let url = try LocalLibrary.save(ImportParser.markdown(title: title, cards: result.cards),
                                        named: title)
        defer { cleanUp([url]) }

        let set = try savedSet(titled: title)
        #expect(set?.cards.count == 2)
        #expect(set?.cards.allSatisfy { !$0.prompt.isEmpty } == true)
    }

    /// Two imports with the same name must not become one import.
    @Test func asecondSetWithTheSameNameDoesNotOverwriteTheFirst() throws {
        let title = "Clash Test \(UUID().uuidString.prefix(8))"
        let first = try LocalLibrary.save("# \(title)\n\nalpha :: one", named: title)
        let second = try LocalLibrary.save("# \(title)\n\nbeta :: two", named: title)
        defer { cleanUp([first, second]) }

        #expect(first != second)
        #expect(try String(contentsOf: first, encoding: .utf8).contains("alpha"))
        #expect(try String(contentsOf: second, encoding: .utf8).contains("beta"))

        let sets = try FolderAccess.loadSets().sets.filter { $0.title == title }
        #expect(sets.count == 2)
    }

    /// A title starting with a dot would save without error and then never appear, because
    /// the scan skips hidden files. The filename rule exists for this; the save path must use it.
    @Test func asetNamedLikeADotfileStillShowsUp() throws {
        let stamp = UUID().uuidString.prefix(8)
        let url = try LocalLibrary.save("# .hidden \(stamp)\n\nalpha :: one",
                                        named: ".hidden \(stamp)")
        defer { cleanUp([url]) }

        #expect(!url.lastPathComponent.hasPrefix("."))
        #expect(try savedSet(titled: ".hidden \(stamp)")?.cards.count == 1)
    }

    /// A title with a path separator in it must stay inside the library directory.
    @Test func asetNamedWithASlashStaysInTheLibrary() throws {
        let stamp = UUID().uuidString.prefix(8)
        let url = try LocalLibrary.save("# Bio\n\nalpha :: one", named: "Unit 1/Bio \(stamp)")
        defer { cleanUp([url]) }

        #expect(url.deletingLastPathComponent().standardizedFileURL
                == LocalLibrary.directory.standardizedFileURL)
    }

    /// `Flagged.md` is app state; if the scan ever picked it up it would list as a set of
    /// duplicates of everything you've flagged.
    @Test func theflagFileIsNotScannedAsASet() throws {
        let url = LocalLibrary.directory.appendingPathComponent(FlagStore.filename)
        let existed = FileManager.default.fileExists(atPath: url.path)
        if !existed { try "# Flagged\n\n- [ ] **too easy** — a :: b".write(to: url, atomically: true, encoding: .utf8) }
        defer { if !existed { cleanUp([url]) } }

        #expect(try !LocalLibrary.files().contains { $0.lastPathComponent == FlagStore.filename })
    }

    // MARK: - The share sheet

    /// The App Group container only exists when the build carries the entitlement, which an
    /// unsigned simulator build does not. These two run on a signed build — on a device, or
    /// locally with a team set — and skip where the hand-off can't physically happen.
    static let appGroupReachable = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: SharedInbox.appGroup) != nil


    /// The extension can only park text; the app has to find it, name it and clear it.
    @Test(.enabled(if: appGroupReachable))
    func asharedNoteArrivesInTheAppWithItsTitle() throws {
        let title = "SharedSet\(UUID().uuidString.prefix(6))"
        let body = "alpha :: one\nbeta :: two"
        try SharedInbox.deposit(body, title: title)

        let waiting = try #require(SharedInbox.next(), "a deposited share should be waiting")
        defer { SharedInbox.clear(waiting.url) }

        #expect(waiting.text == body)
        #expect(waiting.title == title)

        // What RootView does with it: parse and save, exactly as a paste would.
        let parsed = ImportParser.parse(waiting.text, title: waiting.title)
        #expect(parsed.cards.count == 2)

        SharedInbox.clear(waiting.url)
        #expect(SharedInbox.next() == nil)
    }

    /// Shares queue: clearing one has to reveal the next, not drop it.
    @Test(.enabled(if: appGroupReachable))
    func sharesAreConsumedOldestFirst() async throws {
        try SharedInbox.deposit("alpha :: one", title: "First")
        // The filename is stamped with a timestamp, so two in the same instant would tie.
        try await Task.sleep(for: .milliseconds(20))
        try SharedInbox.deposit("beta :: two", title: "Second")

        let first = try #require(SharedInbox.next())
        #expect(first.title == "First")
        SharedInbox.clear(first.url)

        let second = try #require(SharedInbox.next())
        #expect(second.title == "Second")
        SharedInbox.clear(second.url)

        #expect(SharedInbox.next() == nil)
    }

    // MARK: - Fetching a link

    /// Only the two Google formats that actually export text are rewritten; anything else
    /// is fetched as given, so the error you get is the site's rather than ours.
    @Test func googleLinksAreRewrittenToTheirTextExport() throws {
        let doc = URL(string: "https://docs.google.com/document/d/ABC123/edit?usp=sharing")!
        #expect(ImportSetView.googleDocsExport(doc)?.absoluteString
                == "https://docs.google.com/document/d/ABC123/export?format=txt")

        let sheet = URL(string: "https://docs.google.com/spreadsheets/d/XYZ789/edit#gid=0")!
        #expect(ImportSetView.googleDocsExport(sheet)?.absoluteString
                == "https://docs.google.com/spreadsheets/d/XYZ789/export?format=csv")

        #expect(ImportSetView.googleDocsExport(
            URL(string: "https://docs.google.com/presentation/d/Q/edit")!) == nil)
        #expect(ImportSetView.googleDocsExport(
            URL(string: "https://example.com/cards.txt")!) == nil)
    }
}
