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
            ForEach(Array(formats.enumerated()), id: \.element.name) { index, format in
                PanelRow(first: index == 0) {
                    StatRow(label: format.name, value: format.extensions)
                }
            }
        }
    }

    /// One row per format, not per extension — Markdown reads both `.md` and `.markdown`,
    /// and two rows saying "Markdown" is two rows saying one thing. An extension with no
    /// nicer name still gets its own row, so adding one to the scanner can't hide it here.
    private var formats: [(name: String, extensions: String)] {
        var order: [String] = []
        var byName: [String: [String]] = [:]
        for ext in SetFile.allExtensions {
            let name = Self.name(of: ext)
            if byName[name] == nil { order.append(name) }
            byName[name, default: []].append(".\(ext)")
        }
        return order.map { ($0, byName[$0]!.joined(separator: "  ")) }
    }

    private static func name(of ext: String) -> String {
        switch ext {
        case "md", "markdown": return "Markdown"
        case "txt", "text":    return "Plain text"
        case "csv":            return "Comma-separated"
        case "tsv":            return "Tab-separated"
        default:               return ext.uppercased()
        }
    }
}
