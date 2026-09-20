import SwiftUI

/// Hands-free voice study: the app speaks prompts and listens for spoken answers.
struct VoiceStudyView: View {
    @State private var controller: VoiceStudyController
    @Environment(\.scenePhase) private var scenePhase
    let onClose: () -> Void

    init(session: StudySession, onClose: @escaping () -> Void) {
        _controller = State(initialValue: VoiceStudyController(session: session))
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            TableBackground()

            VStack(spacing: 20) {
                Spacer()

                PixelIcon(glyph: controller.isRunning ? .waveform : .mic, size: 63,
                          color: controller.isRunning ? Brand.green : Brand.inkDim)
                    .padding(26)
                    .slab(Brand.surfaceHigh, radius: Brand.cardRadius)
                    .breathing(controller.isRunning ? 2.0 : 0.8,
                               period: controller.isRunning ? 1.1 : 3.2)

                Text(controller.status)
                    .font(.brandLabel)
                    .foregroundStyle(Brand.ink)
                    .multilineTextAlignment(.center)

                if controller.permissionDenied {
                    permissionHelp
                } else if let error = controller.errorText {
                    Text(error)
                        .font(.reading(14))
                        .foregroundStyle(Brand.mult)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let card = controller.session.current {
                    Text(card.prompt)
                        .font(.brandCard)
                        .foregroundStyle(Brand.cardInk)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 26)
                        .background {
                            RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                                .fill(Brand.cardFace)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Brand.cardRadius,
                                                     style: .continuous)
                                        .strokeBorder(Brand.outline, lineWidth: 3))
                                .shadow(color: .black.opacity(0.45), radius: 14, y: 10)
                        }
                        .breathing(0.7, period: 3.3)
                }

                if !controller.heard.isEmpty {
                    Text("Heard: \(controller.heard)")
                        .font(.reading(14))
                        .foregroundStyle(Brand.inkFaint)
                }

                Spacer()

                Button(controller.isRunning ? "Stop" : "Start") {
                    Haptics.thud()
                    controller.isRunning ? controller.stop() : controller.start()
                }
                .buttonStyle(.solid(controller.isRunning ? Brand.mult : Brand.green))
                .disabled(controller.session.isEmpty || controller.permissionDenied)
                .opacity(controller.session.isEmpty || controller.permissionDenied ? 0.45 : 1)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 26)
        }
        .safeAreaInset(edge: .top) { header }
        .animation(Motion.pop, value: controller.isRunning)
        .onDisappear { controller.stop() }
        .onChange(of: scenePhase) { _, phase in
            // Backgrounding tears down the audio route; stop rather than hang mid-card.
            if phase != .active, controller.isRunning { controller.stop() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HeaderChip(glyph: .close, name: "Close") {
                controller.stop()
                onClose()
            }
            Spacer(minLength: 0)
            Text("Voice")
                .font(.brandTitle)
                .foregroundStyle(Brand.ink)
                .shadow(color: Brand.outline, radius: 0, x: 2, y: 2)
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 1)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    /// Permission can only be re-granted in Settings, so link straight there.
    private var permissionHelp: some View {
        VStack(spacing: 12) {
            Text("Voice study needs microphone and speech recognition access.")
                .font(.reading(14))
                .foregroundStyle(Brand.inkDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(url) }
                    .buttonStyle(CrashButton(kind: .soft, fullWidth: false))
            }
        }
    }
}
