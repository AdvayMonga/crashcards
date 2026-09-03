import SwiftUI

/// Settings: manage the attached flashcard folders (add / remove).
struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(FlagStore.self) private var flags
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false

    var body: some View {
        NavigationStack {
            List {
                Section("Flashcard Folders") {
                    if library.folders.isEmpty {
                        Text("No folders attached").foregroundStyle(.secondary)
                    } else {
                        ForEach(library.folders) { folder in
                            Label(folder.name, systemImage: "folder")
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { library.folders[$0].id }
                            for id in ids.sorted(by: >) { library.removeFolder(at: id) }
                        }
                    }
                    Button { importing = true } label: {
                        Label("Add Folder…", systemImage: "plus")
                    }
                }
                Section("Focus") {
                    NavigationLink {
                        BlockingView()
                    } label: {
                        Label("App Blocking", systemImage: "hand.raised")
                    }
                }

                Section {
                    LabeledContent("Sets loaded", value: "\(library.sets.count)")
                    LabeledContent("Flagged cards", value: "\(flags.flags.count)")
                } footer: {
                    Text("Flagged cards are listed in \(FlagStore.filename) in your first folder.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { library.addFolder(url) }
            }
        }
    }
}
