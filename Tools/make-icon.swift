import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Crash Cards artwork: the joker, locked.
//
// The joker is everything you'd rather be doing — the wild card, the distraction. The suit
// is a padlock, sitting in the corners where a rank and pip belong. Put together: the fun
// is behind a lock, and the cards are the way through.
//
// Drawn in the app's own language — cream stock, near-black edge, gold inner frame, standing
// on its own ledge. Two outputs from one drawing:
//
//   swift Tools/make-icon.swift icon   <out.png>   1024 app icon, opaque, on the felt table
//   swift Tools/make-icon.swift shield <out.png>   the card alone, transparent, for the
//                                                  Screen Time block screen
//
// Run from the repo root.

let mode = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]
precondition(mode == "icon" || mode == "shield", "mode must be icon or shield")

/// Everything below is laid out in a 1024-wide space; the context scales it to fit.
let space1024 = 1024.0
let onTable = mode == "icon"
/// How much of that space each output frames, and how many pixels it gets. The app icon is
/// square by rule; the block screen crops to the card, so it gets a card-shaped frame.
let framedWidth = onTable ? space1024 : 566.0
let framedHeight = onTable ? space1024 : 724.0
// The shield art ships as a @3x asset, so these pixels are three per point.
let pixelWidth = onTable ? 1024.0 : 480.0
let pixelHeight = onTable ? 1024.0 : 614.0

// The app's palette, from Brand.
let tableDeep = NSColor(srgbRed: 0x16 / 255, green: 0x22 / 255, blue: 0x2C / 255, alpha: 1)
let tableLift = NSColor(srgbRed: 0x2B / 255, green: 0x42 / 255, blue: 0x54 / 255, alpha: 1)
let cardFace = NSColor(srgbRed: 0xF4 / 255, green: 0xEF / 255, blue: 0xE2 / 255, alpha: 1)
let outline = NSColor(srgbRed: 0x0E / 255, green: 0x15 / 255, blue: 0x19 / 255, alpha: 1)
let gold = NSColor(srgbRed: 0xF0 / 255, green: 0xC0 / 255, blue: 0x40 / 255, alpha: 1)
let mult = NSColor(srgbRed: 0xFE / 255, green: 0x5F / 255, blue: 0x55 / 255, alpha: 1)

// The app icon must be fully opaque; the shield draws over the system's own background,
// so that one keeps its alpha.
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(
    data: nil, width: Int(pixelWidth), height: Int(pixelHeight), bitsPerComponent: 8,
    bytesPerRow: 0, space: space,
    bitmapInfo: (onTable ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue
)!

ctx.scaleBy(x: pixelWidth / framedWidth, y: pixelHeight / framedHeight)
ctx.translateBy(x: (framedWidth - space1024) / 2, y: (framedHeight - space1024) / 2)

// MARK: - The table

if onTable {
    ctx.setFillColor(tableDeep.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: space1024, height: space1024))

    /// One of the broad diagonal sweeps the app's background drifts through, frozen in place.
    func band(angle: CGFloat, offset: CGFloat, thickness: CGFloat, strength: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: space1024 / 2, y: space1024 / 2)
        ctx.rotate(by: angle)
        ctx.clip(to: CGRect(x: -space1024, y: offset - thickness / 2,
                            width: space1024 * 2, height: thickness))
        let sweep = CGGradient(
            colorsSpace: space,
            colors: [tableLift.withAlphaComponent(0).cgColor,
                     tableLift.withAlphaComponent(strength).cgColor,
                     tableLift.withAlphaComponent(0).cgColor] as CFArray,
            locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(sweep, start: CGPoint(x: 0, y: offset - thickness / 2),
                               end: CGPoint(x: 0, y: offset + thickness / 2), options: [])
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
                           startCenter: CGPoint(x: space1024 / 2, y: space1024 / 2),
                           startRadius: 190,
                           endCenter: CGPoint(x: space1024 / 2, y: space1024 / 2),
                           endRadius: 760, options: .drawsAfterEndLocation)
}

// MARK: - Pieces

func fill(_ path: CGPath, _ colour: NSColor, edge: CGFloat = 18) {
    ctx.addPath(path)
    ctx.setFillColor(colour.cgColor)
    ctx.fillPath()
    if edge > 0 {
        ctx.addPath(path)
        ctx.setStrokeColor(outline.cgColor)
        ctx.setLineWidth(edge)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }
}

/// A padlock, centred on the origin of the current space. This is the suit.
/// At corner size the keyhole is left off — it only ever resolves as a smudge.
func lock(scale: CGFloat, keyhole: Bool) {
    ctx.saveGState()
    ctx.scaleBy(x: scale, y: scale)

    // Straight legs up to a half-circle. The legs run down behind the body, so the body
    // covers the stroke ends and the arc still clears it with a real opening.
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

    fill(CGPath(roundedRect: CGRect(x: -100, y: -122, width: 200, height: 192),
                cornerWidth: 30, cornerHeight: 30, transform: nil), gold)

    if keyhole {
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
    }
    ctx.restoreGState()
}

/// The joker: a grinning head under a three-point cap. Drawn face first so the cap's brim
/// sits over the top of the head.
func joker(scale: CGFloat) {
    ctx.saveGState()
    ctx.scaleBy(x: scale, y: scale)

    // Ruff: a band under the chin with three points hanging off it. Drawn before the head
    // so the chin overlaps its top edge and the two read as one figure.
    let ruff = CGMutablePath()
    ruff.move(to: CGPoint(x: -104, y: -120))
    ruff.addLine(to: CGPoint(x: -104, y: -156))
    ruff.addLine(to: CGPoint(x: -69, y: -200))
    ruff.addLine(to: CGPoint(x: -35, y: -156))
    ruff.addLine(to: CGPoint(x: 0, y: -200))
    ruff.addLine(to: CGPoint(x: 35, y: -156))
    ruff.addLine(to: CGPoint(x: 69, y: -200))
    ruff.addLine(to: CGPoint(x: 104, y: -156))
    ruff.addLine(to: CGPoint(x: 104, y: -120))
    ruff.closeSubpath()
    fill(ruff, mult, edge: 17)

    // Head.
    fill(CGPath(ellipseIn: CGRect(x: -86, y: -136, width: 172, height: 172), transform: nil),
         gold)

    // Eyes.
    ctx.setFillColor(outline.cgColor)
    for x in [-36.0, 36.0] {
        ctx.fillEllipse(in: CGRect(x: x - 15, y: -32, width: 30, height: 34))
    }

    // Grin: the bottom of a circle, stroked.
    let grin = CGMutablePath()
    grin.addArc(center: CGPoint(x: 0, y: -34), radius: 48,
                startAngle: 200 * .pi / 180, endAngle: 340 * .pi / 180,
                clockwise: false, transform: .identity)
    ctx.addPath(grin)
    ctx.setStrokeColor(outline.cgColor)
    ctx.setLineWidth(17)
    ctx.setLineCap(.round)
    ctx.strokePath()

    // Cap: three drooping points, each with a bell.
    let cap = CGMutablePath()
    cap.move(to: CGPoint(x: -92, y: 22))
    cap.addLine(to: CGPoint(x: -150, y: 84))
    cap.addLine(to: CGPoint(x: -48, y: 76))
    cap.addLine(to: CGPoint(x: 0, y: 150))
    cap.addLine(to: CGPoint(x: 48, y: 76))
    cap.addLine(to: CGPoint(x: 150, y: 84))
    cap.addLine(to: CGPoint(x: 92, y: 22))
    cap.closeSubpath()
    fill(cap, mult, edge: 17)

    for bell in [CGPoint(x: -150, y: 84), CGPoint(x: 0, y: 152), CGPoint(x: 150, y: 84)] {
        fill(CGPath(ellipseIn: CGRect(x: bell.x - 24, y: bell.y - 24, width: 48, height: 48),
                    transform: nil), gold, edge: 15)
    }

    ctx.restoreGState()
}

// MARK: - The card

let cardWidth = 452.0, cardHeight = 610.0

ctx.saveGState()
ctx.translateBy(x: space1024 / 2, y: space1024 / 2 - 8)
ctx.rotate(by: -.pi / 46)

let rect = CGRect(x: -cardWidth / 2, y: -cardHeight / 2, width: cardWidth, height: cardHeight)
let radius = 54.0

// The ledge, showing only as a lip along the bottom edge.
ctx.addPath(CGPath(roundedRect: rect.offsetBy(dx: 0, dy: -22),
                   cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.setFillColor(outline.cgColor)
ctx.fillPath()

fill(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil),
     cardFace)

ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 30, dy: 30),
                   cornerWidth: radius - 18, cornerHeight: radius - 18, transform: nil))
ctx.setStrokeColor(gold.withAlphaComponent(0.55).cgColor)
ctx.setLineWidth(8)
ctx.strokePath()

// The joker's own middle sits above its origin, so this offset is what centres it.
ctx.saveGState()
ctx.translateBy(x: 0, y: 14)
joker(scale: 0.95)
ctx.restoreGState()

// The suit, in the two corners a rank and pip would occupy. Both upright: a card rotates
// its indices, but a padlock turned upside down just reads as a broken padlock.
for corner in [CGPoint(x: -cardWidth / 2 + 74, y: cardHeight / 2 - 86),
               CGPoint(x: cardWidth / 2 - 74, y: -cardHeight / 2 + 86)] {
    ctx.saveGState()
    ctx.translateBy(x: corner.x, y: corner.y)
    lock(scale: 0.30, keyhole: false)
    ctx.restoreGState()
}

ctx.restoreGState()

let url = URL(fileURLWithPath: outPath) as CFURL
let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
CGImageDestinationFinalize(destination)
print("wrote \(outPath)")
