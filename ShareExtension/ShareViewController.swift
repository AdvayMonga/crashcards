import UIKit
import UniformTypeIdentifiers

/// Accepts text, a link, or a text file from any app's share sheet and parks it for
/// Flashcards to import. Deliberately dumb: no parsing here, so the app can show you the
/// preview before anything becomes a set.
class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await handleShare() }
    }

    private func handleShare() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let attachments = items.flatMap { $0.attachments ?? [] }

        for provider in attachments {
            if let shared = await load(provider) {
                do {
                    try SharedInbox.deposit(shared.text, title: shared.title)
                    await confirm("Saved to Flashcards", detail: "Open Flashcards to finish importing.")
                } catch {
                    await confirm("Couldn't save that", detail: error.localizedDescription)
                }
                return
            }
        }
        await confirm("Nothing to import", detail: "Share text, a link, or a text file.")
    }

    /// Text as-is; a link as its address; a file by reading it. A file or link names the
    /// set; loose text has nothing to name it with, so the app asks.
    private func load(_ provider: NSItemProvider) async -> (text: String, title: String)? {
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
            return (text, "")
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
            let name = url.deletingPathExtension().lastPathComponent
            guard url.isFileURL else { return (url.absoluteString, url.host ?? "") }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (contents, name)
        }
        return nil
    }

    @MainActor
    private func confirm(_ message: String, detail: String) async {
        let alert = UIAlertController(title: message, message: detail, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        present(alert, animated: true)
    }
}
