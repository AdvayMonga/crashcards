import SwiftUI
import UIKit

/// The app's visual language, in one place.
///
/// Two decisions carry most of the personality: everything is set in SF Rounded, and every
/// button sits on a ledge it presses into. Both are cheap, native, and unlike the default
/// look you get for free — which is the point.
enum Brand {
    static let accent = Color("AccentColor")
    static let correct = Color(red: 0.22, green: 0.72, blue: 0.45)
    static let wrong = Color(red: 0.91, green: 0.35, blue: 0.38)

    /// Page background, and the card that floats on it.
    static let canvas = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let hairline = Color.primary.opacity(0.08)

    static let cardRadius: CGFloat = 28
    static let controlRadius: CGFloat = 18
}

extension Font {
    /// SF Rounded at a given size — the app's single typeface.
    static func brand(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let brandDisplay = brand(30, .bold)
    static let brandTitle = brand(24, .bold)
    static let brandCard = brand(27, .semibold)
    static let brandBody = brand(17, .medium)
    static let brandLabel = brand(15, .semibold)
    static let brandCaption = brand(13, .medium)
}

/// Feedback you feel: a tap to confirm, a knock for right, a buzz for wrong.
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func knock() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }

    static func correct() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func wrong() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

/// A button that sits on a ledge and presses into it. `tint` colours the solid kind.
struct CrashButton: ButtonStyle {
    enum Kind {
        case solid      // the one thing to do here
        case soft       // secondary, tinted but quiet
        case ghost      // text only
    }

    var kind: Kind = .solid
    var tint: Color = Brand.accent
    var fullWidth = true

    private var depth: CGFloat { kind == .ghost ? 0 : 4 }

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        return configuration.label
            .font(.brandLabel)
            .foregroundStyle(foreground)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 15)
            .padding(.horizontal, 22)
            .background(
                RoundedRectangle(cornerRadius: Brand.controlRadius, style: .continuous)
                    .fill(background)
            )
            .background(alignment: .bottom) {
                // The ledge: a slice of darker colour the button sinks into when pressed.
                RoundedRectangle(cornerRadius: Brand.controlRadius, style: .continuous)
                    .fill(ledge)
                    .offset(y: pressed ? 0 : depth)
            }
            .offset(y: pressed ? depth : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: pressed)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch kind {
        case .solid: return .white
        case .soft, .ghost: return tint
        }
    }
    private var background: Color {
        switch kind {
        case .solid: return tint
        case .soft: return tint.opacity(0.14)
        case .ghost: return .clear
        }
    }
    private var ledge: Color {
        switch kind {
        case .solid: return tint.opacity(0.55)
        case .soft: return tint.opacity(0.22)
        case .ghost: return .clear
        }
    }
}

extension ButtonStyle where Self == CrashButton {
    static var solid: CrashButton { CrashButton(kind: .solid) }
    static var soft: CrashButton { CrashButton(kind: .soft) }
    static var ghost: CrashButton { CrashButton(kind: .ghost, fullWidth: false) }
    static func solid(_ tint: Color) -> CrashButton { CrashButton(kind: .solid, tint: tint) }
}

/// A slim progress bar. Replaces "3 / 12" as the primary signal — you read a bar faster.
struct ProgressTrack: View {
    let value: Int
    let total: Int

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, CGFloat(value) / CGFloat(total))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.accent.opacity(0.14))
                Capsule()
                    .fill(Brand.accent)
                    .frame(width: max(0, geometry.size.width * fraction))
            }
        }
        .frame(height: 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: fraction)
        .accessibilityLabel("Card \(value) of \(total)")
    }
}
