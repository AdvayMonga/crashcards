import SwiftUI

/// Settings: manage the attached flashcard folders (add / remove).
struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
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
                Section {
                    LabeledContent("Sets loaded", value: "\(library.sets.count)")
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
