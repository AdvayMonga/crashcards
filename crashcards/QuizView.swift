import SwiftUI

/// Quiz: one question at a time, graded. Answering moves you on by itself — right or wrong,
/// you see the result for a beat and the next question arrives. No next button to hunt for.
struct QuizView: View {
    @State var session: StudySession
    @Environment(FlagStore.self) private var flags
    let onClose: () -> Void

    @State private var picked: Choice?
    @State private var flagging = false
    /// Bumped on every wrong answer; the screen shakes once each time it changes.
    @State private var misses = 0
    /// Held so a dismissed or restarted session can't be advanced by the previous one's timer.
    @State private var advance: Task<Void, Never>?

    var body: some View {
        ZStack {
            TableBackground()

            Group {
                if session.isFinished {
                    ScoreCard(session: session, onReview: review,
                              onRestart: restart, onDone: onClose)
                } else if let card = session.current {
                    question(card)
                        .id(session.position)   // a new question is dealt as its own view
                        .transition(.dealtCard)
                }
            }
            .shake(on: misses)

            if flagging {
                CrashDialog(title: "Flag this card",
                            message: session.current?.prompt,
                            onCancel: { flagging = false }) {
                    FlagOptions(card: session.current) { flagging = false }
                }
                .zIndex(1)
            }
        }
        .animation(Motion.deal, value: session.position)
        .animation(Motion.deal, value: session.isFinished)
        .animation(Motion.pop, value: flagging)
        .safeAreaInset(edge: .top) { header }
        .onDisappear { advance?.cancel() }
    }

    private func question(_ card: Card) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            CardFace(tint: Brand.chips) {
                Text(card.prompt)
                    .font(.brandCard)
                    .foregroundStyle(Brand.cardInk)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 34)
                CardIndex(text: "?", tint: Brand.chips)
            }
            .fixedSize(horizontal: false, vertical: true)
            .breathing(0.7, period: 3.3)

            Spacer(minLength: 0)

            // Answers sit low, where your thumb already is.
            VStack(spacing: 12) {
                ForEach(choices(for: card)) { choice in
                    OptionRow(choice: choice, picked: picked) { answer(choice) }
                }
            }
        }
        .padding(.horizontal, 20)
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
        HStack(spacing: 12) {
            HeaderChip(glyph: .close, name: "Close") { onClose() }

            ProgressTrack(value: session.position, total: session.total,
                          label: "Question \(min(session.position + 1, session.total)) of \(session.total)")

            Text("\(session.correctCount)")
                .font(.brandNumber)
                .foregroundStyle(Brand.green)
                .frame(minWidth: 30)
                .contentTransition(.numericText())
                .accessibilityLabel("\(session.correctCount) correct so far")

            let flagged = flags.reason(for: session.current) != nil
            HeaderChip(glyph: flagged ? .flagFilled : .flag,
                       name: flagged ? "Flagged" : "Flag this card",
                       tint: flagged ? Brand.gold : Brand.inkDim) { flagging = true }
                .disabled(session.current == nil || flags.isLocked)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
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
        if choice.isCorrect {
            Haptics.correct()
        } else {
            Haptics.wrong()
            misses += 1
        }

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

/// One answer. Presses into its ledge like every other control, then lights up green or red.
private struct OptionRow: View {
    let choice: Choice
    let picked: Choice?
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var judged: Bool { picked != nil }
    private var isPicked: Bool { picked == choice }

    private var tint: Color? {
        guard judged else { return nil }
        if choice.isCorrect { return Brand.green }
        return isPicked ? Brand.mult : nil
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(choice.text)
                    .font(.brandBody)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let glyph {
                    PixelIcon(glyph: glyph, size: 18, color: Brand.outline)
                }
            }
            .foregroundStyle(tint == nil ? Brand.ink : Brand.outline)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .slab(tint ?? Brand.surface, lift: judged && tint != nil ? 0 : Brand.ledge,
                  highlight: tint == nil ? 0.08 : 0.22)
            .opacity(judged && tint == nil ? 0.4 : 1)
        }
        .buttonStyle(.pressable)
        .disabled(judged)
        // The chosen answer jumps when it lands; the other correct one just lights up.
        .scaleEffect(isPicked && judged ? 1.05 : 1)
        .animation(Motion.pop(reduceMotion), value: picked)
    }

    private var glyph: PixelGlyph? {
        guard judged else { return nil }
        if choice.isCorrect { return .check }
        return isPicked ? .close : nil
    }
}

/// The end of a quiz: how you did, and the two things worth doing next.
private struct ScoreCard: View {
    let session: StudySession
    let onReview: () -> Void
    let onRestart: () -> Void
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts up to `score` on arrival, the way a chip total does.
    @State private var shown = 0

    private var missed: [Card] { session.missedCards }
    private var score: Int {
        guard session.total > 0 else { return 0 }
        return Int((Double(session.correctCount) / Double(session.total) * 100).rounded())
    }
    private var tint: Color {
        if score >= 80 { return Brand.green }
        return score >= 50 ? Brand.gold : Brand.mult
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Text("\(shown)%")
                .font(.pixel(72, relativeTo: .largeTitle))
                .foregroundStyle(tint)
                .shadow(color: Brand.outline, radius: 0, x: 3, y: 4)
                .scaleEffect(shown == score && score > 0 ? 1 : 0.9)
                .animation(Motion.pop(reduceMotion), value: shown == score)

            Text(session.isEmpty
                 ? "No questions in these sets."
                 : "\(session.correctCount) of \(session.total) right")
                .font(.brandLabel)
                .foregroundStyle(Brand.inkDim)

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
                    .buttonStyle(CrashButton(kind: .ghost, tint: Brand.inkDim))
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 26)
        .task { await rollUp() }
    }

    /// Ticks the number up rather than snapping it, so the result lands as an event.
    private func rollUp() async {
        score >= 50 ? Haptics.correct() : Haptics.knock()
        guard !reduceMotion, score > 0 else { shown = score; return }
        let step = max(1, score / 24)
        while shown < score {
            shown = min(score, shown + step)
            Haptics.tap()
            try? await Task.sleep(for: .milliseconds(28))
        }
    }
}
