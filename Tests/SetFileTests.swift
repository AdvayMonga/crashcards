import Testing
import Foundation
@testable import crashcards

/// Which files are sets, what they're called, and what a set may be saved as.
@Suite struct SetFileTests {
    @Test(arguments: ["deck.md", "deck.markdown", "deck.txt", "deck.text", "deck.csv", "deck.tsv", "DECK.MD"])
    func readsEverySupportedExtension(name: String) {
        #expect(SetFile.canRead(URL(fileURLWithPath: "/tmp/\(name)")))
    }

    @Test(arguments: ["notes.pdf", "sheet.numbers", "deck", "archive.zip"])
    func ignoresEverythingElse(name: String) {
        #expect(SetFile.canRead(URL(fileURLWithPath: "/tmp/\(name)")) == false)
    }

    @Test func tablesGoToTheTableParserAndTextToTheCardParser() {
        #expect(SetFile.parse("Dog,Perro", filename: "x.csv").set.cards.count == 1)
        #expect(SetFile.parse("Dog :: Perro", filename: "x.txt").set.cards.count == 1)
        // A comma line isn't a card in a text file, and `::` isn't a column in a table.
        #expect(SetFile.parse("Dog,Perro", filename: "x.txt").set.cards.isEmpty)
    }

    @Test func titleDropsTheExtensionOnly() {
        #expect(SetFile.title(from: "Chapter 3.notes.md") == "Chapter 3.notes")
        #expect(SetFile.title(from: "deck.csv") == "deck")
    }

    /// A name starting with "." would save fine and then never appear: scans skip hidden files.
    @Test func filenameNeverProducesAHiddenFile() {
        #expect(SetFile.filename(from: ".NET Basics") == "NET Basics")
        #expect(SetFile.filename(from: "...") == "Set")
    }

    @Test func filenameStripsPathSeparatorsAndEmptyNames() {
        #expect(SetFile.filename(from: "Chem/Organic") == "Chem-Organic")
        #expect(SetFile.filename(from: "   ") == "Set")
        #expect(SetFile.filename(from: String(repeating: "a", count: 200)).count == 60)
    }
}
