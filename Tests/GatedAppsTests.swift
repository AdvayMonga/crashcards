import Testing
import Foundation
@testable import Flashcards

/// The links a Shortcuts automation sends us.
@Suite struct GatedAppsTests {
    @Test func recognisesAGateLink() {
        #expect(GatedApps.isGate(URL(string: "crashcards://gate?app=linkedin")!))
        #expect(GatedApps.isGate(URL(string: "crashcards://gate")!))
        #expect(GatedApps.isGate(URL(string: "flashcards://something")!) == false)
        #expect(GatedApps.isGate(URL(string: "https://example.com/gate?app=linkedin")!) == false)
    }

    /// `find` falls back to the catalogue, but reads your saved list first — and the test
    /// bundle is hosted by the app, so it would otherwise see whatever you added on this
    /// simulator. A hand-added "Linked In" stores the slug "linkedin" and shadows it.
    @Test func findsAKnownAppEvenBeforeItIsAdded() {
        let saved = GatedApps.all
        GatedApps.all = []
        defer { GatedApps.all = saved }

        let app = GatedApps.target(of: URL(string: "crashcards://gate?app=linkedin")!)
        #expect(app?.name == "LinkedIn")
        #expect(app?.scheme == "linkedin://")
    }

    @Test func yourOwnEntryWinsOverTheCatalogue() {
        let saved = GatedApps.all
        GatedApps.all = [GatedApp(id: "linkedin", name: "Mine", scheme: "custom://")]
        defer { GatedApps.all = saved }

        #expect(GatedApps.target(of: URL(string: "crashcards://gate?app=linkedin")!)?.scheme == "custom://")
    }

    /// An unknown app still opens the gate; only the trip back is missing.
    @Test func unknownOrMissingAppIsNoTarget() {
        #expect(GatedApps.target(of: URL(string: "crashcards://gate?app=nothinghere")!) == nil)
        #expect(GatedApps.target(of: URL(string: "crashcards://gate")!) == nil)
    }

    /// The guard against an app-open automation bouncing us back and forth forever.
    @Test func aRedirectIsRememberedPerApp() {
        let linkedin = GatedApps.catalogue.first { $0.id == "linkedin" }!
        let instagram = GatedApps.catalogue.first { $0.id == "instagram" }!

        GatedApps.recordRedirect(to: linkedin)
        #expect(GatedApps.justRedirected(to: linkedin))
        #expect(GatedApps.justRedirected(to: instagram) == false)
    }

    @Test func everyCatalogueEntryHasAUsableLinkAndAUniqueSlug() {
        let catalogue = GatedApps.catalogue
        #expect(Set(catalogue.map(\.id)).count == catalogue.count)
        for app in catalogue {
            #expect(app.returnURL != nil, "\(app.name) scheme should parse")
            // The slug has to survive being put in a URL and read back out.
            guard let url = URL(string: app.triggerURL) else {
                Issue.record("\(app.name) trigger link should parse")
                continue
            }
            #expect(GatedApps.isGate(url))
            #expect(GatedApps.target(of: url)?.id == app.id)
        }
    }
}
