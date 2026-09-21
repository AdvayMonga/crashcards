import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// SUPERSEDED. The shipped icon, card figures and shield art are hand-made pixel art now,
// dropped straight into the asset catalogs. Running this would overwrite all four with the
// generated versions below, which are not what the app ships. Kept only as a record of how
// the generated set was built.
//
// Crash Cards artwork: the joker, masked and unmasked.
//
// The app's whole idea in two faces of one card. Masked, the joker wears a tragedy mask —
// the fun is there but shut behind something. Unmasked, it grins: that's what you get back.
// The unlock gate turns the card from one to the other, and the masked face is the app icon,
// so the picture runs unbroken from the home screen to the block screen to the gate.
//
// It's pixel art in the literal sense: every figure is drawn as vectors into a small aliased
// bitmap and then blown up with no interpolation, so the stair-stepping is real rather than
// a filter laid over a smooth drawing. Everything is laid out in a 1024-unit design space.
//
//   swift Tools/make-icon.swift icon   <out.png>   1024 app icon, opaque, full bleed
//   swift Tools/make-icon.swift masked <out.png>   the masked joker alone, transparent
//   swift Tools/make-icon.swift joker  <out.png>   the grinning joker alone, transparent
//   swift Tools/make-icon.swift shield <out.png>   the masked joker, sized for the shield
//
// Run from the repo root.

let mode = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]

// MARK: - Palette
//
// Two tones per colour: pixel art needs a shadow to have any form at all, and a third tone
// would start to look like a gradient rather than a drawing.

let tableDeep = NSColor(srgbRed: 0x16 / 255, green: 0x22 / 255, blue: 0x2C / 255, alpha: 1)
let tableLift = NSColor(srgbRed: 0x24 / 255, green: 0x37 / 255, blue: 0x46 / 255, alpha: 1)
let outline = NSColor(srgbRed: 0x0E / 255, green: 0x15 / 255, blue: 0x19 / 255, alpha: 1)

let red = NSColor(srgbRed: 0xFE / 255, green: 0x5F / 255, blue: 0x55 / 255, alpha: 1)
let redDark = NSColor(srgbRed: 0xC4 / 255, green: 0x41 / 255, blue: 0x3A / 255, alpha: 1)
let gold = NSColor(srgbRed: 0xF0 / 255, green: 0xC0 / 255, blue: 0x40 / 255, alpha: 1)
let goldDark = NSColor(srgbRed: 0xBF / 255, green: 0x93 / 255, blue: 0x27 / 255, alpha: 1)

/// The joker's own face: warm, so the cool mask over it reads as a separate object.
let skin = NSColor(srgbRed: 0xF7 / 255, green: 0xE0 / 255, blue: 0xB8 / 255, alpha: 1)
let skinDark = NSColor(srgbRed: 0xD2 / 255, green: 0xB4 / 255, blue: 0x85 / 255, alpha: 1)
let bone = NSColor(srgbRed: 0xE9 / 255, green: 0xE8 / 255, blue: 0xE0 / 255, alpha: 1)
let boneDark = NSColor(srgbRed: 0xB3 / 255, green: 0xB2 / 255, blue: 0xA8 / 255, alpha: 1)

// MARK: - Output shapes

struct Output {
    /// The slice of design space this output frames.
    let design: CGRect
    /// The pixel grid the art is actually drawn on, before it is blown up.
    let cols: Int
    let rows: Int
    /// Final size. Always a whole multiple of the grid, so every art pixel stays square.
    let scale: Int
    let opaque: Bool
}

let outputs: [String: Output] = [
    // Full bleed: the face fills the rounded square the way a map does, and the cap and
    // ruff run off the edges rather than sitting politely inside them.
    "icon": Output(design: CGRect(x: -512, y: -512, width: 1024, height: 1024),
                   cols: 128, rows: 128, scale: 8, opaque: true),
    "masked": Output(design: CGRect(x: -480, y: -560, width: 960, height: 1160),
                     cols: 120, rows: 145, scale: 5, opaque: false),
    "joker": Output(design: CGRect(x: -480, y: -560, width: 960, height: 1160),
                    cols: 120, rows: 145, scale: 5, opaque: false),
    "shield": Output(design: CGRect(x: -480, y: -560, width: 960, height: 1160),
                     cols: 120, rows: 145, scale: 4, opaque: false),
]

guard let out = outputs[mode] else { fatalError("mode must be one of \(outputs.keys.sorted())") }

let space = CGColorSpaceCreateDeviceRGB()

// MARK: - Drawing helpers

func fill(_ c: CGContext, _ path: CGPath, _ colour: NSColor) {
    c.addPath(path)
    c.setFillColor(colour.cgColor)
    c.fillPath()
}

func stroke(_ c: CGContext, _ path: CGPath, _ colour: NSColor, width: CGFloat) {
    c.addPath(path)
    c.setStrokeColor(colour.cgColor)
    c.setLineWidth(width)
    c.setLineJoin(.round)
    c.setLineCap(.round)
    c.strokePath()
}

/// A solid shape with a shadow along its lower-right edge and a dark outline.
///
/// The shadow is the same shape laid down first and then covered by the base colour shifted
/// up and to the left — which is how you shade a form when you only have two tones.
func form(_ c: CGContext, _ path: CGPath, _ base: NSColor, _ shade: NSColor,
          depth: CGFloat = 26, edge: CGFloat = 22) {
    fill(c, path, shade)
    var lift = CGAffineTransform(translationX: -depth, y: depth)
    if let shifted = path.copy(using: &lift) { fill(c, shifted, base) }
    guard edge > 0 else { return }
    stroke(c, path, outline, width: edge)
}

func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: points[0].0, y: points[0].1))
    for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
    path.closeSubpath()
    return path
}

func ellipse(_ centre: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: centre.x - rx, y: centre.y - ry, width: rx * 2, height: ry * 2),
           transform: nil)
}

/// A lens between two quadratic arcs — every mouth in here is one of these.
func lens(left: CGPoint, right: CGPoint, top: CGPoint, bottom: CGPoint) -> CGPath {
    let path = CGMutablePath()
    path.move(to: left)
    path.addQuadCurve(to: right, control: top)
    path.addQuadCurve(to: left, control: bottom)
    path.closeSubpath()
    return path
}

// MARK: - The figure

/// A band split down the middle, which is what the harlequin's cap brim and collar both are.
func band(_ c: CGContext, _ rect: CGRect, shadeAtTop: Bool) {
    fill(c, CGPath(rect: CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2,
                                height: rect.height), transform: nil), gold)
    fill(c, CGPath(rect: CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2,
                                height: rect.height), transform: nil), red)
    fill(c, CGPath(rect: CGRect(x: rect.minX, y: shadeAtTop ? rect.maxY - 26 : rect.minY,
                                width: rect.width, height: 26), transform: nil), goldDark)
    stroke(c, CGPath(rect: rect, transform: nil), outline, width: 22)
}

/// The cap's points, which run off the top and the sides on purpose.
func capPoints(_ c: CGContext) {
    let points: [(path: CGPath, base: NSColor, shade: NSColor)] = [
        (polygon([(-380, 250), (-540, 500), (-190, 330)]), red, redDark),
        (polygon([(-172, 280), (0, 560), (172, 280)]), gold, goldDark),
        (polygon([(380, 250), (540, 500), (190, 330)]), red, redDark),
    ]
    for point in points { form(c, point.path, point.base, point.shade, depth: 20) }

    for bell in [CGPoint(x: -540, y: 500), CGPoint(x: 0, y: 560), CGPoint(x: 540, y: 500)] {
        form(c, ellipse(bell, 62, 62), gold, goldDark, depth: 18)
    }
}

/// The brim, worn across the forehead, so it goes over the head rather than behind it.
func capBrim(_ c: CGContext) {
    band(c, CGRect(x: -352, y: 196, width: 704, height: 92), shadeAtTop: false)
}

/// The ruff's points, hanging off the bottom edge.
func ruffPoints(_ c: CGContext) {
    let spans: [CGFloat] = [-390, -260, -130, 0, 130, 260, 390]
    for index in 0..<(spans.count - 1) {
        let warm = index.isMultiple(of: 2)
        form(c, polygon([(spans[index], -398), (spans[index + 1], -398),
                         ((spans[index] + spans[index + 1]) / 2, -640)]),
             warm ? red : gold, warm ? redDark : goldDark, depth: 18)
    }
}

/// The collar, which sits in front of the chin.
func ruffBand(_ c: CGContext) {
    band(c, CGRect(x: -406, y: -430, width: 812, height: 92), shadeAtTop: true)
}

/// The head under everything, which the mask sits on top of.
func head(_ c: CGContext, tone: NSColor, shade: NSColor) {
    form(c, ellipse(CGPoint(x: 0, y: -46), 352, 336), tone, shade, depth: 30)
}

/// Tragedy: hollow sockets, brows raised in the middle, mouth turned down at the corners.
func tragedyMask(_ c: CGContext) {
    form(c, ellipse(CGPoint(x: 0, y: -50), 302, 292), bone, boneDark, depth: 26)

    for side in [-1.0, 1.0] {
        fill(c, ellipse(CGPoint(x: side * 128, y: 10), 68, 82), outline)
    }

    // Brows lifted at the inner ends — the whole expression is in these two strokes.
    for side in [-1.0, 1.0] {
        let brow = CGMutablePath()
        brow.move(to: CGPoint(x: side * 176, y: 118))
        brow.addQuadCurve(to: CGPoint(x: side * 52, y: 168),
                          control: CGPoint(x: side * 116, y: 162))
        stroke(c, brow, outline, width: 40)
    }

    // A mouth whose corners hang below its middle. The reverse of this is the grin.
    fill(c, lens(left: CGPoint(x: -166, y: -250), right: CGPoint(x: 166, y: -250),
                 top: CGPoint(x: 0, y: -84), bottom: CGPoint(x: 0, y: -236)), outline)

    fill(c, polygon([(0, -26), (54, -142), (-54, -142)]), boneDark)

    // The rim, so it reads as something worn rather than as the face itself.
    stroke(c, ellipse(CGPoint(x: 0, y: -50), 302, 292), outline, width: 22)
}

/// The face under the mask: eyes up, mouth wide open, teeth showing.
func grin(_ c: CGContext) {
    for side in [-1.0, 1.0] {
        fill(c, ellipse(CGPoint(x: side * 134, y: 26), 60, 70), outline)
        // A highlight is the difference between an eye and a hole.
        fill(c, ellipse(CGPoint(x: side * 134 + 20, y: 50), 20, 22), bone)
    }

    // Brows raised at the outer ends, the mirror of the mask's.
    for side in [-1.0, 1.0] {
        let brow = CGMutablePath()
        brow.move(to: CGPoint(x: side * 226, y: 152))
        brow.addQuadCurve(to: CGPoint(x: side * 64, y: 118),
                          control: CGPoint(x: side * 146, y: 160))
        stroke(c, brow, outline, width: 32)
    }

    let mouth = lens(left: CGPoint(x: -212, y: -124), right: CGPoint(x: 212, y: -124),
                     top: CGPoint(x: 0, y: -188), bottom: CGPoint(x: 0, y: -376))
    fill(c, mouth, outline)

    // Teeth along the top lip, clipped to the mouth so they can't spill onto the cheeks.
    c.saveGState()
    c.addPath(mouth)
    c.clip()
    for x in stride(from: -180.0, through: 150.0, by: 66.0) {
        fill(c, CGPath(rect: CGRect(x: x, y: -232, width: 48, height: 80), transform: nil), bone)
    }
    c.restoreGState()

    for side in [-1.0, 1.0] {
        fill(c, ellipse(CGPoint(x: side * 246, y: -118), 54, 40), red)
    }
}

// MARK: - Compose

/// Draws the whole figure into a low-resolution aliased bitmap. Blowing that up with no
/// interpolation is what makes this pixel art rather than a vector drawing with a filter.
func figure(masked: Bool, background: Bool) -> CGImage {
    let c = CGContext(data: nil, width: out.cols, height: out.rows, bitsPerComponent: 8,
                      bytesPerRow: 0, space: space,
                      bitmapInfo: (out.opaque ? CGImageAlphaInfo.noneSkipLast
                                              : CGImageAlphaInfo.premultipliedLast).rawValue)!
    c.setShouldAntialias(false)
    c.setAllowsAntialiasing(false)
    c.interpolationQuality = .none
    c.scaleBy(x: CGFloat(out.cols) / out.design.width, y: CGFloat(out.rows) / out.design.height)
    c.translateBy(x: -out.design.minX, y: -out.design.minY)

    if background {
        fill(c, CGPath(rect: out.design, transform: nil), tableDeep)
        // One broad diagonal, the same sweep the app's table drifts through.
        c.saveGState()
        c.rotate(by: -.pi / 6)
        fill(c, CGPath(rect: CGRect(x: -1200, y: -120, width: 2400, height: 560),
                       transform: nil), tableLift)
        c.restoreGState()
    }

    capPoints(c)
    ruffPoints(c)
    head(c, tone: skin, shade: skinDark)
    if masked { tragedyMask(c) } else { grin(c) }
    capBrim(c)
    ruffBand(c)
    return c.makeImage()!
}

let art = figure(masked: mode != "joker", background: mode == "icon")

let width = out.cols * out.scale
let height = out.rows * out.scale
let final = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: 0, space: space,
                      bitmapInfo: (out.opaque ? CGImageAlphaInfo.noneSkipLast
                                              : CGImageAlphaInfo.premultipliedLast).rawValue)!
final.interpolationQuality = .none
final.setShouldAntialias(false)
final.draw(art, in: CGRect(x: 0, y: 0, width: width, height: height))

let url = URL(fileURLWithPath: outPath) as CFURL
let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, final.makeImage()!, nil)
CGImageDestinationFinalize(destination)
print("wrote \(outPath) — \(width)x\(height) from a \(out.cols)x\(out.rows) grid")
