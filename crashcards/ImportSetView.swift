import SwiftUI

/// Attach a folder of flashcard files — the one way cards get in.
///
/// Lists the formats the folder scan reads, so you know what belongs in the folder, then
/// hands you the system folder picker. Nothing is written: the files stay yours.
struct ImportSetView: View {
    let onClose: () -> Void

    @Environment(LibraryStore.self) private var library
    @State private var importingFolder = false

    var body: some View {
        CrashModal(title: "New set", onCancel: onClose) {
            VStack(spacing: 16) {
                formatsPanel
                Panel {
                    PanelRow(first: true) {
                        PanelAction(title: "Open a folder…") { importingFolder = true }
                    }
                }
            }
        }
        .fileImporter(isPresented: $importingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                library.addFolder(url)
                if library.importError == nil { onClose() }
            case .failure(let error):
                library.importFailed(error)
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

    /// Read off `SetFile`, so the page can't offer a format the scan won't read.
    private var formatsPanel: some View {
        Panel(title: "Deck formats") {
            ForEach(Array(SetFile.allExtensions.enumerated()), id: \.element) { index, ext in
                PanelRow(first: index == 0) {
                    StatRow(label: ImportSetView.name(of: ext), value: ".\(ext)")
                }
            }
        }
    }

    private static func name(of ext: String) -> String {
        switch ext {
        case "md", "markdown": return "Markdown"
        case "txt", "text":    return "Plain text"
        case "csv":            return "Comma-separated"
        case "tsv":            return "Tab-separated"
        default:               return "Text"
        }
    }
}
