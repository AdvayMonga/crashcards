import SwiftUI

@main
struct CrashcardsApp: App {
    @State private var library = LibraryStore()
    @State private var flags = FlagStore()
    @State private var blocking = ScreenTimeManager()
    @State private var stats = StatsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(flags)
                .environment(blocking)
                .environment(stats)
        }
    }
}
