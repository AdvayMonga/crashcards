import SwiftUI

// MARK: - Slabs

/// The one shape this app is built from: a flat slab, outlined in near-black, standing on a
/// darker ledge, with a soft shadow under it so it reads as lifted off the table.
///
/// `lift` is how far it stands off its ledge; pressing a control sends `lift` to zero, which
/// is what makes a tap feel like something moving rather than something recolouring.
struct Slab: ViewModifier {
    var fill: Color = Brand.surface
    var radius: CGFloat = Brand.slabRadius
    var lift: CGFloat = Brand.ledge
    /// Drawn over the fill along the top edge — the light catching the cut face.
    var highlight: Double = 0.10

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(fill)
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [.white.opacity(highlight), .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: radius)
                            .mask(shape)
                    }
                    .overlay(shape.strokeBorder(Brand.outline, lineWidth: Brand.stroke))
            }
            .background(alignment: .bottom) {
                // The ledge. Sized to the content and pushed down, so only its lip shows.
                shape.fill(fill.opacity(0.001).blended(under: Brand.outline, amount: 0.55))
                    .overlay(shape.strokeBorder(Brand.outline, lineWidth: Brand.stroke))
                    .offset(y: lift)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 4)
            }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

private extension Color {
    /// The ledge colour: the face, darkened. Done in sRGB so every tint darkens the same way.
    func blended(under other: Color, amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let t = CGFloat(amount)
        return Color(.sRGB,
                     red: Double(ar + (br - ar) * t),
                     green: Double(ag + (bg - ag) * t),
                     blue: Double(ab + (bb - ab) * t),
                     opacity: 1)
    }
}

extension View {
    /// Put this view on a slab. See `Slab`.
    func slab(_ fill: Color = Brand.surface,
              radius: CGFloat = Brand.slabRadius,
              lift: CGFloat = Brand.ledge,
              highlight: Double = 0.10) -> some View {
        modifier(Slab(fill: fill, radius: radius, lift: lift, highlight: highlight))
    }
}

// MARK: - Motion

/// The tap: squash down onto the ledge, then spring back past where it started.
///
/// Anchored at the bottom so the slab compresses into its own ledge instead of shrinking
/// towards its middle — the difference between something being pressed and something
/// being scaled.
struct Squash: ViewModifier {
    let pressed: Bool
    var depth: CGFloat = Brand.ledge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: pressed && !reduceMotion ? 1.04 : 1,
                         y: pressed && !reduceMotion ? 0.94 : 1,
                         anchor: .bottom)
            .offset(y: pressed ? depth : 0)
            .animation(Motion.pop(reduceMotion), value: pressed)
    }
}

/// The slow idle wobble every card and slab has. Nothing in Balatro is ever quite still,
/// and it's most of why the screen feels alive rather than laid out.
struct Breathing: ViewModifier {
    var amount: Double = 1
    var period: Double = 2.6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swung = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(swung ? 0.55 * amount : -0.55 * amount))
            .offset(y: swung ? -1.5 * amount : 1.5 * amount)
            .animation(reduceMotion ? nil
                        : .easeInOut(duration: period).repeatForever(autoreverses: true),
                       value: swung)
            .onAppear { swung = true }
    }
}

/// A short, decaying shake. Bump `trigger` to fire it.
struct Shake: ViewModifier, Animatable {
    var progress: CGFloat
    var distance: CGFloat = 7

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(x: sin(progress * .pi * 6) * distance * (1 - progress))
    }
}

extension View {
    func breathing(_ amount: Double = 1, period: Double = 2.6) -> some View {
        modifier(Breathing(amount: amount, period: period))
    }

    /// Shakes once each time `trigger` changes.
    func shake(on trigger: some Hashable) -> some View {
        modifier(ShakeOnChange(trigger: AnyHashable(trigger)))
    }
}

private struct ShakeOnChange: ViewModifier {
    let trigger: AnyHashable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .modifier(Shake(progress: progress))
            .onChange(of: trigger) { _, _ in
                guard !reduceMotion else { return }
                progress = 0
                withAnimation(.easeOut(duration: 0.45)) { progress = 1 }
            }
    }
}

// MARK: - Buttons

/// A chunky slab you press into its ledge.
struct CrashButton: ButtonStyle {
    enum Kind {
        case solid      // the one thing to do here
        case soft       // secondary — the table showing through, outlined
        case ghost      // text only, no slab
    }

    var kind: Kind = .solid
    var tint: Color = Brand.gold
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        Face(kind: kind, tint: tint, fullWidth: fullWidth,
             pressed: configuration.isPressed, label: configuration.label)
    }

    /// A view rather than inline chrome so `@Environment` (Reduce Motion, `isEnabled`) resolves.
    private struct Face<Label: View>: View {
        let kind: Kind
        let tint: Color
        let fullWidth: Bool
        let pressed: Bool
        let label: Label

        /// `.disabled()` stops the tap on its own but changes nothing about how a custom
        /// style draws, so without this a dead button is indistinguishable from a live one.
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let content = label
                .font(.brandLabel)
                .foregroundStyle(foreground)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.vertical, 14)
                .padding(.horizontal, 22)

            Group {
                if kind == .ghost {
                    content.opacity(pressed ? 0.55 : 1)
                } else {
                    content
                        // Sunk flat when dead: a slab still standing off its ledge reads
                        // as something waiting to be pressed.
                        .slab(background, lift: pressed || !isEnabled ? 0 : Brand.ledge,
                              highlight: kind == .solid ? 0.22 : 0.06)
                        .modifier(Squash(pressed: pressed))
                }
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : Brand.deadOpacity)
            .saturation(isEnabled ? 1 : Brand.deadSaturation)
        }

        private var foreground: Color {
            switch kind {
            case .solid: return Brand.outline
            case .soft, .ghost: return tint
            }
        }

        private var background: Color {
            switch kind {
            case .solid: return tint
            case .soft: return Brand.surface
            case .ghost: return .clear
            }
        }
    }
}

extension ButtonStyle where Self == CrashButton {
    static var solid: CrashButton { CrashButton(kind: .solid) }
    static var soft: CrashButton { CrashButton(kind: .soft) }
    static var ghost: CrashButton { CrashButton(kind: .ghost, fullWidth: false) }
    static func solid(_ tint: Color) -> CrashButton { CrashButton(kind: .solid, tint: tint) }
    static func soft(_ tint: Color) -> CrashButton { CrashButton(kind: .soft, tint: tint) }
}

/// Any view made tappable with the house press, for rows and cards that aren't buttons.
struct PressableRow: ButtonStyle {
    var depth: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        Face(depth: depth, pressed: configuration.isPressed, label: configuration.label)
    }

    /// A view so `isEnabled` resolves — see `CrashButton.Face`.
    private struct Face<Label: View>: View {
        let depth: CGFloat
        let pressed: Bool
        let label: Label

        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .modifier(Squash(pressed: pressed, depth: depth))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : Brand.deadOpacity)
                .saturation(isEnabled ? 1 : Brand.deadSaturation)
        }
    }
}

extension ButtonStyle where Self == PressableRow {
    static var pressable: PressableRow { PressableRow() }
}

/// A square header button — the app's answer to a toolbar item.
struct HeaderChip: View {
    let glyph: PixelGlyph
    let name: String
    var tint: Color = Brand.inkDim
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            PixelIcon(glyph: glyph, size: 18, color: tint)
                .frame(width: 40, height: 40)
                .slab(Brand.surface, radius: 10, lift: 3)
                .frame(minWidth: 44, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(name)
    }
}

// MARK: - Panels

/// A titled group of rows. Replaces `List`/`Form`: one slab, hairline dividers, our type.
struct Panel<Content: View>: View {
    var title: String?
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.brandCaption)
                    .tracking(1.2)
                    .foregroundStyle(Brand.gold)
                    .padding(.horizontal, 6)
            }
            VStack(spacing: 0) { content }
                .slab(Brand.surface, radius: Brand.cardRadius)
            if let footnote {
                Text(footnote)
                    .font(.reading(13))
                    .foregroundStyle(Brand.inkFaint)
                    .padding(.horizontal, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, Brand.ledge)
    }
}

/// A line inside a `Panel`. Dividers are drawn by the row so the panel stays a plain stack.
struct PanelRow<Content: View>: View {
    var first = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            if !first {
                Rectangle()
                    .fill(Brand.outline.opacity(0.45))
                    .frame(height: 1.5)
            }
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A button that *is* a panel row. A `CrashButton` here would add its own padding on top
/// of the row's, which is what made these rows twice as tall as the ones around them.
struct PanelAction: View {
    let title: String
    var tint: Color = Brand.gold
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 0) {
                Text(title).font(.brandLabel).foregroundStyle(tint)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }
}

/// `label — value`, the shape most settings rows take.
struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(.brandLabel).foregroundStyle(Brand.ink)
            Spacer(minLength: 12)
            Text(value).font(.brandNumber).foregroundStyle(Brand.gold)
        }
    }
}

// MARK: - Controls

/// A chunky switch. The knob is a square that slides between two ends of an outlined track.
struct CrashToggle: View {
    let label: String
    @Binding var isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            Haptics.select()
            isOn.toggle()
        } label: {
            HStack {
                Text(label).font(.brandLabel).foregroundStyle(Brand.ink)
                Spacer(minLength: 12)
                track
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private var track: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isOn ? Brand.green : Brand.surfaceLedge)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Brand.outline, lineWidth: Brand.stroke))
                .frame(width: 58, height: 32)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Brand.cardFace)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Brand.outline, lineWidth: 2))
                .frame(width: 22, height: 22)
                .padding(.horizontal, 5)
        }
        .animation(Motion.pop(reduceMotion), value: isOn)
    }
}

/// A number you nudge between two ends. Replaces `Stepper`.
///
/// The two keys are slabs you press like any other control, and the number between them is
/// in the display face — it's the thing being changed, so it's the thing you read.
struct CrashStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    /// Rendered value, so "10" can read as "10 min" without the binding carrying a string.
    var format: (Int) -> String = { "\($0)" }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.brandLabel)
                .foregroundStyle(Brand.ink)
            Spacer(minLength: 8)

            key(.minus, by: -step, enabled: value > range.lowerBound)

            Text(format(value))
                .font(.brandNumber)
                .foregroundStyle(Brand.gold)
                .monospacedDigit()
                .frame(minWidth: 62)
                .contentTransition(.numericText())

            key(.plus, by: step, enabled: value < range.upperBound)
        }
    }

    /// A key at the end of its range is drawn dead by the style, like every other control.
    private func key(_ glyph: PixelGlyph, by delta: Int, enabled: Bool) -> some View {
        Button {
            Haptics.tap()
            value = min(range.upperBound, max(range.lowerBound, value + delta))
        } label: {
            PixelIcon(glyph: glyph, size: 14, color: Brand.outline)
                .frame(width: 38, height: 34)
                .slab(Brand.gold, radius: 9, lift: 3, highlight: 0.22)
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .accessibilityLabel(delta > 0 ? "Increase \(label)" : "Decrease \(label)")
    }
}

/// A grid of slabs where exactly one is lit. Replaces `Picker`.
///
/// It wraps rather than squeezing: the import screen offers seven formats, and seven labels
/// across one row is seven truncated labels.
struct CrashSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var perRow: Int { min(options.count, 3) }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(stride(from: 0, to: options.count, by: perRow)), id: \.self) { start in
                HStack(spacing: 8) {
                    ForEach(options[start..<min(start + perRow, options.count)], id: \.value) {
                        option in cell(option)
                    }
                    // Keeps a short last row's cells the same width as the rows above it.
                    ForEach(0..<max(0, start + perRow - options.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
        .animation(Motion.pop(reduceMotion), value: selection)
    }

    private func cell(_ option: (value: Value, title: String)) -> some View {
        let on = option.value == selection
        return Button {
            Haptics.select()
            selection = option.value
        } label: {
            Text(option.title)
                .font(.brandCaption)
                .foregroundStyle(on ? Brand.outline : Brand.inkDim)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
                .slab(on ? Brand.gold : Brand.surfaceLedge, radius: 9,
                      lift: on ? 0 : 3, highlight: on ? 0.22 : 0.04)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

/// A text box drawn by us: sunk into the slab rather than standing on it, with a gold caret.
struct CrashField: View {
    let placeholder: String
    @Binding var text: String
    var multiline = false
    var minHeight: CGFloat = 0
    var mono = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Brand.surfaceLedge)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Brand.outline, lineWidth: Brand.stroke))

            if text.isEmpty {
                Text(placeholder)
                    .font(.brandCaption)
                    .foregroundStyle(Brand.inkFaint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, multiline ? 14 : 12)
                    .allowsHitTesting(false)
            }

            field
                .font(mono ? .system(size: 14, design: .monospaced) : .reading(16))
                .foregroundStyle(Brand.ink)
                .tint(Brand.gold)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, multiline ? 6 : 4)
        }
        .frame(minHeight: max(minHeight, 46))
    }

    @ViewBuilder private var field: some View {
        if multiline {
            TextEditor(text: $text)
        } else {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
        }
    }
}

// MARK: - Cards

/// A playing card: cream stock, a near-black edge, an inner frame line in the suit's colour,
/// and a shadow that belongs to the stock rather than to what's printed on it.
///
/// Every card in the app comes through here — a flashcard, a quiz question, and the two
/// faces the unlock gate turns over — so a card is one object wherever you meet it.
struct CardFace<Content: View>: View {
    var tint: Color = Brand.gold
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                .fill(Brand.cardFace)
                .shadow(color: .black.opacity(0.5), radius: 16, y: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.cardRadius - 6, style: .continuous)
                        .strokeBorder(tint.opacity(0.45), lineWidth: 2)
                        .padding(9))
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                        .strokeBorder(Brand.outline, lineWidth: 3))
            content
        }
    }
}

/// The rank in a card's corner, printed in both opposite corners the way a real one is.
struct CardIndex: View {
    let text: String
    var tint: Color = Brand.gold

    var body: some View {
        VStack {
            HStack {
                mark
                Spacer()
            }
            Spacer()
            HStack {
                Spacer()
                mark.rotationEffect(.degrees(180))
            }
        }
        .padding(16)
    }

    private var mark: some View {
        Text(text).font(.pixel(30)).foregroundStyle(tint)
    }
}

/// Turns a stack of faces over, one half-turn at a time.
///
/// `turn` counts half-turns: 0 shows face 0, 1 shows face 1, and the card is edge-on at
/// every half. Driving it from a single number is what lets the card do more than rotate —
/// it lunges towards you as it passes edge-on, which is what stops a 3D rotation from
/// reading as a page turning.
struct CardFlipper<Face: View>: View, Animatable {
    var turn: Double
    @ViewBuilder var face: (Int) -> Face

    var animatableData: Double {
        get { turn }
        set { turn = newValue }
    }

    var body: some View {
        let index = max(0, Int(turn.rounded()))
        let lunge = abs(sin(min(max(turn, 0), .greatestFiniteMagnitude) * .pi))

        face(index)
            // An odd half-turn lands the card mirrored; undo that on the content alone.
            .rotation3DEffect(.degrees(index.isMultiple(of: 2) ? 0 : 180),
                              axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(.degrees(turn * 180), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(1 + 0.09 * lunge)
            .offset(y: -14 * lunge)
    }
}

// MARK: - Readouts

/// A chunky progress bar. Outlined like everything else, and filled in gold.
struct ProgressTrack: View {
    let value: Int
    let total: Int
    /// What the bar is counting. Callers count different things, so none of them can share
    /// a baked-in "Card N of M".
    let label: String
    var tint: Color = Brand.gold

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, CGFloat(value) / CGFloat(total))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Brand.surfaceLedge)

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint)
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [.white.opacity(0.3), .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 5)
                    }
                    .frame(width: max(0, geometry.size.width * fraction))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Brand.outline, lineWidth: 2))
        }
        .frame(height: 14)
        .animation(Motion.settle, value: fraction)
        .accessibilityLabel(label)
    }
}

/// The screen title. Drawn by us — the navigation bar would set it in the system face.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.brandDisplay)
                .foregroundStyle(Brand.ink)
                .shadow(color: Brand.outline, radius: 0, x: 2, y: 3)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// Nothing here yet — and what to do about it. Replaces `ContentUnavailableView`.
struct EmptyState<Actions: View>: View {
    let glyph: PixelGlyph
    let title: String
    let message: String
    var tint: Color = Brand.inkDim
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 16) {
            PixelIcon(glyph: glyph, size: 54, color: tint)
                .padding(22)
                .slab(Brand.surface, radius: Brand.cardRadius)
                .breathing(1.4, period: 3.4)
                .padding(.bottom, 6)

            Text(title)
                .font(.brandTitle)
                .foregroundStyle(Brand.ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.reading(16))
                .foregroundStyle(Brand.inkDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) { actions }
                .padding(.top, 8)
        }
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyState where Actions == EmptyView {
    init(glyph: PixelGlyph, title: String, message: String, tint: Color = Brand.inkDim) {
        self.init(glyph: glyph, title: title, message: message, tint: tint) { EmptyView() }
    }
}
