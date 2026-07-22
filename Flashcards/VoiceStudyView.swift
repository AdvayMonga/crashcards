import SwiftUI

/// Hands-free voice study: the app speaks prompts and listens for spoken answers.
struct VoiceStudyView: View {
    @State private var controller: VoiceStudyController
    @Environment(\.dismiss) private var dismiss

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

            if let card = controller.session.current {
                Text(cardPrompt(card))
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
        }
        .padding()
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { controller.stop() }
    }

    private func cardPrompt(_ card: Card) -> String {
        switch card.content {
        case .flip(let front, _): return front
        case .multipleChoice(let question, _): return question
        }
    }
}
