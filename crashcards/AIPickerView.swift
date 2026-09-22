import SwiftUI
import UIKit

/// Which chatbot to hand a prompt to, asked at the moment of handing it over.
///
/// Explain can't name one in its own label — the app has no allegiance to a provider and
/// no way to know which you pay for — so the button says "AI" and this asks. The prompt
/// reaches the clipboard whichever you pick, because not every provider can be prefilled.
/// A prompt waiting for a provider. Identifiable so it can drive a `screenLayer`, which a
/// bare String can't.
struct ExplainRequest: Identifiable {
    let id = UUID()
    let prompt: String
}

struct AIPickerView: View {
    let prompt: String
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    /// Whichever you reached for last sits at the top, so a habit costs one tap.
    private var ordered: [AIProvider] {
        let first = AIProvider.preferred
        return [first] + AIProvider.all.filter { $0.id != first.id }
    }

    var body: some View {
        CrashModal(title: "Explain with", onCancel: onClose) {
            Panel(footnote: "Opens a chat with the question already in it. The prompt is copied too, so you can paste it anywhere else.") {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, provider in
                    PanelRow(first: index == 0) {
                        PanelAction(title: provider.name, tint: Brand.chips) { hand(to: provider) }
                    }
                }
            }
        }
    }

    private func hand(to provider: AIProvider) {
        Prefs.preferredProviderID = provider.id   // the one offered first next time
        UIPasteboard.general.string = prompt
        if let url = provider.url(prompt: prompt) { openURL(url) }
        onClose()
    }
}
