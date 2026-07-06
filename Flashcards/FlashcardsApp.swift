import SwiftUI

@main
struct FlashcardsApp: App {
    @State private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
    }
}
