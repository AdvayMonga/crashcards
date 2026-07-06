import SwiftUI

/// Minimal settings: see and change the flashcards folder.
struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false

    var body: some View {
        NavigationStack {
            List {
                Section("Flashcards Folder") {
                    LabeledContent("Current", value: FolderAccess.folderName ?? "None")
                    Button("Change Folder…") { importing = true }
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
                if case .success(let url) = result { library.setFolder(url) }
            }
        }
    }
}
