import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Crash Cards artwork. One drawing, four outputs.
//
// Two cards say what the app is. The joker is what you'd rather be doing; the lock is what
// stands in front of it. Fanned, with the lock card covering the joker, that reads as one
// sentence without a word of copy — and the two faces are also what the unlock gate flips
// between, so the picture on your home screen is the picture you meet when you're blocked.
//
// The joker is a harlequin: split red and gold down the middle, angular rather than round,
// drawn as linework on pale stock so it reads as a printed court card and not a sticker.
//
//   swift Tools/make-icon.swift icon   <out.png>   1024 app icon, opaque, on the felt table
//   swift Tools/make-icon.swift shield <out.png>   both cards, transparent, for the shield
//   swift Tools/make-icon.swift joker  <out.png>   the joker figure alone, transparent
//   swift Tools/make-icon.swift lock   <out.png>   the padlock alone, transparent
//
// The two figure-only outputs are what the app draws inside its own card stock, so a card in
// the gate and a card in a deck are the same object.
//
// Run from the repo root.

let mode = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]

// The app's palette, from Brand.
let tableDeep = NSColor(srgbRed: 0x16 / 255, green: 0x22 / 255, blue: 0x2C / 255, alpha: 1)
let tableLift = NSColor(srgbRed: 0x2B / 255, green: 0x42 / 255, blue: 0x54 / 255, alpha: 1)
let cardFace = NSColor(srgbRed: 0xF4 / 255, green: 0xEF / 255, blue: 0xE2 / 255, alpha: 1)
let cardBack = NSColor(srgbRed: 0xCA / 255, green: 0xC3 / 255, blue: 0xB1 / 255, alpha: 1)
let skin = NSColor(srgbRed: 0xFD / 255, green: 0xFA / 255, blue: 0xF1 / 255, alpha: 1)
let outline = NSColor(srgbRed: 0x0E / 255, green: 0x15 / 255, blue: 0x19 / 255, alpha: 1)
let gold = NSColor(srgbRed: 0xF0 / 255, green: 0xC0 / 255, blue: 0x40 / 255, alpha: 1)
let mult = NSColor(srgbRed: 0xFE / 255, green: 0x5F / 255, blue: 0x55 / 255, alpha: 1)

/// Everything is laid out in a design space centred on the origin. Each mode frames a
/// different rectangle of it, at a different pixel size.
struct Output {
    let frame: CGRect
    let pixels: CGSize
    let opaque: Bool
}

let outputs: [String: Output] = [
    "icon": Output(frame: CGRect(x: -512, y: -512, width: 1024, height: 1024),
                   pixels: CGSize(width: 1024, height: 1024), opaque: true),
    "shield": Output(frame: CGRect(x: -400, y: -400, width: 800, height: 800),
                     pixels: CGSize(width: 480, height: 480), opaque: false),
    "joker": Output(frame: CGRect(x: -186, y: -226, width: 372, height: 452),
                    pixels: CGSize(width: 558, height: 678), opaque: false),
    "lock": Output(frame: CGRect(x: -150, y: -186, width: 300, height: 372),
                   pixels: CGSize(width: 450, height: 558), opaque: false),
]

guard let out = outputs[mode] else { fatalError("mode must be one of \(outputs.keys.sorted())") }

let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(
    data: nil, width: Int(out.pixels.width), height: Int(out.pixels.height),
    bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: (out.opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue
)!

ctx.scaleBy(x: out.pixels.width / out.frame.width, y: out.pixels.height / out.frame.height)
ctx.translateBy(x: -out.frame.minX, y: -out.frame.minY)

// MARK: - Drawing helpers

func fill(_ path: CGPath, _ colour: NSColor, edge: CGFloat = 16) {
    ctx.addPath(path)
    ctx.setFillColor(colour.cgColor)
    ctx.fillPath()
    guard edge > 0 else { return }
    ctx.addPath(path)
    ctx.setStrokeColor(outline.cgColor)
    ctx.setLineWidth(edge)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}

func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: points[0].0, y: points[0].1))
    for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
    path.closeSubpath()
    return path
}

func diamond(at centre: CGPoint, width: CGFloat, height: CGFloat) -> CGPath {
    polygon([(centre.x, centre.y + height), (centre.x + width, centre.y),
             (centre.x, centre.y - height), (centre.x - width, centre.y)])
}

/// Fills a shape in two colours split down the middle — the harlequin's whole idea.
func fillHarlequin(_ path: CGPath, left: NSColor, right: NSColor, edge: CGFloat = 16) {
    for (half, colour) in [(CGRect(x: -800, y: -800, width: 800, height: 1600), left),
                           (CGRect(x: 0, y: -800, width: 800, height: 1600), right)] {
        ctx.saveGState()
        ctx.clip(to: half)
        ctx.addPath(path)
        ctx.setFillColor(colour.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.addPath(path)
    ctx.setStrokeColor(outline.cgColor)
    ctx.setLineWidth(edge)
    ctx.setLineJoin(.round)
    ctx.strokePath()
}

// MARK: - The suit

/// A padlock, centred on the origin of the current space.
func lock(keyhole: Bool) {
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
                cornerWidth: 30, cornerHeight: 30, transform: nil), gold, edge: 18)

    guard keyhole else { return }
    ctx.setFillColor(outline.cgColor)
    ctx.fillEllipse(in: CGRect(x: -25, y: -35, width: 50, height: 50))
    ctx.addPath(polygon([(-17, -22), (17, -22), (10, -90), (-10, -90)]))
    ctx.fillPath()
}

// MARK: - The joker

/// A harlequin bust: ruff, head, face, cap. Split red and gold down the centre line.
func joker() {
    // Ruff — four points hanging off a band, alternating colour across the split.
    let spans: [(CGFloat, CGFloat)] = [(-112, -56), (-56, 0), (0, 56), (56, 112)]
    for (index, span) in spans.enumerated() {
        fill(polygon([(span.0, -116), (span.1, -116), ((span.0 + span.1) / 2, -206)]),
             index.isMultiple(of: 2) ? mult : gold, edge: 14)
    }
    fillHarlequin(CGPath(roundedRect: CGRect(x: -118, y: -136, width: 236, height: 36),
                         cornerWidth: 12, cornerHeight: 12, transform: nil),
                  left: gold, right: mult, edge: 16)

    // Head — faceted rather than round, so it reads as drawn instead of stamped.
    fill(polygon([(0, 62), (-54, 48), (-78, 4), (-70, -46), (-36, -98), (0, -114),
                  (36, -98), (70, -46), (78, 4), (54, 48)]), skin, edge: 16)

    // Brows: angled outward and down, which is most of the expression.
    ctx.setStrokeColor(outline.cgColor)
    ctx.setLineCap(.round)
    ctx.setLineWidth(13)
    for side in [-1.0, 1.0] {
        ctx.move(to: CGPoint(x: side * 56, y: 4))
        ctx.addLine(to: CGPoint(x: side * 16, y: 16))
        ctx.strokePath()
    }

    // Eyes as small diamonds — the harlequin motif, not a pair of dots.
    ctx.setFillColor(outline.cgColor)
    for side in [-1.0, 1.0] {
        ctx.addPath(diamond(at: CGPoint(x: side * 34, y: -14), width: 17, height: 13))
        ctx.fillPath()
    }

    // A harlequin tear under one eye.
    fill(diamond(at: CGPoint(x: -56, y: -46), width: 12, height: 17), mult, edge: 9)

    // Nose.
    ctx.setStrokeColor(outline.cgColor)
    ctx.setLineWidth(11)
    ctx.move(to: CGPoint(x: 0, y: -22))
    ctx.addLine(to: CGPoint(x: 0, y: -54))
    ctx.addLine(to: CGPoint(x: 15, y: -60))
    ctx.strokePath()

    // Smirk, lifted on one side. A symmetric grin is what made the last one a smiley.
    let smirk = CGMutablePath()
    smirk.move(to: CGPoint(x: -34, y: -74))
    smirk.addCurve(to: CGPoint(x: 38, y: -50),
                   control1: CGPoint(x: -4, y: -98), control2: CGPoint(x: 26, y: -86))
    ctx.addPath(smirk)
    ctx.setLineWidth(13)
    ctx.strokePath()

    // Cap: three drooping points over a brim, split down the middle.
    fillHarlequin(polygon([(-92, 40), (-150, 104), (-48, 90), (0, 168),
                           (48, 90), (150, 104), (92, 40)]),
                  left: mult, right: gold, edge: 17)
    ctx.setStrokeColor(outline.cgColor)
    ctx.setLineWidth(11)
    ctx.move(to: CGPoint(x: 0, y: 44))
    ctx.addLine(to: CGPoint(x: 0, y: 166))
    ctx.strokePath()

    fillHarlequin(CGPath(roundedRect: CGRect(x: -98, y: 24, width: 196, height: 38),
                         cornerWidth: 14, cornerHeight: 14, transform: nil),
                  left: gold, right: mult, edge: 16)

    for bell in [CGPoint(x: -150, y: 104), CGPoint(x: 0, y: 170), CGPoint(x: 150, y: 104)] {
        fill(CGPath(ellipseIn: CGRect(x: bell.x - 24, y: bell.y - 24, width: 48, height: 48),
                    transform: nil), gold, edge: 15)
    }
}

// MARK: - Cards

let cardWidth = 452.0, cardHeight = 610.0
let cardRadius = 54.0

/// One card: ledge, stock, near-black edge, gold inner frame, then whatever it carries.
func card(at centre: CGPoint, rotation: CGFloat, stock: NSColor, contents: () -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: centre.x, y: centre.y)
    ctx.rotate(by: rotation)

    let rect = CGRect(x: -cardWidth / 2, y: -cardHeight / 2, width: cardWidth, height: cardHeight)

    ctx.addPath(CGPath(roundedRect: rect.offsetBy(dx: 0, dy: -22),
                       cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil))
    ctx.setFillColor(outline.cgColor)
    ctx.fillPath()

    fill(CGPath(roundedRect: rect, cornerWidth: cardRadius, cornerHeight: cardRadius,
                transform: nil), stock, edge: 18)

    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 30, dy: 30),
                       cornerWidth: cardRadius - 18, cornerHeight: cardRadius - 18,
                       transform: nil))
    ctx.setStrokeColor(gold.withAlphaComponent(0.55).cgColor)
    ctx.setLineWidth(8)
    ctx.strokePath()

    contents()
    ctx.restoreGState()
}

/// The suit, in the two corners a rank and pip would occupy. Both upright: a card rotates
/// its indices, but a padlock turned upside down reads as a broken padlock.
func cornerSuit() {
    for corner in [CGPoint(x: -cardWidth / 2 + 74, y: cardHeight / 2 - 86),
                   CGPoint(x: cardWidth / 2 - 74, y: -cardHeight / 2 + 86)] {
        ctx.saveGState()
        ctx.translateBy(x: corner.x, y: corner.y)
        ctx.scaleBy(x: 0.28, y: 0.28)
        lock(keyhole: false)
        ctx.restoreGState()
    }
}

// MARK: - Compose

switch mode {
case "joker":
    ctx.translateBy(x: 0, y: -10)
    joker()

case "lock":
    ctx.scaleBy(x: 1.18, y: 1.18)
    ctx.translateBy(x: 0, y: -6)
    lock(keyhole: true)

default:
    if mode == "icon" {
        ctx.setFillColor(tableDeep.cgColor)
        ctx.fill(CGRect(x: -512, y: -512, width: 1024, height: 1024))

        /// One of the broad sweeps the app's background drifts through, frozen in place.
        func band(angle: CGFloat, offset: CGFloat, thickness: CGFloat, strength: CGFloat) {
            ctx.saveGState()
            ctx.rotate(by: angle)
            ctx.clip(to: CGRect(x: -1024, y: offset - thickness / 2,
                                width: 2048, height: thickness))
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

        let vignette = CGGradient(colorsSpace: space,
                                  colors: [tableDeep.withAlphaComponent(0).cgColor,
                                           tableDeep.withAlphaComponent(0.74).cgColor] as CFArray,
                                  locations: [0, 1])!
        ctx.drawRadialGradient(vignette, startCenter: .zero, startRadius: 190,
                               endCenter: .zero, endRadius: 760, options: .drawsAfterEndLocation)
    }

    // The joker behind, showing enough of itself to be read; the lock card over it.
    ctx.scaleBy(x: 0.86, y: 0.86)

    card(at: CGPoint(x: 190, y: 74), rotation: .pi / 9, stock: cardBack) {
        ctx.translateBy(x: 0, y: -10)
        ctx.scaleBy(x: 0.84, y: 0.84)
        joker()
    }

    card(at: CGPoint(x: -126, y: -52), rotation: -.pi / 40, stock: cardFace) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: -4)
        lock(keyhole: true)
        ctx.restoreGState()
        cornerSuit()
    }
}

let url = URL(fileURLWithPath: outPath) as CFURL
let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
CGImageDestinationFinalize(destination)
print("wrote \(outPath)")
