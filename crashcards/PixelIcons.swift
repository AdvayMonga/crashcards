import SwiftUI

/// The app's icons, drawn as 9×9 pixel grids rather than taken from SF Symbols.
///
/// A system symbol set is the one part of a custom look that gives itself away instantly —
/// it carries Apple's stroke weights and optical sizing into a screen that has neither.
/// These are coarse on purpose: the grid is the point.
struct PixelGlyph {
    /// Nine rows of nine characters. `#` is on, anything else is off.
    let rows: [String]
    static let side = 9

    init(_ rows: String...) { self.rows = rows }
}

extension PixelGlyph {
    static let close = PixelGlyph(
        ".........",
        ".#.....#.",
        ".##...##.",
        "..##.##..",
        "...###...",
        "..##.##..",
        ".##...##.",
        ".#.....#.",
        ".........")

    static let plus = PixelGlyph(
        ".........",
        "...###...",
        "...###...",
        ".#######.",
        ".#######.",
        ".#######.",
        "...###...",
        "...###...",
        ".........")

    static let minus = PixelGlyph(
        ".........",
        ".........",
        ".........",
        ".#######.",
        ".#######.",
        ".#######.",
        ".........",
        ".........",
        ".........")

    /// A clock face with its hands at a quarter past — the sign for a scheduled window.
    static let clock = PixelGlyph(
        "..#####..",
        ".#.....#.",
        "#...#...#",
        "#...#...#",
        "#...####.",
        "#.......#",
        "#.......#",
        ".#.....#.",
        "..#####..")

    static let check = PixelGlyph(
        ".........",
        ".......##",
        "......##.",
        ".....##..",
        ".##..##..",
        ".####....",
        "..###....",
        "...##....",
        ".........")

    static let flag = PixelGlyph(
        "..#......",
        "..####...",
        "..#..##..",
        "..#....#.",
        "..#..##..",
        "..####...",
        "..#......",
        "..#......",
        "..#......")

    static let flagFilled = PixelGlyph(
        "..#......",
        "..####...",
        "..#####..",
        "..######.",
        "..#####..",
        "..####...",
        "..#......",
        "..#......",
        "..#......")

    static let lockClosed = PixelGlyph(
        ".........",
        "...###...",
        "..#...#..",
        "..#...#..",
        ".#######.",
        ".###.###.",
        ".###.###.",
        ".#######.",
        ".........")

    static let lockOpen = PixelGlyph(
        ".........",
        "....####.",
        "...#....#",
        "...#.....",
        ".#######.",
        ".###.###.",
        ".###.###.",
        ".#######.",
        ".........")

    static let mic = PixelGlyph(
        ".........",
        "...###...",
        "...###...",
        "...###...",
        ".#.###.#.",
        ".#.....#.",
        "..#####..",
        "....#....",
        "...###...")

    static let waveform = PixelGlyph(
        ".........",
        ".....#...",
        ".#...#...",
        ".#.#.#.#.",
        ".#.#.#.#.",
        ".#.#.#.#.",
        ".#.#.#.#.",
        "...#...#.",
        ".........")

    static let gear = PixelGlyph(
        "...###...",
        ".#######.",
        ".##...##.",
        "###...###",
        "##.....##",
        "###...###",
        ".##...##.",
        ".#######.",
        "...###...")

    static let cards = PixelGlyph(
        "#########",
        "#.......#",
        "#...#...#",
        "#..###..#",
        "#.#####.#",
        "#..###..#",
        "#...#...#",
        "#.......#",
        "#########")

    static let warning = PixelGlyph(
        "....#....",
        "....#....",
        "...###...",
        "...#.#...",
        "..##.##..",
        "..##.##..",
        ".###.###.",
        ".#######.",
        "#########")

    static let folder = PixelGlyph(
        ".........",
        ".####....",
        ".#######.",
        ".#######.",
        ".#######.",
        ".#######.",
        ".#######.",
        ".........",
        ".........")

    /// Lid, handle, and a body with two staves cut out of it.
    static let trash = PixelGlyph(
        "...###...",
        ".#######.",
        ".........",
        "#########",
        "#.#.#.#.#",
        "#.#.#.#.#",
        "#.#.#.#.#",
        "#.......#",
        ".#######.")

    static let copy = PixelGlyph(
        ".........",
        "...######",
        "...#....#",
        "######..#",
        "#....#..#",
        "#....#..#",
        "#....####",
        "#....#...",
        "######...")

    /// Reveal: show the answer you couldn't get to.
    static let eye = PixelGlyph(
        ".........",
        "..#####..",
        ".##...##.",
        "#..###..#",
        "#..###..#",
        "#..###..#",
        ".##...##.",
        "..#####..",
        ".........")

    static let question = PixelGlyph(
        ".........",
        "..#####..",
        ".##...##.",
        "......##.",
        "....###..",
        "...##....",
        "...##....",
        ".........",
        "...##....")

    static let play = PixelGlyph(
        ".........",
        "..#......",
        "..###....",
        "..#####..",
        "..#######",
        "..#####..",
        "..###....",
        "..#......",
        ".........")

    static let stop = PixelGlyph(
        ".........",
        ".#######.",
        ".#######.",
        ".#######.",
        ".#######.",
        ".#######.",
        ".#######.",
        ".#######.",
        ".........")

    static let chevron = PixelGlyph(
        ".........",
        "..##.....",
        "...##....",
        "....##...",
        ".....##..",
        "....##...",
        "...##....",
        "..##.....",
        ".........")

    /// The chevron mirrored. A drawn glyph rather than a rotated one: rotating the icon
    /// would take its chip's ledge with it and put the shadow on top.
    static let chevronLeft = PixelGlyph(
        ".........",
        ".....##..",
        "....##...",
        "...##....",
        "..##.....",
        "...##....",
        "....##...",
        ".....##..",
        ".........")

    /// The joker: the app's sign for something blocked. A grinning head under a cap,
    /// which at nine pixels square is as much face as there is room for.
    static let joker = PixelGlyph(
        "..#.#.#..",
        "..#####..",
        ".#######.",
        ".#######.",
        ".##.#.##.",
        ".#######.",
        ".#.....#.",
        ".##...##.",
        "..#####..")

    static let shuffle = PixelGlyph(
        ".........",
        ".##....##",
        "...#..#..",
        "....##...",
        "....##...",
        "...#..#..",
        ".##....##",
        ".........",
        ".........")
}

/// Draws a glyph at a whole number of points per pixel, so the grid never lands half on
/// a device pixel and turns soft.
struct PixelIcon: View {
    let glyph: PixelGlyph
    var size: CGFloat = 18
    var color: Color = Brand.ink

    private var cell: CGFloat { max(1, (size / CGFloat(PixelGlyph.side)).rounded(.down)) }
    private var drawn: CGFloat { cell * CGFloat(PixelGlyph.side) }

    var body: some View {
        Canvas { context, _ in
            for (y, row) in glyph.rows.enumerated() {
                for (x, mark) in row.enumerated() where mark == "#" {
                    context.fill(
                        Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell,
                                    width: cell, height: cell)),
                        with: .color(color))
                }
            }
        }
        .frame(width: drawn, height: drawn)
        .accessibilityHidden(true)
    }
}
