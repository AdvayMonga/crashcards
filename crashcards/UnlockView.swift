import SwiftUI

/// Gate in front of blocked apps: answer questions until enough are right, then the shield
/// lifts for the grace window. Cards are drawn at random and keep coming until you're done.
struct UnlockView: View {
    let cards: [Card]
    let manager: ScreenTimeManager
    /// The app you were headed to, when the questions came from a gate link.
    var target: GatedApp?
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    @State private var question: Question?
    @State private var picked: Choice?
    @State private var correct = 0
    @State private var unlocked = false
    @State private var returnFailed = false
    @State private var misses = 0

    private var needed: Int { ScreenTimeManager.questionsToUnlock }

    var body: some View {
        ZStack {
            TableBackground()

            Group {
                if unlocked {
                    success
                } else if let question {
                    quiz(question)
                } else {
                    EmptyState(glyph: .question,
                               title: "No questions available",
                               message: "Add cards to your flashcards folder first.") {
                        Button("Close") { onClose() }
                            .buttonStyle(.soft)
                    }
                }
            }
            .shake(on: misses)
        }
        .safeAreaInset(edge: .top) { header }
        .animation(Motion.deal, value: unlocked)
        .onAppear { if question == nil { question = makeQuestion() } }
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

    private func quiz(_ question: Question) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                ProgressTrack(value: correct, total: needed,
                              label: "\(correct) of \(needed) correct")
                Text("\(correct) of \(needed) correct")
                    .font(.brandCaption)
                    .foregroundStyle(Brand.inkDim)
            }

            Text(question.prompt)
                .font(.brandCard)
                .foregroundStyle(Brand.cardInk)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.vertical, 30)
                .background {
                    RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                        .fill(Brand.cardFace)
                        .overlay(
                            RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                                .strokeBorder(Brand.outline, lineWidth: 3))
                        .shadow(color: .black.opacity(0.45), radius: 14, y: 10)
                }
                .breathing(0.7, period: 3.3)
                .id(question.cardID)
                .transition(.dealtCard)

            Spacer(minLength: 8)

            VStack(spacing: 12) {
                ForEach(question.choices) { choice in
                    choiceRow(choice)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .animation(Motion.deal, value: question.cardID)
    }

    private var success: some View {
        VStack(spacing: 16) {
            Spacer()
            PixelIcon(glyph: .lockOpen, size: 60, color: Brand.green)
                .padding(24)
                .slab(Brand.surfaceHigh, radius: Brand.cardRadius)
                .breathing(1.4, period: 3.0)

            Text("Unlocked for \(ScreenTimeManager.unlockMinutes) minutes")
                .font(.brandTitle)
                .foregroundStyle(Brand.ink)
                .multilineTextAlignment(.center)

            Text(returnFailed
                 ? "\(target?.name ?? "That app") didn't open. Check its link in Focus, or switch to it yourself."
                 : "Your apps re-block automatically when the time is up.")
                .font(.reading(15))
                .foregroundStyle(returnFailed ? Brand.mult : Brand.inkDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

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
        .padding(.horizontal, 26)
        .padding(.bottom, 26)
    }

    /// Hand you back to the app you were opening.
    private func goToTarget(_ app: GatedApp) {
        guard let url = app.returnURL else { returnFailed = true; return }
        GatedApps.recordRedirect(to: app)
        openURL(url) { opened in returnFailed = !opened }
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

    /// Score the tap, show the result briefly, then advance — or unlock once we hit the target.
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
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            if correct >= needed {
                manager.unlock()
                unlocked = true
                if let target { goToTarget(target) }
            } else {
                question = makeQuestion()
                picked = nil
            }
        }
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

    private func makeQuestion() -> Question? {
        let pool = answerable
        guard !pool.isEmpty else { return nil }
        // Avoid repeating the card just asked, unless it's the only one.
        let candidates = pool.count > 1 ? pool.filter { $0.id != question?.cardID } : pool
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
