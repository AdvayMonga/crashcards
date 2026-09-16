import Testing
import Foundation
@testable import Flashcards

/// The links a Shortcuts automation sends us.
@Suite struct GatedAppsTests {
    @Test func recognisesAGateLink() {
        #expect(GatedApps.isGate(URL(string: "flashcards://gate?app=linkedin")!))
        #expect(GatedApps.isGate(URL(string: "flashcards://gate")!))
        #expect(GatedApps.isGate(URL(string: "flashcards://something")!) == false)
        #expect(GatedApps.isGate(URL(string: "https://example.com/gate?app=linkedin")!) == false)
    }

    @Test func findsAKnownAppEvenBeforeItIsAdded() {
        let app = GatedApps.target(of: URL(string: "flashcards://gate?app=linkedin")!)
        #expect(app?.name == "LinkedIn")
        #expect(app?.scheme == "linkedin://")
    }

    /// An unknown app still opens the gate; only the trip back is missing.
    @Test func unknownOrMissingAppIsNoTarget() {
        #expect(GatedApps.target(of: URL(string: "flashcards://gate?app=nothinghere")!) == nil)
        #expect(GatedApps.target(of: URL(string: "flashcards://gate")!) == nil)
    }

    @Test func everyCatalogueEntryHasAUsableLinkAndAUniqueSlug() {
        let catalogue = GatedApps.catalogue
        #expect(Set(catalogue.map(\.id)).count == catalogue.count)
        for app in catalogue {
            #expect(app.returnURL != nil, "\(app.name) scheme should parse")
            #expect(app.triggerURL == "flashcards://gate?app=\(app.id)")
            #expect(GatedApps.isGate(URL(string: app.triggerURL)!))
        }
    }
}
