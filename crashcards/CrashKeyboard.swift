import SwiftUI

/// The quiz's own keyboard, drawn in slabs like every other control.
///
/// The system keyboard slides up over the bottom of the screen and shrinks the safe area
/// as it comes, which shoved the header and the question up with it. This one is laid
/// out as part of the screen instead — it never arrives or leaves, so nothing above it
/// ever moves. Letters and figures are two layers, the way a phone keyboard does it.
struct CrashKeyboard: View {
    @Binding var text: String
    /// Whether the check key is live — a blank answer can't be submitted.
    let canSubmit: Bool
    let onSubmit: () -> Void

    @State private var figures = false

    static let keyHeight: CGFloat = 42
    static let gap: CGFloat = 7
    /// Four rows, fixed, so whatever sits above the keyboard can be held still.
    static let height: CGFloat = 4 * keyHeight + 3 * gap

    private static let letterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    private static let figureRows = ["1234567890", "-/:()'&.,", "?!\";@#$"]

    var body: some View {
        GeometryReader { geo in
            // Ten keys and nine gaps across the top row; every other key is cut from that.
            let unit = (geo.size.width - 9 * Self.gap) / 10
            let rows = figures ? Self.figureRows : Self.letterRows
            VStack(spacing: Self.gap) {
                keys(rows[0], unit: unit)
                keys(rows[1], unit: unit)
                HStack(spacing: Self.gap) {
                    keys(rows[2], unit: unit)
                    Key(width: 2 * unit + Self.gap, name: "Delete") {
                        _ = text.popLast()
                    } label: {
                        PixelIcon(glyph: .backspace, size: 18, color: Brand.ink)
                    }
                }
                HStack(spacing: Self.gap) {
                    Key(width: 2 * unit + Self.gap, name: figures ? "Letters" : "Figures") {
                        figures.toggle()
                    } label: {
                        Text(figures ? "ABC" : "123")
                            .font(.pixel(16))
                            .foregroundStyle(Brand.ink)
                    }
                    Key(width: 6 * unit + 5 * Self.gap, name: "Space") {
                        text.append(" ")
                    } label: {
                        Color.clear   // a wide blank key reads as space without a label
                    }
                    Key(width: 2 * unit + Self.gap, tint: Brand.chips, name: "Check answer",
                        action: onSubmit) {
                        PixelIcon(glyph: .check, size: 18, color: Brand.outline)
                    }
                    .disabled(!canSubmit)
                }
            }
            .frame(width: geo.size.width)
        }
        .frame(height: Self.height)
    }

    private func keys(_ row: String, unit: CGFloat) -> some View {
        HStack(spacing: Self.gap) {
            ForEach(Array(row), id: \.self) { char in
                Key(width: unit, name: String(char)) {
                    text.append(char)
                } label: {
                    // The pixel face for letters; figures in the screen face, where a 5
                    // can't be mistaken for a 2 — see `Font.number`.
                    Text(String(char).uppercased())
                        .font(figures ? .number(18) : .pixel(20))
                        .foregroundStyle(Brand.ink)
                }
            }
        }
    }
}

/// One key: a small slab that presses into its ledge.
private struct Key<Label: View>: View {
    let width: CGFloat
    var tint: Color = Brand.surface
    let name: String
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            label
                .frame(width: width, height: CrashKeyboard.keyHeight)
                .slab(tint, radius: 8, lift: 3, highlight: 0.12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(name)
    }
}
