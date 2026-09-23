import Foundation
import Testing
@testable import crashcards

/// Which sets the gate draws from. The rule that matters is what an *empty* choice means:
/// nobody has opened the picker on a fresh install, and the gate still has to work.
struct GateSetsTests {

    private func set(_ id: String, answers: [String]) -> FlashcardSet {
        let cards = answers.map {
            Card(content: .flip(front: "q-\($0)", back: $0), setID: id, setTitle: id)
        }
        return FlashcardSet(id: id, title: id, cards: cards)
    }

    /// `LibraryStore.cards(in:)` over values, so the rule can be checked without a store.
    private func cards(in ids: Set<String>, from sets: [FlashcardSet]) -> [Card] {
        let picked = sets.filter { ids.contains($0.id) }
        return (picked.isEmpty ? sets : picked).flatMap(\.cards)
    }

    private var library: [FlashcardSet] {
        [set("a.md", answers: ["one", "two"]),
         set("b.md", answers: ["three"]),
         set("c.md", answers: ["four", "five"])]
    }

    @Test func noChoiceMeansEverySet() {
        #expect(cards(in: [], from: library).count == 5)
    }

    @Test func picksOnlyTheChosenSets() {
        let picked = cards(in: ["a.md", "c.md"], from: library)
        #expect(picked.count == 4)
        #expect(!picked.contains { $0.setID == "b.md" })
    }

    /// The Study tab can rename or delete a set out from under a choice made weeks ago.
    /// Falling back to every set beats gating on nothing.
    @Test func aChoiceOfSetsThatNoLongerExistFallsBackToEverything() {
        #expect(cards(in: ["gone.md"], from: library).count == 5)
    }

    @Test func anEmptyLibraryYieldsNoCardsWhicheverWayItIsAsked() {
        #expect(cards(in: [], from: []).isEmpty)
        #expect(cards(in: ["a.md"], from: []).isEmpty)
    }

    // MARK: - The two selections are independent

    @Test func theGateChoiceAndTheStudyChoiceDoNotShareStorage() {
        let suite = "gate-sets-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(["a.md"], forKey: "selectedSetIDs")
        defaults.set(["b.md", "c.md"], forKey: "gateSetIDs")

        #expect(Set(defaults.stringArray(forKey: "selectedSetIDs") ?? []) == ["a.md"])
        #expect(Set(defaults.stringArray(forKey: "gateSetIDs") ?? []) == ["b.md", "c.md"])
    }

    /// Only the sets that can produce a question count — a set of flip cards that all share
    /// one answer has cards and nothing to ask, and the picker says so per row.
    @Test func countsQuestionsRatherThanCards() {
        let sameAnswer = set("dupe.md", answers: ["yes", "yes"])
        #expect(sameAnswer.cards.count == 2)
        #expect(UnlockView.answerable(in: sameAnswer.cards).isEmpty)

        let varied = set("varied.md", answers: ["yes", "no"])
        #expect(UnlockView.answerable(in: varied.cards).count == 2)
    }
}
