import SwiftUI

/// Settings tab: manage the attached folders (add / remove) and review file problems.
struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(FlagStore.self) private var flags
    @State private var importing = false

    private var hasProblems: Bool { library.issueCount > 0 || flags.loadError != nil }

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                } header: {
                    Text("Flashcard Folders")
                } footer: {
                    Text("Optional. Sets also live inside the app, and both are read the same way. Files can be .md, .txt, .csv or .tsv.")
                }
                Section {
                    LabeledContent("Sets loaded", value: "\(library.sets.count)")
                    LabeledContent("Flagged cards", value: "\(flags.flags.count)")
                    NavigationLink {
                        FileProblemsView().environment(library).environment(flags)
                    } label: {
                        Label {
                            LabeledContent("File problems", value: "\(library.issueCount)")
                        } icon: {
                            Image(systemName: hasProblems
                                  ? "exclamationmark.triangle.fill" : "checkmark.circle")
                                .foregroundStyle(hasProblems ? .orange : .secondary)
                        }
                    }
                } footer: {
                    Text("Crash Cards never edits your .md files. The only file it writes is \(FlagStore.filename), in your first folder.")
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url): library.addFolder(url)
                case .failure(let error): library.importFailed(error)
                }
            }
            .alert("Couldn't add folder",
                   isPresented: .init(get: { library.importError != nil },
                                      set: { if !$0 { library.importError = nil } })) {
                Button("OK") { library.importError = nil }
            } message: {
                Text(library.importError ?? "")
            }
        }
    }
}
