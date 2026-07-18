import SwiftUI

/// Classic study: one card at a time. Flip cards tap to reveal; multiple-choice cards
/// tap an option. Swipe or arrows move between cards; shuffle restarts.
struct StudyView: View {
    @State var session: StudySession
    @State private var picked: Choice?          // selected option for the current MC card
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            if session.isFinished {
                completion
            } else {
                Text(session.progressText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                currentCard
                controls
            }
        }
        .padding()
        .navigationTitle("Classic")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)   // disable the edge swipe-back-to-home
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Label("Sets", systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { session.restart() } label: {
                    Image(systemName: "shuffle")
                }
                .disabled(session.isEmpty)
            }
        }
        .onChange(of: session.position) { _, _ in picked = nil }
    }

    // MARK: - Current card

    @ViewBuilder private var currentCard: some View {
        if let card = session.current {
            Group {
                switch card.content {
                case .flip(let front, let back):
                    flipCard(front: front, back: back)
                case .multipleChoice(let question, let choices):
                    mcCard(question: question, choices: choices)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20).onEnded { handleSwipe($0.translation) }
            )
        }
    }

    private func flipCard(front: String, back: String) -> some View {
        VStack {
            Spacer()
            Text(session.isFlipped ? back : front)
                .font(.title2.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(24)
            Spacer()
            Text(session.isFlipped ? "answer" : "tap to reveal")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, minHeight: 340)
        .background(session.isFlipped ? Color(.secondarySystemBackground) : Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color(.separator)))
        .contentShape(Rectangle())
        .onTapGesture { session.flip() }
    }

    private func mcCard(question: String, choices: [Choice]) -> some View {
        VStack(spacing: 16) {
            Text(question)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            ForEach(choices) { choice in
                choiceRow(choice)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 340, alignment: .top)
    }

    private func choiceRow(_ choice: Choice) -> some View {
        let state = choiceState(for: choice)
        return Button {
            if picked == nil { picked = choice }
        } label: {
            HStack {
                Text(choice.text)
                    .multilineTextAlignment(.leading)
                Spacer()
                if let icon = state.icon {
                    Image(systemName: icon).foregroundStyle(state.tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(state.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(state.border))
        }
        .buttonStyle(.plain)
        .foregroundStyle(state.foreground)
        .disabled(picked != nil)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button { session.prev() } label: {
                Image(systemName: "chevron.left").font(.title3)
            }
            .buttonStyle(.bordered)
            .disabled(session.position == 0)

            if currentIsFlip {
                Button(session.isFlipped ? "Hide" : "Flip") { session.flip() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            } else {
                Spacer()
            }

            Button { session.next() } label: {
                Image(systemName: "chevron.right").font(.title3)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private var completion: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(session.isEmpty ? "No cards to study." : "Deck complete.")
                .font(.title2.weight(.semibold))
            if !session.isEmpty {
                Button("Study Again") { session.restart() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    // MARK: - Helpers

    private var currentIsFlip: Bool {
        guard let content = session.current?.content else { return false }
        if case .flip = content { return true }
        return false
    }

    /// A decisive horizontal swipe moves cards: left = next, right = previous.
    private func handleSwipe(_ translation: CGSize) {
        guard abs(translation.width) > 50, abs(translation.width) > abs(translation.height) else { return }
        if translation.width < 0 { session.next() } else { session.prev() }
    }

    /// Visual state of an MC option once the user has answered.
    private struct ChoiceStyle {
        var background: Color
        var border: Color
        var foreground: Color
        var tint: Color
        var icon: String?
    }

    private func choiceState(for choice: Choice) -> ChoiceStyle {
        guard let picked else {
            return ChoiceStyle(background: Color(.secondarySystemBackground),
                               border: Color(.separator), foreground: .primary, tint: .primary, icon: nil)
        }
        if choice.isCorrect {
            return ChoiceStyle(background: .green.opacity(0.18), border: .green,
                               foreground: .primary, tint: .green, icon: "checkmark.circle.fill")
        }
        if choice == picked {
            return ChoiceStyle(background: .red.opacity(0.18), border: .red,
                               foreground: .primary, tint: .red, icon: "xmark.circle.fill")
        }
        return ChoiceStyle(background: Color(.secondarySystemBackground),
                           border: Color(.separator), foreground: .secondary, tint: .secondary, icon: nil)
    }
}
