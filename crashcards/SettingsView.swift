import SwiftUI

/// Settings tab: manage the attached folders (add / remove) and review file problems.
struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(FlagStore.self) private var flags
    @State private var importing = false
    @State private var showingProblems = false

    private var hasProblems: Bool { library.issueCount > 0 || flags.loadError != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                StatsPanels()
                foldersPanel
                libraryPanel
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top) { ScreenHeader("Settings") }
        .screenLayer(isPresented: $showingProblems) {
            FileProblemsView { showingProblems = false }
                .environment(library)
                .environment(flags)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): library.addFolder(url)
            case .failure(let error): library.importFailed(error)
            }
        }
        .overlay {
            if let message = library.importError {
                CrashAlert(title: "Couldn't add folder", message: message) {
                    library.importError = nil
                }
            }
        }
        .animation(Motion.pop, value: library.importError)
    }

    private var foldersPanel: some View {
        Panel(title: "Flashcard folders",
              footnote: "Optional. Sets also live inside the app, and both are read the same way. Files can be .md, .txt, .csv or .tsv.") {
            if library.folders.isEmpty {
                PanelRow(first: true) {
                    Text("No folders attached")
                        .font(.reading(15))
                        .foregroundStyle(Brand.inkFaint)
                }
            } else {
                ForEach(Array(library.folders.enumerated()), id: \.element.id) { index, folder in
                    PanelRow(first: index == 0) {
                        HStack(spacing: 12) {
                            PixelIcon(glyph: .folder, size: 18, color: Brand.gold)
                            Text(folder.name)
                                .font(.reading(15))
                                .foregroundStyle(Brand.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Button {
                                Haptics.tap()
                                library.removeFolder(at: folder.id)
                            } label: {
                                PixelIcon(glyph: .close, size: 14, color: Brand.mult)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressable)
                            .accessibilityLabel("Remove \(folder.name)")
                        }
                    }
                }
            }
            PanelRow(first: false) {
                PanelAction(title: "Add folder…") { importing = true }
            }
        }
    }

    private var libraryPanel: some View {
        Panel(title: "Library",
              footnote: "Crash Cards never edits your .md files. The only file it writes is \(FlagStore.filename) — in your first folder, or alongside the app's own sets when you haven't added one.") {
            PanelRow(first: true) {
                StatRow(label: "Sets loaded", value: "\(library.sets.count)")
            }
            PanelRow {
                StatRow(label: "Flagged cards", value: "\(flags.flags.count)")
            }
            PanelRow {
                Button { showingProblems = true } label: {
                    HStack(spacing: 12) {
                        PixelIcon(glyph: hasProblems ? .warning : .check, size: 18,
                                  color: hasProblems ? Brand.orange : Brand.green)
                        Text("File problems")
                            .font(.brandLabel)
                            .foregroundStyle(Brand.ink)
                        Spacer(minLength: 12)
                        Text("\(library.issueCount)")
                            .font(.brandNumber)
                            .foregroundStyle(hasProblems ? Brand.orange : Brand.inkDim)
                        PixelIcon(glyph: .chevron, size: 14, color: Brand.inkFaint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
        }
    }
}
