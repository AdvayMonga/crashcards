import SwiftUI
import FamilyControls

/// Gate in front of blocked apps: answer questions until enough are right, then the shield
/// lifts for the grace window.
///
/// Deliberately the quiz screen with a different scoreboard. A question in front of your
/// apps is still a question, so it is laid out the way every other question in the app is —
/// full-width card, answers low where your thumb is — and the only thing the gate adds is
/// the bar counting how many more it wants. Clearing it turns up the joker: the same face
/// as the app icon and the block screen, so the picture stays continuous.
struct UnlockView: View {
    let cards: [Card]
    let manager: ScreenTimeManager
    /// The app you were headed to, when the questions came from the shield's Answer button.
    var tapped: PendingGate?
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(StatsStore.self) private var stats

    /// The question on screen, and how many have come before it — the counter doubles as the
    /// identity that deals each question as its own view.
    @State private var question: Question?
    @State private var position = 0
    @State private var unlocked = false
    @State private var picked: Choice?
    @State private var correct = 0
    @State private var answered = 0
    @State private var startedAt = Date()
    @State private var recorded = false
    @State private var returnFailed = false
    @State private var misses = 0

    private var needed: Int { manager.questionsToUnlock }

    /// The app we can send you back to, if we recognise it.
    private var wayBack: URL? { AppLinks.url(forAppNamed: tapped?.name) }

    var body: some View {
        ZStack {
            TableBackground()

            if answerable.isEmpty {
                EmptyState(glyph: .question,
                           title: "No questions to ask",
                           message: cards.isEmpty
                                ? "Add a set on the Study tab, then come back to unlock."
                                : "Your sets need either multiple-choice questions or two cards with different answers.") {
                    Button("Close") { onClose() }
                        .buttonStyle(.soft)
                }
            } else if unlocked {
                cleared
            } else if let question {
                ask(question)
                    .id(position)   // a new question is dealt as its own view
                    .transition(.dealtCard)
            }
        }
        .animation(Motion.deal, value: position)
        .animation(Motion.deal, value: unlocked)
        .safeAreaInset(edge: .top) { header }
        // Keyed on the pool, not just on appearing: the gate can be put on screen in the
        // same pass that the library is still loading in, and a question picked from nothing
        // is no question at all. When the cards land, this runs again.
        .task(id: answerable.count) { if question == nil { question = makeQuestion() } }
        .onDisappear { bank(unlocked: false) }
    }

    // MARK: - The question

    /// The quiz's layout, point for point: the card floats in the middle at full width and
    /// sizes itself to the question, and the answers sit low.
    private func ask(_ question: Question) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            CardFace(tint: Brand.chips) {
                Text(question.prompt)
                    .font(.brandCard)
                    .foregroundStyle(Brand.cardInk)
                    .multilineTextAlignment(.center)
                    // Shrinks first, then truncates — the same rule the quiz card follows,
                    // so a question that fits there fits here.
                    .lineLimit(9)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 34)
                CardIndex(text: "?", tint: Brand.chips)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                ForEach(question.choices) { choice in
                    OptionRow(choice: choice, picked: picked) { answer(choice) }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .shake(on: misses)
    }

    // MARK: - Cleared

    /// The reward, and the way back. The joker gets the whole card because it's the only
    /// thing on the screen at this point.
    private var cleared: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            CardFace {
                VStack(spacing: 6) {
                    Image("JokerFigure")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                    Text("Yours")
                        .font(.pixel(22))
                        .foregroundStyle(Brand.cardInk.opacity(0.6))
                }
                .padding(.horizontal, 26)
                .padding(.top, 26)
                .padding(.bottom, 20)
            }
            .aspectRatio(0.72, contentMode: .fit)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                if returnFailed {
                    Text("\(tapped?.name ?? "That app") wouldn't open. Switch to it yourself — it's unblocked either way.")
                        .font(.reading(14))
                        .foregroundStyle(Brand.mult)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let name = tapped?.name, wayBack != nil {
                    Button("Open \(name)") { goBack() }
                        .buttonStyle(.solid(Brand.green))
                    Button("Stay here") { onClose() }
                        .buttonStyle(.soft)
                } else {
                    Button("Done") { onClose() }
                        .buttonStyle(.solid(Brand.green))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    /// Send you back to the app you were opening. Nothing to do if we don't know its link —
    /// the shield is down, so switching back by hand works.
    private func goBack() {
        guard let url = wayBack else { returnFailed = true; return }
        openURL(url) { opened in returnFailed = !opened }
    }

    // MARK: - Chrome

    /// The quiz's header without the things a gate doesn't have: no score, and no reveal —
    /// giving the answer away is the one thing that would make the gate pointless.
    private var header: some View {
        HStack(spacing: 12) {
            if unlocked {
                Color.clear.frame(width: 44, height: 1)
            } else {
                HeaderChip(glyph: .close, name: "Not now") { onClose() }
            }

            ProgressTrack(value: correct, total: needed,
                          label: "\(correct) of \(needed) correct")

            Text(unlocked ? "\(manager.unlockMinutes) min" : "\(correct)/\(needed)")
                .font(.brandNumber)
                .foregroundStyle(unlocked ? Brand.green : Brand.gold)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
        .animation(Motion.settle, value: correct)
    }

    // MARK: - Answering

    /// Score the tap, let the colour land, then move on — the quiz's timings exactly.
    private func answer(_ choice: Choice) {
        guard picked == nil else { return }
        picked = choice
        answered += 1
        if choice.isCorrect {
            correct += 1
            Haptics.correct()
        } else {
            Haptics.wrong()
            misses += 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(choice.isCorrect ? 0.55 : 0.95))
            picked = nil
            if correct >= needed {
                manager.unlock()
                bank(unlocked: true)
                Haptics.thud()
                unlocked = true
                goBack()
            } else {
                question = makeQuestion()
                position += 1
            }
        }
    }

    /// The gate isn't scored — that's quiz mode's job — but its questions are still
    /// questions, so they count toward what you've answered and how accurate you are.
    ///
    /// Banked the instant the gate clears rather than when the view goes away: clearing it
    /// hands you to another app, which can background this one first.
    private func bank(unlocked: Bool) {
        guard !recorded, answered > 0 else { return }
        recorded = true
        stats.record(StudyRun(answered: answered, correct: correct,
                              seconds: StatsStore.studySeconds(since: startedAt, answered: answered),
                              unlocks: unlocked ? 1 : 0))
    }

    // MARK: - Question building

    struct Question {
        let cardID: Card.ID
        let prompt: String
        let choices: [Choice]
    }

    /// Cards that can be scored: multiple-choice cards use their own options; a flip card
    /// borrows other cards' answers as distractors, so it needs at least one to borrow.
    ///
    /// Static so the Focus tab can ask the same question before offering the gate. Counting
    /// quiz cards there instead would offer an unlock that lands on "No questions available"
    /// — a deck of flip cards that all share one answer has plenty of cards and no questions.
    static func answerable(in cards: [Card]) -> [Card] {
        let distinctAnswers = Set(cards.map(\.answer)).count
        return cards.filter { card in
            if case .multipleChoice = card.content { return true }
            return distinctAnswers >= 2
        }
    }

    private var answerable: [Card] { Self.answerable(in: cards) }

    private func makeQuestion() -> Question? {
        let pool = answerable
        guard !pool.isEmpty else { return nil }
        // Avoid repeating the card just asked, unless it's the only one.
        let lastAsked = question?.cardID
        let candidates = pool.count > 1 ? pool.filter { $0.id != lastAsked } : pool
        guard let card = candidates.randomElement() else { return nil }

        switch card.content {
        case .multipleChoice(let prompt, let choices):
            return Question(cardID: card.id, prompt: prompt, choices: choices.shuffled())
        // Typed cards are borrowed from the same way flip cards are. The gate stays a
        // tapping screen on purpose: it stands between you and an app you already reached
        // for, so it has to be answerable in a second, not typed into.
        case .flip, .typed:
            let answer = card.answer
            let distractors = Set(cards.map(\.answer)).subtracting([answer, ""])
            let picked = distractors.shuffled().prefix(3).map { Choice(text: $0, isCorrect: false) }
            return Question(cardID: card.id, prompt: card.prompt,
                            choices: (picked + [Choice(text: answer, isCorrect: true)]).shuffled())
        }
    }
}
