import SwiftUI
import UniformTypeIdentifiers

/// Bring cards in from anywhere: paste them, fetch a URL, or open a file.
///
/// Whatever the source, you see the parsed cards before anything is saved — a wrong guess
/// about the format is then obvious, and the layout picker fixes it.
struct ImportSetView: View {
    /// Text handed in by the share sheet, when the import didn't start here.
    var initialText: String = ""
    let onSaved: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var title = ""
    @State private var layout: ImportParser.Layout?
    @State private var urlString = ""
    @State private var fetching = false
    @State private var importingFile = false
    @State private var error: String?
    @State private var saveToFolder = true

    private var result: ImportParser.Result? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return ImportParser.parse(text, as: layout, title: effectiveTitle)
    }
    private var effectiveTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Imported Set" : trimmed
    }

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                if let result {
                    previewSection(result)
                    destinationSection
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("New Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(result?.cards.isEmpty ?? true)
                }
            }
            .fileImporter(isPresented: $importingFile,
                          allowedContentTypes: [.plainText, .commaSeparatedText, .text, .data]) { result in
                load(from: result)
            }
            .onAppear { if text.isEmpty { text = initialText } }
        }
    }

    // MARK: - Sections

    private var sourceSection: some View {
        Section {
            TextField("Set name", text: $title)
            TextEditor(text: $text)
                .frame(minHeight: 140)
                .font(.callout.monospaced())
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Paste your cards here")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                TextField("Or fetch a link", text: $urlString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button(fetching ? "Fetching…" : "Fetch") { Task { await fetch() } }
                    .disabled(urlString.isEmpty || fetching)
            }
            Button("Open a File…") { importingFile = true }
        } footer: {
            Text("Quizlet: open a set → Export → copy, and paste it above. Google Docs: share the doc so anyone with the link can view, then paste the link.")
        }
    }

    private func previewSection(_ result: ImportParser.Result) -> some View {
        Section {
            Picker("Format", selection: layoutBinding(result.layout)) {
                ForEach(ImportParser.Layout.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            ForEach(result.cards.prefix(8)) { card in
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.prompt).font(.subheadline)
                    Text(card.answer).font(.caption).foregroundStyle(.secondary)
                }
            }
            if result.cards.count > 8 {
                Text("and \(result.cards.count - 8) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(result.cards.count == 1 ? "1 card found" : "\(result.cards.count) cards found")
        } footer: {
            if result.skipped > 0 {
                Text("\(result.skipped) line\(result.skipped == 1 ? "" : "s") didn't look like a card and won't be imported. Try another format above if that's wrong.")
            }
        }
    }

    @ViewBuilder private var destinationSection: some View {
        if library.hasFolders {
            Section {
                Picker("Save to", selection: $saveToFolder) {
                    Text(library.folders.first?.name ?? "My folder").tag(true)
                    Text("In the app").tag(false)
                }
            } footer: {
                Text("Saved as a new .md file. Existing files are never changed.")
            }
        }
    }

    private func layoutBinding(_ detected: ImportParser.Layout) -> Binding<ImportParser.Layout> {
        Binding(get: { layout ?? detected }, set: { layout = $0 })
    }

    // MARK: - Actions

    /// Google Docs links are pages, not text — ask Docs for the plain-text export instead.
    private func fetch() async {
        guard var url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else {
            error = "That doesn't look like a link."
            return
        }
        if let exportable = ImportSetView.googleDocsExport(url) { url = exportable }
        fetching = true
        defer { fetching = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                error = "The link returned \(http.statusCode). If it's a Google Doc, set sharing to “anyone with the link”."
                return
            }
            guard let fetched = String(data: data, encoding: .utf8) else {
                error = "That link didn't return text."
                return
            }
            text = fetched
            layout = nil
            if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// docs.google.com/document/d/<id>/edit → the same doc exported as plain text.
    static func googleDocsExport(_ url: URL) -> URL? {
        guard url.host?.contains("docs.google.com") == true,
              let id = url.pathComponents.drop(while: { $0 != "d" }).dropFirst().first
        else { return nil }
        return URL(string: "https://docs.google.com/document/d/\(id)/export?format=txt")
    }

    private func load(from result: Result<URL, Error>) {
        switch result {
        case .failure(let failure):
            error = failure.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                error = "That file isn't readable as text."
                return
            }
            text = contents
            layout = nil
            if title.isEmpty { title = url.deletingPathExtension().lastPathComponent }
            error = nil
        }
    }

    private func save() {
        guard let result, !result.cards.isEmpty else { return }
        let markdown = ImportParser.markdown(title: effectiveTitle, cards: result.cards)
        do {
            if saveToFolder && library.hasFolders {
                try FolderAccess.createSetFile(named: effectiveTitle, contents: markdown)
            } else {
                try LocalLibrary.save(markdown, named: effectiveTitle)
            }
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
