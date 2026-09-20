import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Crash Cards icon: two cards on the felt table, the front one carrying a gold bolt.
//
// Drawn in the same language as the app — dark table with a band of lighter colour across
// it, cream card stock, everything outlined in near-black and standing on its own ledge.
// Kept to three shapes so it still reads at 40pt on a home screen.

let size = 1024.0

// The app's palette, from Brand.
let tableDeep = NSColor(srgbRed: 0x16 / 255, green: 0x22 / 255, blue: 0x2C / 255, alpha: 1)
let tableLift = NSColor(srgbRed: 0x2B / 255, green: 0x42 / 255, blue: 0x54 / 255, alpha: 1)
let cardFace = NSColor(srgbRed: 0xF4 / 255, green: 0xEF / 255, blue: 0xE2 / 255, alpha: 1)
let cardBack = NSColor(srgbRed: 0xCF / 255, green: 0xC8 / 255, blue: 0xB6 / 255, alpha: 1)
let outline = NSColor(srgbRed: 0x0E / 255, green: 0x15 / 255, blue: 0x19 / 255, alpha: 1)
let gold = NSColor(srgbRed: 0xF0 / 255, green: 0xC0 / 255, blue: 0x40 / 255, alpha: 1)

// An opaque context: App Store icons must carry no alpha channel at all.
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

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

// Pulls the eye to the middle and keeps the corners from competing with the cards.
let vignette = CGGradient(colorsSpace: space,
                          colors: [tableDeep.withAlphaComponent(0).cgColor,
                                   tableDeep.withAlphaComponent(0.74).cgColor] as CFArray,
                          locations: [0, 1])!
ctx.drawRadialGradient(vignette,
                       startCenter: CGPoint(x: size / 2, y: size / 2), startRadius: 190,
                       endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: 760,
                       options: .drawsAfterEndLocation)

// MARK: - The cards

/// A card: a ledge, the stock on top of it, a near-black edge, and an optional inner frame.
func card(center: CGPoint, width: CGFloat, height: CGFloat,
          rotation: CGFloat, fill: NSColor, frame: NSColor? = nil) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: rotation)

    let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    let radius = 52.0

    // The ledge, showing only as a lip along the bottom edge.
    ctx.addPath(CGPath(roundedRect: rect.offsetBy(dx: 0, dy: -22),
                       cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(outline.cgColor)
    ctx.fillPath()

    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                      transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(fill.cgColor)
    ctx.fillPath()
    ctx.addPath(path)
    ctx.setStrokeColor(outline.cgColor)
    ctx.setLineWidth(18)
    ctx.strokePath()

    if let frame {
        ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 30, dy: 30),
                           cornerWidth: radius - 18, cornerHeight: radius - 18, transform: nil))
        ctx.setStrokeColor(frame.cgColor)
        ctx.setLineWidth(8)
        ctx.strokePath()
    }
    ctx.restoreGState()
}

let cardWidth = 414.0, cardHeight = 558.0

// Back card: further up the table, leaning the other way, and in shadow.
card(center: CGPoint(x: size / 2 + 80, y: size / 2 + 34),
     width: cardWidth, height: cardHeight, rotation: .pi / 13, fill: cardBack)

// Front card, nearly upright.
let frontCentre = CGPoint(x: size / 2 - 67, y: size / 2 - 26)
let frontRotation = -CGFloat.pi / 44
card(center: frontCentre, width: cardWidth, height: cardHeight,
     rotation: frontRotation, fill: cardFace, frame: gold.withAlphaComponent(0.5))

// MARK: - The bolt

// Filled and outlined rather than knocked out: an app icon must be fully opaque, so a
// transparent hole isn't available to draw with.
ctx.saveGState()
ctx.translateBy(x: frontCentre.x, y: frontCentre.y)
ctx.rotate(by: frontRotation)

let bolt = CGMutablePath()
let points: [(CGFloat, CGFloat)] = [
    (53, 200), (-94, 27), (-18, 27), (-53, -200), (94, -27), (18, -27),
]
bolt.move(to: CGPoint(x: points[0].0, y: points[0].1))
for point in points.dropFirst() { bolt.addLine(to: CGPoint(x: point.0, y: point.1)) }
bolt.closeSubpath()

ctx.addPath(bolt)
ctx.setFillColor(gold.cgColor)
ctx.fillPath()
ctx.addPath(bolt)
ctx.setStrokeColor(outline.cgColor)
ctx.setLineWidth(17)
ctx.setLineJoin(.round)
ctx.strokePath()
ctx.restoreGState()

let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
CGImageDestinationFinalize(destination)
print("wrote \(CommandLine.arguments[1])")
