import Testing
import Foundation
@testable import crashcards

@Suite struct AppLinksTests {
    @Test func knownAppsResolve() {
        #expect(AppLinks.url(forAppNamed: "Instagram")?.scheme == "instagram")
        #expect(AppLinks.url(forAppNamed: "Facebook")?.scheme == "fb")
        #expect(AppLinks.url(forAppNamed: "X")?.scheme == "twitter")
    }

    /// The shield reports whatever iOS calls the app, which is not always tidy.
    @Test func namesAreNormalised() {
        #expect(AppLinks.url(forAppNamed: "TikTok") == AppLinks.url(forAppNamed: "Tik Tok"))
        #expect(AppLinks.url(forAppNamed: "youtube") != nil)
    }

    @Test func unknownAppsGetNothing() {
        #expect(AppLinks.url(forAppNamed: "Some Obscure App") == nil)
        #expect(AppLinks.url(forAppNamed: nil) == nil)
        #expect(AppLinks.url(forAppNamed: "") == nil)
    }
}
