import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// Crash Cards icon: the ace of locks.
//
// A single playing card on the felt table, drawn in the app's own language — cream stock,
// near-black edge, a gold inner frame, standing on its own ledge. The suit is a padlock,
// which is the app in one shape: cards are what stands in front of your apps.
//
// Run from the repo root:  swift Tools/make-icon.swift <out.png>

let outPath = CommandLine.arguments[1]
let fontPath = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "crashcards/Fonts/PixelifySans-Bold.ttf"

let size = 1024.0

// The app's palette, from Brand.
let tableDeep = NSColor(srgbRed: 0x16 / 255, green: 0x22 / 255, blue: 0x2C / 255, alpha: 1)
let tableLift = NSColor(srgbRed: 0x2B / 255, green: 0x42 / 255, blue: 0x54 / 255, alpha: 1)
let cardFace = NSColor(srgbRed: 0xF4 / 255, green: 0xEF / 255, blue: 0xE2 / 255, alpha: 1)
let outline = NSColor(srgbRed: 0x0E / 255, green: 0x15 / 255, blue: 0x19 / 255, alpha: 1)
let gold = NSColor(srgbRed: 0xF0 / 255, green: 0xC0 / 255, blue: 0x40 / 255, alpha: 1)

// An opaque context: App Store icons must carry no alpha channel at all.
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

/// The app's display face, read straight from the bundled file so the rank matches the UI.
let pixelFont: CTFont = {
    guard let provider = CGDataProvider(url: URL(fileURLWithPath: fontPath) as CFURL),
          let cgFont = CGFont(provider)
    else { fatalError("couldn't read the pixel font at \(fontPath)") }
    return CTFontCreateWithGraphicsFont(cgFont, 128, nil, nil)
}()

// MARK: - The table

ctx.setFillColor(tableDeep.cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

/// One of the broad diagonal sweeps the app's background drifts through, frozen in place.
func band(angle: CGFloat, offset: CGFloat, thickness: CGFloat, strength: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: size / 2, y: size / 2)
    ctx.rotate(by: angle)
    ctx.clip(to: CGRect(x: -size, y: offset - thickness / 2, width: size * 2, height: thickness))
    let sweep = CGGradient(
        colorsSpace: space,
        colors: [tableLift.withAlphaComponent(0).cgColor,
                 tableLift.withAlphaComponent(strength).cgColor,
                 tableLift.withAlphaComponent(0).cgColor] as CFArray,
        locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(sweep,
                           start: CGPoint(x: 0, y: offset - thickness / 2),
                           end: CGPoint(x: 0, y: offset + thickness / 2),
                           options: [])
    ctx.restoreGState()
}

band(angle: -.pi / 6.4, offset: 170, thickness: 660, strength: 1.0)
band(angle: -.pi / 4.6, offset: -280, thickness: 460, strength: 0.7)

// Pulls the eye to the middle and keeps the corners from competing with the card.
let vignette = CGGradient(colorsSpace: space,
                          colors: [tableDeep.withAlphaComponent(0).cgColor,
                                   tableDeep.withAlphaComponent(0.74).cgColor] as CFArray,
                          locations: [0, 1])!
ctx.drawRadialGradient(vignette,
                       startCenter: CGPoint(x: size / 2, y: size / 2), startRadius: 190,
                       endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: 760,
                       options: .drawsAfterEndLocation)

// MARK: - Pieces

/// A padlock, centred on the origin of the current space. This is the suit.
func lock(scale: CGFloat) {
    ctx.saveGState()
    ctx.scaleBy(x: scale, y: scale)

    // Shackle: straight legs up to a half-circle, stroked twice — a heavy near-black pass
    // with a thinner gold one centred inside it. The legs run down past the body's top edge
    // so the body covers where the stroke ends, and the arc clears it far enough to leave a
    // real opening rather than a slot.
    let shackle = CGMutablePath()
    shackle.move(to: CGPoint(x: -64, y: 20))
    shackle.addLine(to: CGPoint(x: -64, y: 70))
    shackle.addArc(center: CGPoint(x: 0, y: 70), radius: 64,
                   startAngle: .pi, endAngle: 0, clockwise: true)
    shackle.addLine(to: CGPoint(x: 64, y: 20))

    for (width, colour) in [(64.0, outline), (32.0, gold)] {
        ctx.addPath(shackle)
        ctx.setStrokeColor(colour.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.butt)
        ctx.strokePath()
    }

    let bodyRect = CGRect(x: -100, y: -122, width: 200, height: 192)
    let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: 30, cornerHeight: 30, transform: nil)
    ctx.addPath(bodyPath)
    ctx.setFillColor(gold.cgColor)
    ctx.fillPath()
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(outline.cgColor)
    ctx.setLineWidth(18)
    ctx.strokePath()

    // Keyhole.
    ctx.setFillColor(outline.cgColor)
    ctx.fillEllipse(in: CGRect(x: -25, y: -35, width: 50, height: 50))
    let stem = CGMutablePath()
    stem.move(to: CGPoint(x: -17, y: -22))
    stem.addLine(to: CGPoint(x: 17, y: -22))
    stem.addLine(to: CGPoint(x: 10, y: -90))
    stem.addLine(to: CGPoint(x: -10, y: -90))
    stem.closeSubpath()
    ctx.addPath(stem)
    ctx.fillPath()

    ctx.restoreGState()
}

/// A corner index. Just the rank — a miniature suit beside it turns to grit by 60pt.
func index(at point: CGPoint, upsideDown: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: point.x, y: point.y)
    if upsideDown { ctx.rotate(by: .pi) }

    let attributed = NSAttributedString(string: "A", attributes: [
        .font: pixelFont, .foregroundColor: outline,
    ])
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(x: -bounds.width / 2, y: -bounds.height / 2)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// MARK: - The card

let cardWidth = 452.0, cardHeight = 610.0
let cardCentre = CGPoint(x: size / 2, y: size / 2 - 8)

ctx.saveGState()
ctx.translateBy(x: cardCentre.x, y: cardCentre.y)
ctx.rotate(by: -.pi / 46)

let rect = CGRect(x: -cardWidth / 2, y: -cardHeight / 2, width: cardWidth, height: cardHeight)
let radius = 54.0

// The ledge, showing only as a lip along the bottom edge.
ctx.addPath(CGPath(roundedRect: rect.offsetBy(dx: 0, dy: -22),
                   cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.setFillColor(outline.cgColor)
ctx.fillPath()

let cardPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(cardPath)
ctx.setFillColor(cardFace.cgColor)
ctx.fillPath()
ctx.addPath(cardPath)
ctx.setStrokeColor(outline.cgColor)
ctx.setLineWidth(18)
ctx.strokePath()

ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 30, dy: 30),
                   cornerWidth: radius - 18, cornerHeight: radius - 18, transform: nil))
ctx.setStrokeColor(gold.withAlphaComponent(0.55).cgColor)
ctx.setLineWidth(8)
ctx.strokePath()

// The pip. The lock's own middle sits above its origin, so this offset is what actually
// centres it on the card rather than leaving it riding high.
ctx.saveGState()
ctx.translateBy(x: 0, y: -6)
lock(scale: 1.22)
ctx.restoreGState()

index(at: CGPoint(x: -cardWidth / 2 + 80, y: cardHeight / 2 - 88), upsideDown: false)
index(at: CGPoint(x: cardWidth / 2 - 80, y: -cardHeight / 2 + 88), upsideDown: true)

ctx.restoreGState()

let url = URL(fileURLWithPath: outPath) as CFURL
let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
CGImageDestinationFinalize(destination)
print("wrote \(outPath)")
