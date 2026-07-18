import SwiftUI

/// First-run screen: pick the flashcards folder via the system Files picker.
struct FolderSetupView: View {
    @Environment(LibraryStore.self) private var library
    @State private var importing = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            Text("Choose your flashcards folder")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Pick the folder in your Obsidian vault that holds your .md sets. Each file becomes a set.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose Folder") { importing = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            if let error = library.loadError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { library.addFolder(url) }
        }
    }
}
