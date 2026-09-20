import SwiftUI

/// The felt the whole app sits on: a dark table with a few broad bands of lighter colour
/// drifting slowly across it, under a vignette.
///
/// The drift is built from soft gradients rather than blurred shapes — a blur would be
/// re-rasterised every frame, and this has to run behind everything, all the time. Reduce
/// Motion parks the bands where they are.
struct TableBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false

    /// Each band: how far along it starts, how wide, how steep, and how long a lap takes.
    private static let bands: [(offset: CGFloat, width: CGFloat, angle: Double, lap: Double)] = [
        (-0.35, 0.85, -28, 34),
        (0.15, 0.60, -34, 47),
        (0.55, 1.00, -22, 61),
    ]

    var body: some View {
        GeometryReader { geometry in
            let span = max(geometry.size.width, geometry.size.height) * 1.6

            ZStack {
                Brand.tableDeep

                ForEach(Array(Self.bands.enumerated()), id: \.offset) { index, band in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, Brand.tableLift.opacity(0.55), .clear],
                                startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: span * band.width, height: span)
                        .rotationEffect(.degrees(band.angle))
                        .offset(x: drifting ? span * 0.45 : -span * 0.45,
                                y: span * band.offset * 0.2)
                        .animation(
                            reduceMotion ? nil
                                : .easeInOut(duration: band.lap)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 2),
                            value: drifting)
                }

                // Pulls the eye to the middle of the table and hides the band edges.
                RadialGradient(
                    colors: [.clear, Brand.tableDeep.opacity(0.85)],
                    center: .center,
                    startRadius: geometry.size.height * 0.18,
                    endRadius: geometry.size.height * 0.78)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .onAppear { drifting = true }
    }
}

/// Everything in the app draws on the table. Screens use this rather than a plain colour so
/// the drift is continuous when you move between them.
extension View {
    func onTable() -> some View {
        background(TableBackground())
    }
}
