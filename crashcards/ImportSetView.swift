import SwiftUI
import UniformTypeIdentifiers

/// Bring cards in from anywhere: paste them, fetch a URL, or open a file.
///
/// Whatever the source, you see the parsed cards before anything is saved — a wrong guess
/// about the format is then obvious, and the layout picker fixes it.
struct ImportSetView: View {
    /// Text handed in by the share sheet, when the import didn't start here.
    var initialText: String = ""
    var initialTitle: String = ""
    let onClose: () -> Void
    let onSaved: () -> Void

    @Environment(LibraryStore.self) private var library

    @State private var text = ""
    @State private var title = ""
    @State private var layout: ImportParser.Layout?
    @State private var urlString = ""
    @State private var fetching = false
    @State private var importingFile = false
    @State private var error: String?
    @State private var saveToFolder = true

    @State private var result: ImportParser.Result?

    /// Parsing is deliberately not a computed property: detection tries every layout, and
    /// recomputing that on each `body` pass re-parsed the whole paste on every keystroke.
    private func reparse() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result = nil
            return
        }
        result = ImportParser.parse(text, as: layout, title: effectiveTitle)
    }
    private var effectiveTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Imported Set" : trimmed
    }

    var body: some View {
        CrashModal(title: "New set",
                   confirm: (label: "Save",
                             enabled: !(result?.cards.isEmpty ?? true),
                             action: save),
                   onCancel: onClose) {
            VStack(spacing: 16) {
                sourcePanel
                if let result {
                    previewPanel(result)
                    destinationPanel
                }
                if let error {
                    Text(error)
                        .font(.reading(14))
                        .foregroundStyle(Brand.mult)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .slab(Brand.surface)
                }
            }
        }
        .fileImporter(isPresented: $importingFile,
                      allowedContentTypes: [.plainText, .commaSeparatedText, .text]) { result in
            load(from: result)
        }
        .onAppear {
            if text.isEmpty { text = initialText }
            if title.isEmpty { title = initialTitle }
            reparse()
        }
        .onChange(of: text) { _, _ in layout = nil; reparse() }
        .onChange(of: layout) { _, _ in reparse() }
    }

    // MARK: - Panels

    private var sourcePanel: some View {
        Panel(title: "Source",
              footnote: "Quizlet: open a set → Export → copy, and paste it above. Google Docs: share the doc so anyone with the link can view, then paste the link.") {
            PanelRow(first: true) {
                CrashField(placeholder: "Set name", text: $title)
            }
            PanelRow {
                CrashField(placeholder: "Paste your cards here", text: $text,
                           multiline: true, minHeight: 150, mono: true)
            }
            PanelRow {
                HStack(spacing: 10) {
                    CrashField(placeholder: "Or fetch a link", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button(fetching ? "…" : "Fetch") { Task { await fetch() } }
                        .buttonStyle(CrashButton(kind: .solid, tint: Brand.chips, fullWidth: false))
                        .disabled(urlString.isEmpty || fetching)
                        .opacity(urlString.isEmpty || fetching ? 0.45 : 1)
                }
            }
            PanelRow {
                PanelAction(title: "Open a file…") { importingFile = true }
            }
        }
    }

    private func previewPanel(_ result: ImportParser.Result) -> some View {
        Panel(title: result.cards.count == 1 ? "1 card found" : "\(result.cards.count) cards found",
              footnote: result.skipped > 0
                ? "\(result.skipped) line\(result.skipped == 1 ? "" : "s") didn't look like a card and won't be imported. Try another format above if that's wrong."
                : nil) {
            PanelRow(first: true) {
                CrashSegmented(
                    options: ImportParser.Layout.allCases.map { ($0, $0.title) },
                    selection: layoutBinding(result.layout))
            }
            ForEach(result.cards.prefix(8)) { card in
                PanelRow {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.prompt)
                            .font(.reading(15))
                            .foregroundStyle(Brand.ink)
                        Text(card.answer)
                            .font(.reading(13))
                            .foregroundStyle(Brand.inkDim)
                    }
                }
            }
            if result.cards.count > 8 {
                PanelRow {
                    Text("and \(result.cards.count - 8) more")
                        .font(.brandCaption)
                        .foregroundStyle(Brand.inkFaint)
                }
            }
        }
    }

    @ViewBuilder private var destinationPanel: some View {
        if library.hasFolders {
            Panel(title: "Save to",
                  footnote: "Saved as a new .md file. Existing files are never changed.") {
                PanelRow(first: true) {
                    CrashSegmented(
                        options: [(true, library.folders.first?.name ?? "My folder"),
                                  (false, "In the app")],
                        selection: $saveToFolder)
                }
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
            reparse()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// A Docs link exports as text, a Sheets link as CSV. Anything else is left alone —
    /// rewriting a Slides or Drive link would just 404 with a misleading explanation.
    static func googleDocsExport(_ url: URL) -> URL? {
        guard url.host?.contains("docs.google.com") == true,
              let id = url.pathComponents.drop(while: { $0 != "d" }).dropFirst().first
        else { return nil }
        if url.pathComponents.contains("document") {
            return URL(string: "https://docs.google.com/document/d/\(id)/export?format=txt")
        }
        if url.pathComponents.contains("spreadsheets") {
            return URL(string: "https://docs.google.com/spreadsheets/d/\(id)/export?format=csv")
        }
        return nil
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
            if title.isEmpty { title = SetFile.title(from: url.lastPathComponent) }
            error = nil
            reparse()
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
            Haptics.correct()
            onSaved()
            onClose()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
