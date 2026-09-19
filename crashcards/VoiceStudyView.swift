import SwiftUI

/// Hands-free voice study: the app speaks prompts and listens for spoken answers.
struct VoiceStudyView: View {
    @State private var controller: VoiceStudyController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(session: StudySession) {
        _controller = State(initialValue: VoiceStudyController(session: session))
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: controller.isRunning ? "waveform" : "mic.circle")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, isActive: controller.isRunning)

            Text(controller.status)
                .font(.headline)
                .multilineTextAlignment(.center)

            if controller.permissionDenied {
                permissionHelp
            } else if let error = controller.errorText {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if let card = controller.session.current {
                Text(card.prompt)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            if !controller.heard.isEmpty {
                Text("Heard: \(controller.heard)")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                controller.isRunning ? controller.stop() : controller.start()
            } label: {
                Label(controller.isRunning ? "Stop" : "Start",
                      systemImage: controller.isRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(controller.isRunning ? .red : .accentColor)
            .disabled(controller.session.isEmpty || controller.permissionDenied)
        }
        .padding()
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { controller.stop() }
        .onChange(of: scenePhase) { _, phase in
            // Backgrounding tears down the audio route; stop rather than hang mid-card.
            if phase != .active, controller.isRunning { controller.stop() }
        }
    }

    /// Permission can only be re-granted in Settings, so link straight there.
    private var permissionHelp: some View {
        VStack(spacing: 12) {
            Text("Voice study needs microphone and speech recognition access.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
    }
}
