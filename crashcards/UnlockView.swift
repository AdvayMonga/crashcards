import SwiftUI

/// Gate in front of blocked apps: answer questions until enough are right, then the shield
/// lifts for the grace window.
///
/// It's staged as one card being turned over. The masked joker lands first — a tragedy mask
/// over the face you were after, which is what being blocked is — and it arrives hard. Each
/// answer turns the card to the next question, and the turn that clears the gate takes the
/// mask off: the joker grins. It's the same face as the app icon, so the picture is
/// continuous from the home screen to the block screen to here.
struct UnlockView: View {
    let cards: [Card]
    let manager: ScreenTimeManager
    /// The app you were headed to, when the questions came from a gate link.
    var target: GatedApp?
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the card is showing, in the order it was turned to. Index 0 is always the mask.
    private enum Face {
        case masked
        case question(Question)
        case joker
    }

    @State private var faces: [Face] = [.masked]
    @State private var showing = 0
    @State private var turn: Double = 0
    /// The masked card's arrival: it drops in oversized and settles.
    @State private var landing: CGFloat = 1
    @State private var picked: Choice?
    @State private var correct = 0
    @State private var returnFailed = false
    @State private var misses = 0

    private var needed: Int { ScreenTimeManager.questionsToUnlock }
    private var unlocked: Bool {
        if case .joker = faces[showing] { return true }
        return false
    }

    var body: some View {
        ZStack {
            TableBackground()

            if answerable.isEmpty {
                EmptyState(glyph: .question,
                           title: "No questions available",
                           message: "Add cards to your flashcards folder first.") {
                    Button("Close") { onClose() }
                        .buttonStyle(.soft)
                }
            } else {
                gate
            }
        }
        .safeAreaInset(edge: .top) { header }
        .task { await land() }
    }

    // MARK: - The gate

    private var gate: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                ProgressTrack(value: correct, total: needed,
                              label: "\(correct) of \(needed) correct")
                Text(unlocked ? "Unlocked for \(ScreenTimeManager.unlockMinutes) minutes"
                              : "\(correct) of \(needed) correct")
                    .font(.brandCaption)
                    .foregroundStyle(unlocked ? Brand.green : Brand.inkDim)
            }

            CardFlipper(turn: turn) { index in
                face(faces[min(index, faces.count - 1)])
            }
            .aspectRatio(0.72, contentMode: .fit)
            .frame(maxHeight: .infinity)
            .scaleEffect(landing)
            .shake(on: misses)

            controls
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .animation(Motion.settle, value: correct)
    }

    @ViewBuilder
    private func face(_ face: Face) -> some View {
        switch face {
        case .masked:
            // Blue while it's shut, gold once it opens — the frame line picks up whichever
            // colour the figure on the card is wearing.
            CardFace(tint: Brand.chips) {
                portrait("MaskedJoker", caption: "Blocked")
            }
        case .question(let question):
            CardFace(tint: Brand.chips) {
                Text(question.prompt)
                    .font(.brandCard)
                    .foregroundStyle(Brand.cardInk)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, 30)
                CardIndex(text: "?", tint: Brand.chips)
            }
        case .joker:
            CardFace {
                portrait("JokerFigure", caption: "Yours")
            }
        }
    }

    /// The figure fills the card the way the icon fills its square — the face is the point,
    /// so it is given the room rather than floated in the middle of a lot of stock.
    private func portrait(_ image: String, caption: String) -> some View {
        VStack(spacing: 6) {
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
            Text(caption)
                .font(.pixel(22))
                .foregroundStyle(Brand.cardInk.opacity(0.6))
        }
        .padding(.horizontal, 26)
        .padding(.top, 26)
        .padding(.bottom, 20)
    }

    @ViewBuilder private var controls: some View {
        switch faces[showing] {
        case .masked:
            Text("Turning it over…")
                .font(.brandCaption)
                .foregroundStyle(Brand.inkFaint)
                .frame(height: 52)

        case .question(let question):
            VStack(spacing: 12) {
                ForEach(question.choices) { choice in
                    choiceRow(choice)
                }
            }
            .transition(.opacity)

        case .joker:
            VStack(spacing: 12) {
                if returnFailed {
                    Text("\(target?.name ?? "That app") didn't open. Check its link in Focus, or switch to it yourself.")
                        .font(.reading(14))
                        .foregroundStyle(Brand.mult)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let target {
                    Button("Open \(target.name)") { goToTarget(target) }
                        .buttonStyle(.solid(Brand.green))
                    Button("Stay here") { onClose() }
                        .buttonStyle(.soft)
                } else {
                    Button("Done") { onClose() }
                        .buttonStyle(.solid(Brand.green))
                }
            }
            .transition(.opacity)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if !unlocked {
                HeaderChip(glyph: .close, name: "Not now") { onClose() }
            }
            Spacer(minLength: 0)
            Text("Unlock")
                .font(.brandTitle)
                .foregroundStyle(Brand.ink)
                .shadow(color: Brand.outline, radius: 0, x: 2, y: 2)
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 1)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private func choiceRow(_ choice: Choice) -> some View {
        let judged = picked != nil
        let tint = tint(for: choice)
        return Button { answer(choice) } label: {
            HStack(spacing: 12) {
                Text(choice.text)
                    .font(.brandBody)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if judged, choice.isCorrect {
                    PixelIcon(glyph: .check, size: 18, color: Brand.outline)
                } else if judged, choice == picked {
                    PixelIcon(glyph: .close, size: 18, color: Brand.outline)
                }
            }
            .foregroundStyle(tint == nil ? Brand.ink : Brand.outline)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .slab(tint ?? Brand.surface, lift: tint != nil ? 0 : Brand.ledge,
                  highlight: tint == nil ? 0.08 : 0.22)
            .opacity(judged && tint == nil ? 0.4 : 1)
        }
        .buttonStyle(.pressable)
        .disabled(judged)
        .scaleEffect(judged && choice == picked ? 1.05 : 1)
        .animation(Motion.pop, value: picked)
    }

    private func tint(for choice: Choice) -> Color? {
        guard let picked else { return nil }
        if choice.isCorrect { return Brand.green }
        return choice == picked ? Brand.mult : nil
    }

    // MARK: - Staging

    /// The block landing: the lock card drops in oversized, settles, and turns itself over
    /// to the first question. Reduce Motion gets the question without the theatre.
    private func land() async {
        guard !faces.isEmpty, answerable.isEmpty == false else { return }
        guard !reduceMotion else {
            deal(makeQuestion().map(Face.question) ?? .joker)
            return
        }

        landing = 1.3
        Haptics.thud()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.52)) { landing = 1 }
        misses += 1   // one shake, so the block reads as an impact

        try? await Task.sleep(for: .seconds(0.75))
        deal(makeQuestion().map(Face.question) ?? .joker)
    }

    /// Turn the card to a new face.
    private func deal(_ next: Face) {
        faces.append(next)
        let index = faces.count - 1
        showing = index
        withAnimation(reduceMotion ? .easeInOut(duration: 0.22)
                                   : .spring(response: 0.5, dampingFraction: 0.72)) {
            turn = Double(index)
        }
    }

    /// Score the tap, let the colour land, then turn to whatever comes next.
    private func answer(_ choice: Choice) {
        guard picked == nil else { return }
        picked = choice
        if choice.isCorrect {
            correct += 1
            Haptics.correct()
        } else {
            Haptics.wrong()
            misses += 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.7))
            picked = nil
            if correct >= needed {
                manager.unlock()
                Haptics.thud()
                deal(.joker)
                if let target { goToTarget(target) }
            } else if let question = makeQuestion() {
                deal(.question(question))
            } else {
                deal(.joker)
            }
        }
    }

    /// Hand you back to the app you were opening.
    private func goToTarget(_ app: GatedApp) {
        guard let url = app.returnURL else { returnFailed = true; return }
        GatedApps.recordRedirect(to: app)
        openURL(url) { opened in returnFailed = !opened }
    }

    // MARK: - Question building

    struct Question {
        let cardID: Card.ID
        let prompt: String
        let choices: [Choice]
    }

    /// Cards that can be scored: multiple-choice cards use their own options; a flip card
    /// borrows other cards' answers as distractors, so it needs at least one to borrow.
    private var answerable: [Card] {
        let distinctAnswers = Set(cards.map(\.answer)).count
        return cards.filter { card in
            if case .multipleChoice = card.content { return true }
            return distinctAnswers >= 2
        }
    }

    /// The card the last question came from, so the next one can avoid repeating it.
    private var lastAsked: Card.ID? {
        for face in faces.reversed() {
            if case .question(let question) = face { return question.cardID }
        }
        return nil
    }

    private func makeQuestion() -> Question? {
        let pool = answerable
        guard !pool.isEmpty else { return nil }
        // Avoid repeating the card just asked, unless it's the only one.
        let candidates = pool.count > 1 ? pool.filter { $0.id != lastAsked } : pool
        guard let card = candidates.randomElement() else { return nil }

        switch card.content {
        case .multipleChoice(let prompt, let choices):
            return Question(cardID: card.id, prompt: prompt, choices: choices.shuffled())
        case .flip(let front, let back):
            let distractors = Set(cards.map(\.answer)).subtracting([back, ""])
            let picked = distractors.shuffled().prefix(3).map { Choice(text: $0, isCorrect: false) }
            return Question(cardID: card.id, prompt: front,
                            choices: (picked + [Choice(text: back, isCorrect: true)]).shuffled())
        }
    }
}
