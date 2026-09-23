import SwiftUI
import UIKit

/// Quiz: one question at a time, graded. Answering moves you on by itself — right or wrong,
/// you see the result for a beat and the next question arrives. No next button to hunt for.
struct QuizView: View {
    @State var session: StudySession
    @Environment(StatsStore.self) private var stats
    let onClose: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    @State private var picked: Choice?
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
    /// What's been typed on a typed card, and how it was judged once submitted.
    @State private var typed = ""
    @State private var typedVerdict: TypedVerdict?
    /// Set when you gave up on a multiple-choice card: the answer lights up, nothing is
    /// marked as your pick, and the card moves on by itself.
    @State private var revealed = false
    /// Held here rather than inside `TypedAnswer` so tapping the table can put the keyboard
    /// away, and so a card that lands its verdict can let go of the field.
    @FocusState private var typing: Bool
    /// The prompt waiting for you to say which chatbot should answer it.
    @State private var explaining: ExplainRequest?

    var body: some View {
        ZStack {
            // Tapping anywhere that isn't a control puts the keyboard away. The background
            // is the only thing under everything else, so this can't swallow an answer tap.
            TableBackground()
                .contentShape(Rectangle())
                .onTapGesture { typing = false }

            Group {
                if session.isFinished {
                    ScoreCard(session: session, onReview: review,
                              onRestart: restart, onDone: onClose,
                              onExplain: { explaining = $0 })
                } else if let card = session.current {
                    question(card)
                        .id(session.position)   // a new question is dealt as its own view
                        .transition(.dealtCard)
                }
            }
            .shake(on: misses)

        }
        .animation(Motion.deal, value: session.position)
        .animation(Motion.deal, value: session.isFinished)
        .animation(Motion.pop, value: gain)
        .safeAreaInset(edge: .top) { header }
        .screenLayer(item: $explaining) { request in
            AIPickerView(prompt: request.prompt) { explaining = nil }
        }
        .onChange(of: session.position) { _, _ in
            // Cleared here rather than in the advance task so that every route to a new
            // card — answering, practising the missed ones, starting over — arrives with an
            // empty box. Leaving the verdict set froze the card: both submit paths bail out
            // while one stands.
            typed = ""
            typedVerdict = nil
            revealed = false
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
        let accepted = card.typedAnswers
        return VStack(spacing: 22) {
            // A typed card holds the question at the top so the keyboard has nothing but
            // empty table to cover. A tapped one has no keyboard to plan around, so it
            // keeps floating in the middle with its answers low.
            if accepted == nil { Spacer(minLength: 0) }

            CardFace(tint: Brand.chips) {
                Text(card.prompt)
                    .font(.brandCard)
                    .foregroundStyle(Brand.cardInk)
                    .multilineTextAlignment(.center)
                    // Shrinks first, then truncates. Without a line limit the card grows
                    // with the question and a long one runs off the screen.
                    .lineLimit(9)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 34)
                CardIndex(text: "?", tint: Brand.chips)
            }
            // The one card that doesn't breathe: it's being read, and the keyboard under a
            // typed card is right there for the wobble to show against.
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .bottom) {
                if let gain {
                    GainBadge(gain: gain)
                }
            }

            if let accepted {
                // Directly under the question rather than at the foot of the screen: that
                // is the whole reason nothing jumps when the keyboard arrives.
                TypedAnswer(accepted: accepted, verdict: typedVerdict, text: $typed,
                            typing: $typing, onSubmit: { submitTyped(accepted) })
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)

                // Tapped answers stay low, where your thumb already is.
                VStack(spacing: 12) {
                    ForEach(choices(for: card)) { choice in
                        OptionRow(choice: choice, picked: picked, revealed: revealed) {
                            answer(choice)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    /// Only reached for cards that have options: anything else took the typed branch, so
    /// the fallback is a formality rather than a way to self-grade a flip card.
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

            HeaderChip(glyph: .eye, name: "Reveal the answer",
                       tint: canReveal ? Brand.inkDim : Brand.inkFaint) { reveal() }
                .disabled(!canReveal)
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

    /// Grade what was typed, show the answer either way, then move on like a tapped card.
    private func submitTyped(_ accepted: [String]) {
        guard typedVerdict == nil else { return }
        let right = AnswerMatcher.matches(typed, anyOf: accepted)
        land(right, verdict: right ? .right : .wrong(accepted))
    }

    private func land(_ right: Bool, verdict: TypedVerdict) {
        typedVerdict = verdict
        session.record(right, elapsed: wentAway ? .infinity : Date().timeIntervalSince(shownAt))
        if right {
            gain = session.score.lastGain
            Haptics.correct()
        } else {
            Haptics.wrong()
            misses += 1
        }

        advance?.cancel()
        advance = Task { @MainActor in
            // Longer than a tapped card: the answer you missed is there to be read.
            try? await Task.sleep(for: .seconds(right ? 0.8 : 1.8))
            guard !Task.isCancelled else { return }
            gain = nil
            session.next()
        }
    }

    /// Give up on the question: show what the answer was, then move on like any other card.
    ///
    /// Scored as a miss. You didn't know it, so the streak breaks and it goes into the
    /// review round — which is the whole reason for having one.
    private var canReveal: Bool {
        session.current != nil && picked == nil && typedVerdict == nil && !revealed
    }

    private func reveal() {
        guard let card = session.current, canReveal else { return }
        // Softer than a wrong answer, and no shake: you chose to see this, you didn't
        // walk into it.
        Haptics.knock()

        if let accepted = card.typedAnswers {
            typedVerdict = .wrong(accepted)
        } else {
            revealed = true
        }
        session.record(false, elapsed: .infinity)

        advance?.cancel()
        advance = Task { @MainActor in
            // Longer than a tapped card: an answer you didn't know is there to be read.
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
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
        typed = ""
        typedVerdict = nil
        revealed = false
        shownAt = Date()
        wentAway = false
    }
}

/// How a typed answer was judged, carrying what the card would have accepted so the card
/// can teach on the way past.
enum TypedVerdict: Equatable {
    case right
    case wrong([String])

    var accepted: [String] {
        switch self {
        case .right: return []
        case .wrong(let accepted): return accepted
        }
    }
    var isRight: Bool { self == .right }
}

/// The typed answer, wearing the same clothes as a tapped one.
///
/// Typed on the quiz's own keyboard rather than the system one, so nothing above it moves.
/// Judged, it becomes the rows a multiple-choice card would show: the answer in green
/// with a tick, and what you typed in red beneath it when they differ. Same slab, same
/// glyphs, same colours — the only difference is where the answer came from.
private struct TypedAnswer: View {
    let accepted: [String]
    let verdict: TypedVerdict?
    @Binding var text: String
    @FocusState.Binding var typing: Bool
    let onSubmit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var blank: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 12) {
            if let verdict {
                AnswerRow(text: accepted[0], tint: Brand.green, glyph: .check)
                    .scaleEffect(verdict.isRight ? 1.05 : 1)
                    .animation(Motion.pop(reduceMotion), value: verdict)
                if !verdict.isRight, !text.isEmpty {
                    AnswerRow(text: text, tint: Brand.mult, glyph: .close)
                }
            } else {
                CrashField(placeholder: "Type your answer", text: $text)
                    // Pinned, not merely floored: with a spacer below rather than above,
                    // the field would otherwise take every point going.
                    .frame(height: 46)
                    .focused($typing)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    // Return checks a written answer and simply puts the keyboard away on
                    // an empty one, so the key is never a dead end.
                    .onSubmit { if blank { typing = false } else { onSubmit() } }

                Button("Check") { onSubmit() }
                    .buttonStyle(.solid(Brand.chips))
                    .disabled(blank)
            }
        }
        // Fixed, so the question above doesn't move when the field gives way to the
        // verdict — two rows and a field-plus-button come to about the same height.
        .frame(maxWidth: .infinity, minHeight: 124, maxHeight: 124, alignment: .top)
        .onAppear { typing = true }
    }
}

/// One judged row, drawn the way `OptionRow` draws a judged option.
private struct AnswerRow: View {
    let text: String
    let tint: Color
    let glyph: PixelGlyph

    var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.brandBody)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
            PixelIcon(glyph: glyph, size: 18, color: Brand.outline)
        }
        .foregroundStyle(Brand.outline)
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .slab(tint, lift: 0, highlight: 0.22)
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }
}

/// One answer. Presses into its ledge like every other control, then lights up green or red.
private struct OptionRow: View {
    let choice: Choice
    let picked: Choice?
    /// The answer was given away rather than chosen: the right option lights up and no
    /// option is marked as yours, because none was.
    var revealed = false
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var judged: Bool { picked != nil || revealed }
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
                    // Two lines, shrinking to fit rather than growing: four options at four
                    // lines each pushed the question off the top of the screen. Anything
                    // too long to fit at this scale is reported in File Problems instead of
                    // being quietly cut, because the fix belongs in the deck.
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
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
        .animation(Motion.pop(reduceMotion), value: revealed)
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
    /// Handed up so the picker is presented over the whole screen, not inside this card.
    let onExplain: (ExplainRequest) -> Void

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

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Text("\(shown)%")
                .font(.pixel(72))
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
                        .font(.pixel(36))
                        .foregroundStyle(Brand.gold)
                        .shadow(color: Brand.outline, radius: 0, x: 2, y: 2)
                    Text("POINTS")
                        .font(.brandCaption)
                        .tracking(1.4)
                        .foregroundStyle(Brand.gold)

                    // Its own line rather than a clause after POINTS, so it reads as the
                    // event it is instead of a footnote on the total.
                    if session.score.perfectBonus > 0 {
                        Text("PERFECT RUN  +\(session.score.perfectBonus)")
                            .font(.brandCaption)
                            .tracking(1.4)
                            .foregroundStyle(Brand.green)
                            .padding(.top, 6)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .padding(.top, 4)
            }

            Spacer()

            VStack(spacing: 12) {
                if !missed.isEmpty {
                    Button("Practise \(missed.count) missed") { onReview() }
                        .buttonStyle(.solid)
                    // The end of the run, not the moment of answering: a wrong answer moves
                    // you on by itself, and stopping the quiz dead to leave for a chat app
                    // would undo the thing that makes it a quiz.
                    Button("Explain \(missed.count) missed with AI") {
                        Haptics.tap()
                        onExplain(ExplainRequest(prompt: ExplainPrompt.text(for: missed)))
                    }
                    .buttonStyle(.soft(Brand.chips))
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
