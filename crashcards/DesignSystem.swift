import SwiftUI
import UIKit

/// The app's visual language, in one place.
///
/// The look is borrowed from Balatro: a dark felt table, chunky slabs outlined in near-black,
/// every control sitting on a ledge it presses into, a pixel typeface, and motion that
/// overshoots instead of easing. Nothing here is a system default — the palette is fixed
/// rather than adaptive, the face is bundled, and the springs are ours.
enum Brand {

    // MARK: - The table

    /// Deepest point of the felt, and the lighter sweep the background animates through.
    static let tableDeep = Color(hex: 0x16222C)
    static let tableLift = Color(hex: 0x2B4254)

    /// A raised slab: panels, rows, headers. `surfaceHigh` is the one a finger is on.
    static let surface = Color(hex: 0x30414E)
    static let surfaceHigh = Color(hex: 0x3C5060)
    /// The shadow side of a slab — the ledge it sits on.
    static let surfaceLedge = Color(hex: 0x1C2A34)

    /// Playing-card stock, and the ink printed on it.
    static let cardFace = Color(hex: 0xF4EFE2)
    static let cardInk = Color(hex: 0x21282E)

    /// The near-black every shape is outlined in. This single line does most of the work.
    static let outline = Color(hex: 0x0E1519)

    // MARK: - Text

    static let ink = Color(hex: 0xF2EDE1)
    static let inkDim = Color(hex: 0x9DAEBB)
    static let inkFaint = Color(hex: 0x6B7F8D)

    // MARK: - Accents, named for what Balatro counts with them

    /// Chips. The primary action.
    static let chips = Color(hex: 0x009DFF)
    /// Mult. Wrong answers, destructive things.
    static let mult = Color(hex: 0xFE5F55)
    /// Money. Highlights, scores, the selected state.
    static let gold = Color(hex: 0xF0C040)
    /// Right answers, and an unlocked shield.
    static let green = Color(hex: 0x4BC292)
    /// The second study mode.
    static let purple = Color(hex: 0x9A6FC4)
    /// Warnings — file problems.
    static let orange = Color(hex: 0xFDA200)

    static let accent = gold

    // MARK: - Metrics

    /// Corners are modest: a slab reads as cut, not as a pill.
    static let slabRadius: CGFloat = 12
    static let cardRadius: CGFloat = 16
    /// Outline weight. Thick enough to be the shape's edge, not a hairline on it.
    static let stroke: CGFloat = 2.5
    /// How far a control stands off its ledge before you press it.
    static let ledge: CGFloat = 5
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Type

/// Pixelify Sans, bundled, for words. A pixel face needs whole-pixel sizes to stay crisp,
/// so every size here is even. Figures use ``number(_:)`` instead.
extension Font {
    private static let display = "PixelifySans-Bold"
    private static let text = "PixelifySans-Regular"

    /// The pixel face, snapped to the font's own grid.
    ///
    /// A pixel face only draws cleanly at whole multiples of the grid it was drawn on. Off
    /// the grid, the renderer splits single-pixel strokes across two device pixels and the
    /// whole face goes soft, so `relativeTo` is dropped: Dynamic Type scales by fractional
    /// factors, which would put every size back off the grid. Long text uses ``reading``,
    /// which is a system face and scales properly.
    ///
    /// Crispness was not what made the figures hard to read — see ``number(_:)``.
    static func pixel(_ size: CGFloat, bold: Bool = true,
                      relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(bold ? display : text, fixedSize: (size / grid).rounded() * grid)
    }

    /// Pixelify Sans is drawn on a 2-unit grid, so even sizes land on whole pixels.
    private static let grid: CGFloat = 2

    /// Long card text stays in a screen face — a pixel font at reading length is a chore.
    static func reading(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let brandDisplay = pixel(34, relativeTo: .largeTitle)
    static let brandTitle = pixel(26, relativeTo: .title)
    static let brandLabel = pixel(18, relativeTo: .headline)
    static let brandCaption = pixel(15, bold: false, relativeTo: .caption)
    /// Figures, in the screen face rather than the pixel one.
    ///
    /// Pixelify Sans draws `5` with a squared-off top arm that reads as a reversed `2` —
    /// fine in a word, bad in a score, where a digit has to be unambiguous at a glance.
    /// Words keep the pixel face; only figures move.
    static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Numbers carry the score, so they read a size up from a label.
    static let brandNumber = number(26)

    /// The two faces used for card and answer text, where length varies wildly.
    static let brandCard = reading(26, .semibold)
    static let brandBody = reading(17, .medium)
}

// MARK: - Motion

/// One motion vocabulary, so nothing in the app eases the way iOS eases by default.
///
/// Everything overshoots a little. `pop` is the house spring; `snap` is for things that
/// must land before you look away; `settle` is for layout that shouldn't draw the eye.
enum Motion {
    static let pop = Animation.spring(response: 0.30, dampingFraction: 0.58)
    static let snap = Animation.spring(response: 0.20, dampingFraction: 0.72)
    static let settle = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let deal = Animation.spring(response: 0.38, dampingFraction: 0.72)

    /// Reduce Motion gets the same timing without the overshoot, so nothing jumps.
    static func pop(_ reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.18) : pop
    }
    static func deal(_ reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.2) : deal
    }
}

/// Feedback you feel: a tap to confirm, a knock for right, a buzz for wrong.
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func knock() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func thud() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }

    static func correct() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func wrong() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
