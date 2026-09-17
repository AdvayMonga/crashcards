import SwiftUI

/// Quiz: one question at a time, graded. Answering moves you on by itself — right or wrong,
/// you see the result for a beat and the next question arrives. No next button to hunt for.
struct QuizView: View {
    @State var session: StudySession
    @Environment(FlagStore.self) private var flags
    @Environment(\.dismiss) private var dismiss

    @State private var picked: Choice?
    @State private var flagging = false
    /// Held so a dismissed or restarted session can't be advanced by the previous one's timer.
    @State private var advance: Task<Void, Never>?

    var body: some View {
        ZStack {
            Brand.canvas.ignoresSafeArea()

            if session.isFinished {
                ScoreCard(session: session, onReview: review, onRestart: restart, onDone: { dismiss() })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let card = session.current {
                question(card)
                    .id(session.position)   // a new question animates in as its own view
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: session.position)
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: session.isFinished)
        .safeAreaInset(edge: .top) { header }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)   // studying is full-screen
        .onDisappear { advance?.cancel() }
        .confirmationDialog("Flag this card", isPresented: $flagging, titleVisibility: .visible) {
            FlagOptions(card: session.current)
        } message: {
            if let card = session.current { Text(card.prompt) }
        }
    }

    private func question(_ card: Card) -> some View {
        VStack(spacing: 24) {
            Text(card.prompt)
                .font(.brandCard)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.vertical, 36)
                .background(
                    RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                        .fill(Brand.surface)
                        .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
                )

            Spacer(minLength: 12)

            // Answers sit low, where your thumb already is.
            VStack(spacing: 12) {
                ForEach(choices(for: card)) { choice in
                    OptionRow(choice: choice, picked: picked) { answer(choice) }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    /// Quiz mode is only ever handed multiple-choice cards (`StudyMode.usableCards` filters
    /// to them), so the fallback is a formality rather than a way to self-grade a flip card.
    private func choices(for card: Card) -> [Choice] {
        guard case .multipleChoice(_, let choices) = card.content else {
            return [Choice(text: card.answer, isCorrect: true)]
        }
        return choices
    }

    private var header: some View {
        HStack(spacing: 14) {
            HeaderChip(symbol: "xmark", name: "Close", tint: .secondary) { dismiss() }

            ProgressTrack(value: session.position, total: session.total,
                          label: "Question \(min(session.position + 1, session.total)) of \(session.total)")

            Text("\(session.correctCount)")
                .font(.brandLabel)
                .foregroundStyle(Brand.correct)
                .frame(minWidth: 28)
                .accessibilityLabel("\(session.correctCount) correct so far")

            let flagged = flags.reason(for: session.current) != nil
            HeaderChip(symbol: flagged ? "flag.fill" : "flag",
                       name: flagged ? "Flagged" : "Flag this card",
                       tint: flagged ? Brand.accent : .secondary) { flagging = true }
                .disabled(session.current == nil || flags.isLocked)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .background(Brand.canvas)
    }

    // MARK: - Answering

    /// Score it, let the colour land, then move on by itself.
    ///
    /// `@MainActor` on the task matters: this method is nonisolated, so a plain `Task`
    /// would write `@State` and mutate the session off the main thread.
    private func answer(_ choice: Choice) {
        guard picked == nil else { return }
        picked = choice
        session.record(choice.isCorrect)
        choice.isCorrect ? Haptics.correct() : Haptics.wrong()

        advance?.cancel()
        advance = Task { @MainActor in
            try? await Task.sleep(for: .seconds(choice.isCorrect ? 0.55 : 0.95))
            guard !Task.isCancelled else { return }
            picked = nil
            session.next()
        }
    }

    private func review() {
        advance?.cancel()
        session = StudySession(cards: session.missedCards)
        picked = nil
    }

    private func restart() {
        advance?.cancel()
        session.restart()
        picked = nil
    }
}

/// One answer. Grows very slightly under the finger, then turns green or red once judged.
private struct OptionRow: View {
    let choice: Choice
    let picked: Choice?
    let action: () -> Void

    private var judged: Bool { picked != nil }
    private var isPicked: Bool { picked == choice }

    private var tint: Color? {
        guard judged else { return nil }
        if choice.isCorrect { return Brand.correct }
        return isPicked ? Brand.wrong : nil
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(choice.text)
                    .font(.brandBody)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let icon {
                    Image(systemName: icon).font(.brand(17, .bold))
                }
            }
            .foregroundStyle(tint ?? .primary)
            .padding(.vertical, 17)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: Brand.controlRadius, style: .continuous)
                    .fill(tint?.opacity(0.13) ?? Brand.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Brand.controlRadius, style: .continuous)
                    .strokeBorder(tint ?? Brand.hairline, lineWidth: tint == nil ? 1 : 2)
            )
            .opacity(judged && tint == nil ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(judged)
        .scaleEffect(isPicked && judged ? 1.02 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: picked)
    }

    private var icon: String? {
        guard judged else { return nil }
        if choice.isCorrect { return "checkmark.circle.fill" }
        return isPicked ? "xmark.circle.fill" : nil
    }
}

/// The end of a quiz: how you did, and the two things worth doing next.
private struct ScoreCard: View {
    let session: StudySession
    let onReview: () -> Void
    let onRestart: () -> Void
    let onDone: () -> Void

    private var missed: [Card] { session.missedCards }
    private var score: Int {
        guard session.total > 0 else { return 0 }
        return Int((Double(session.correctCount) / Double(session.total) * 100).rounded())
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("\(score)%")
                .font(.brand(64, .bold))
                .foregroundStyle(Brand.accent)
                .contentTransition(.numericText())
            Text(session.isEmpty
                 ? "No questions in these sets."
                 : "\(session.correctCount) of \(session.total) right")
                .font(.brandBody)
                .foregroundStyle(.secondary)
            Spacer()

            VStack(spacing: 12) {
                if !missed.isEmpty {
                    Button("Practise \(missed.count) missed") { onReview() }
                        .buttonStyle(.solid)
                }
                if !session.isEmpty {
                    Button("Start over") { onRestart() }
                        .buttonStyle(.soft)
                }
                Button("Done") { onDone() }
                    .buttonStyle(CrashButton(kind: .ghost))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .onAppear { score >= 50 ? Haptics.correct() : Haptics.knock() }
    }
}
