import SwiftUI

/// Quiz: one question at a time, graded. Answering moves you on by itself — right or wrong,
/// you see the result for a beat and the next question arrives. No next button to hunt for.
struct QuizView: View {
    @State var session: StudySession
    @Environment(FlagStore.self) private var flags
    @Environment(StatsStore.self) private var stats
    let onClose: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    @State private var picked: Choice?
    @State private var flagging = false
    /// Bumped on every wrong answer; the screen shakes once each time it changes.
    @State private var misses = 0
    /// When the question on screen was dealt, and whether you left the app while it stood.
    /// A question you walked away from can't be a fast one, and tracking the stopwatch
    /// across a suspend to work that out costs more than it's worth.
    @State private var shownAt = Date()
    @State private var wentAway = false
    /// What the last answer paid, shown briefly on the card that earned it.
    @State private var gain: Int?
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
        .animation(Motion.pop, value: gain)
        .safeAreaInset(edge: .top) { header }
        .onChange(of: session.position) { _, _ in
            shownAt = Date()
            wentAway = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { wentAway = true }
        }
        // Banked the moment the last question lands, so a run that ends the way it's meant
        // to is never lost to the app being killed on the score screen.
        .onChange(of: session.isFinished) { _, finished in
            guard finished else { return }
            session.score.finish()   // pays the perfect bonus before the run is banked
            bank()
        }
        .onDisappear {
            advance?.cancel()
            bank()
        }
    }

    /// Hand this run's questions to the lifetime totals. Idempotent — whichever of the two
    /// call sites gets there first is the one that counts.
    private func bank() {
        if let run = session.consumeRun() { stats.record(run) }
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
            .overlay(alignment: .bottom) {
                if let gain {
                    GainBadge(gain: gain)
                }
            }

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

            ScoreReadout(score: session.score)

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
        session.record(choice.isCorrect, elapsed: wentAway ? .infinity : Date().timeIntervalSince(shownAt))
        if choice.isCorrect {
            gain = session.score.lastGain
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
            gain = nil
            session.next()
        }
    }

    private func review() {
        advance?.cancel()
        session = StudySession(cards: session.missedCards, dayStreak: session.dayStreak)
        reset()
    }

    private func restart() {
        advance?.cancel()
        session.restart()
        reset()
    }

    private func reset() {
        picked = nil
        gain = nil
        shownAt = Date()
        wentAway = false
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
    /// Counts up to `percent` on arrival, the way a chip total does.
    @State private var shown = 0

    private var missed: [Card] { session.missedCards }
    private var percent: Int {
        guard session.total > 0 else { return 0 }
        return Int((Double(session.correctCount) / Double(session.total) * 100).rounded())
    }
    private var tint: Color {
        if percent >= 80 { return Brand.green }
        return percent >= 50 ? Brand.gold : Brand.mult
    }

    /// The line under the points. A perfect run says so and nothing else — it already tells
    /// you the streak went the distance.
    private var footnote: String {
        let score = session.score
        if score.perfectBonus > 0 { return "perfect run · +\(score.perfectBonus)" }
        if score.bestStreak >= 3 { return "points · best run of \(score.bestStreak)" }
        return "points"
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Text("\(shown)%")
                .font(.pixel(72, relativeTo: .largeTitle))
                .foregroundStyle(tint)
                .shadow(color: Brand.outline, radius: 0, x: 3, y: 4)
                .scaleEffect(shown == percent && percent > 0 ? 1 : 0.9)
                .animation(Motion.pop(reduceMotion), value: shown == percent)

            Text(session.isEmpty
                 ? "No questions in these sets."
                 : "\(session.correctCount) of \(session.total) right")
                .font(.brandLabel)
                .foregroundStyle(Brand.inkDim)

            if session.score.total > 0 {
                VStack(spacing: 2) {
                    Text("\(session.score.total)")
                        .font(.pixel(36, relativeTo: .title))
                        .foregroundStyle(Brand.gold)
                        .shadow(color: Brand.outline, radius: 0, x: 2, y: 2)
                    Text(footnote)
                        .font(.brandCaption)
                        .foregroundStyle(session.score.perfectBonus > 0 ? Brand.green : Brand.inkDim)
                }
                .padding(.top, 4)
            }

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
        percent >= 50 ? Haptics.correct() : Haptics.knock()
        guard !reduceMotion, percent > 0 else { shown = percent; return }
        let step = max(1, percent / 24)
        while shown < percent {
            shown = min(percent, shown + step)
            Haptics.tap()
            try? await Task.sleep(for: .milliseconds(28))
        }
    }
}

/// "×2" rather than "×2.0" — only the half step a daily streak pays needs a decimal.
private func multText(_ value: Double) -> String {
    value == value.rounded() ? "×\(Int(value))" : "×\(String(format: "%.1f", value))"
}

/// The running total, with the mult riding beside it. The mult shows only once it's paying
/// more than ×1: a permanent ×1 is furniture.
private struct ScoreReadout: View {
    let score: ScoreRun

    var body: some View {
        HStack(spacing: 5) {
            Text("\(score.total)")
                .font(.brandNumber)
                .foregroundStyle(Brand.gold)
                .contentTransition(.numericText())
            if score.pendingMult > 1 {
                Text(multText(score.pendingMult))
                    .font(.brandCaption)
                    .foregroundStyle(Brand.mult)
                    .contentTransition(.numericText())
            }
        }
        .frame(minWidth: 34)
        .accessibilityElement()
        .accessibilityLabel("\(score.total) points, next answer worth \(multText(score.pendingMult))")
    }
}

/// What the answer just paid, rising off the card that earned it.
private struct GainBadge: View {
    let gain: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lifted = false

    var body: some View {
        Text("+\(gain)")
            .font(.brandNumber)
            .foregroundStyle(Brand.gold)
            .shadow(color: Brand.outline, radius: 0, x: 2, y: 2)
            .offset(y: lifted ? -40 : 4)
            .opacity(lifted ? 0 : 1)
            .accessibilityHidden(true)
            .task {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.6)) { lifted = true }
            }
    }
}
