import SwiftUI

/// Shown instead of a study screen when the selected sets can't supply what the mode needs —
/// e.g. Quiz mode on sets that only contain `::` flip cards.
///
/// Says what's missing and, when the fix is a file edit, the exact format to write.
struct ModeUnavailableView: View {
    let mode: StudyMode
    let reason: ModeUnavailable
    let onClose: () -> Void

    var body: some View {
        ZStack {
            TableBackground()

            VStack(spacing: 16) {
                Spacer()

                PixelIcon(glyph: glyph, size: 54, color: Brand.inkDim)
                    .padding(22)
                    .slab(Brand.surface, radius: Brand.cardRadius)
                    .breathing(1.2, period: 3.4)

                Text(reason.title)
                    .font(.brandTitle)
                    .foregroundStyle(Brand.ink)
                    .multilineTextAlignment(.center)

                Text(reason.message)
                    .font(.reading(15))
                    .foregroundStyle(Brand.inkDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let expected = reason.expected {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(expected)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Brand.ink)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Brand.surfaceLedge)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Brand.outline, lineWidth: 2))
                    }
                }

                Spacer()
                Button("Back to sets") { onClose() }
                    .buttonStyle(.solid)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 26)
        }
        .safeAreaInset(edge: .top) { header }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HeaderChip(glyph: .close, name: "Close") { onClose() }
            Text(mode.title)
                .font(.brandTitle)
                .foregroundStyle(Brand.ink)
                .shadow(color: Brand.outline, radius: 0, x: 2, y: 2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private var glyph: PixelGlyph {
        switch reason {
        case .noSetsSelected: return .cards
        case .noCards:        return .folder
        case .noQuestions:    return .question
        }
    }
}
