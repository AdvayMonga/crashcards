import Testing
import Foundation
@testable import crashcards

/// Cover for the app's own library: `LocalLibrary.save` → the folder scan, which is what
/// seeding the starter decks goes through.
///
/// The parser suites test the parsing. This tests the hop through the file system that
/// separates "the cards parsed" from "the set is in your library", which is where a set
/// would actually be lost.
@Suite(.serialized)
struct LocalLibraryTests {

    /// Every test writes into the real local library, so each cleans up what it made.
    private func cleanUp(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    /// The set this title produced, as the library would list it.
    private func savedSet(titled title: String) throws -> FlashcardSet? {
        try FolderAccess.loadSets().sets.first { $0.title == title }
    }

    /// Two saves with the same name must not become one set.
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
}
