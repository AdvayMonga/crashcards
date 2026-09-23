import UIKit
import UniformTypeIdentifiers

/// Accepts text, a link, or a text file from any app's share sheet and parks it for
/// Crash Cards to import. Deliberately dumb: no parsing here, so the app can show you the
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
                    await confirm("Saved to Crash Cards", detail: "Open Crash Cards to finish importing.")
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
    ///
    /// A provider answers with whichever shape it holds the type in, not the one you asked
    /// for: text typed into a share sheet arrives as a `String`, but a `.txt` or `.csv`
    /// picked in Files arrives as a file `URL` under the same `public.plain-text`. Casting
    /// straight to `String` drops every file share on the floor, so all three are unwrapped.
    private func load(_ provider: NSItemProvider) async -> (text: String, title: String)? {
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) {
            if let text = item as? String { return (text, "") }
            if let url = item as? URL, url.isFileURL { return readFile(url) }
            if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                return (text, "")
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
            guard url.isFileURL else { return (url.absoluteString, url.host ?? "") }
            return readFile(url)
        }
        return nil
    }

    /// A file handed over by another app lives outside this extension's container, and on
    /// some paths is only readable inside a security scope.
    private func readFile(_ url: URL) -> (text: String, title: String)? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return (contents, url.deletingPathExtension().lastPathComponent)
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
