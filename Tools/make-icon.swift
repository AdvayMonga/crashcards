import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Crash Cards icon: two cards, the top one struck through by a bolt-shaped gap.
// Minimal — two shapes, one accent, no gradients beyond a single soft wash.
let size = 1024.0
let accent = NSColor(srgbRed: 0.369, green: 0.361, blue: 0.902, alpha: 1)
let deep = NSColor(srgbRed: 0.24, green: 0.23, blue: 0.68, alpha: 1)

// An opaque context: App Store icons must carry no alpha channel at all.
let space0 = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: space0, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

// Ground: a vertical wash from the accent into a deeper indigo.
let space = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(colorsSpace: space,
                          colors: [deep.cgColor, accent.cgColor] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0),
                       end: CGPoint(x: size, y: size), options: [])

// Back card: offset, translucent, rotated a touch.
func card(rect: CGRect, radius: CGFloat, rotation: CGFloat, fill: NSColor) {
    ctx.saveGState()
    ctx.translateBy(x: rect.midX, y: rect.midY)
    ctx.rotate(by: rotation)
    ctx.translateBy(x: -rect.width / 2, y: -rect.height / 2)
    let path = CGPath(roundedRect: CGRect(origin: .zero, size: rect.size),
                      cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(fill.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
}

let w = 430.0, h = 560.0
card(rect: CGRect(x: size / 2 - w / 2 + 52, y: size / 2 - h / 2 + 8, width: w, height: h),
     radius: 64, rotation: .pi / 22, fill: NSColor(white: 1, alpha: 0.28))

// Front card, upright and solid.
let front = CGRect(x: size / 2 - w / 2 - 26, y: size / 2 - h / 2 - 12, width: w, height: h)
card(rect: front, radius: 64, rotation: -.pi / 40, fill: .white)

// The bolt, drawn in the accent. Filled rather than knocked out: an app icon must be
// fully opaque, and destinationOut would leave a transparent hole.
ctx.saveGState()
ctx.translateBy(x: front.midX, y: front.midY)
ctx.rotate(by: -.pi / 40)
let bolt = CGMutablePath()
let points: [(CGFloat, CGFloat)] = [
    (42, 186), (-78, 22), (-14, 22), (-42, -186), (78, -22), (14, -22),
]
bolt.move(to: CGPoint(x: points[0].0, y: points[0].1))
for p in points.dropFirst() { bolt.addLine(to: CGPoint(x: p.0, y: p.1)) }
bolt.closeSubpath()
ctx.addPath(bolt)
ctx.setFillColor(accent.cgColor)
ctx.fillPath()
ctx.restoreGState()

let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
CGImageDestinationFinalize(destination)
print("wrote \(CommandLine.arguments[1])")
