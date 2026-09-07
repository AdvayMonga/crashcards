import SwiftUI

@main
struct FlashcardsApp: App {
    @State private var library = LibraryStore()
    @State private var flags = FlagStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(flags)
        }
    }
}
