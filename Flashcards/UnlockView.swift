import SwiftUI

/// Gate in front of blocked apps: answer questions until enough are right, then the shield
/// lifts for the grace window. Cards are drawn at random and keep coming until you're done.
struct UnlockView: View {
    let cards: [Card]
    let manager: ScreenTimeManager
    /// The app you were headed to, when the questions came from a gate link.
    var target: GatedApp?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var question: Question?
    @State private var picked: Choice?
    @State private var correct = 0
    @State private var unlocked = false
    @State private var returnFailed = false

    private var needed: Int { ScreenTimeManager.questionsToUnlock }

    var body: some View {
        VStack(spacing: 20) {
            if unlocked {
                success
            } else if let question {
                VStack(spacing: 8) {
                    ProgressTrack(value: correct, total: needed,
                                  label: "\(correct) of \(needed) correct")
                    Text("\(correct) of \(needed) correct")
                        .font(.brandCaption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                Text(question.prompt)
                    .font(.brandCard)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                ForEach(question.choices) { choice in
                    choiceRow(choice)
                }
                Spacer()
            } else {
                ContentUnavailableView("No questions available", systemImage: "questionmark.folder",
                                       description: Text("Add cards to your flashcards folder first."))
            }
        }
        .padding(20)
        .background(Brand.canvas)
        .navigationTitle("Unlock")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !unlocked {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not now") { dismiss() }
                }
            }
        }
        .onAppear { if question == nil { question = makeQuestion() } }
    }

    private var success: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Unlocked for \(ScreenTimeManager.unlockMinutes) minutes")
                .font(.brandTitle)
                .multilineTextAlignment(.center)
            Text(returnFailed
                 ? "\(target?.name ?? "That app") didn't open. Check its link in Focus, or switch to it yourself."
                 : "Your apps re-block automatically when the time is up.")
                .font(.subheadline)
                .foregroundStyle(returnFailed ? .red : .secondary)
                .multilineTextAlignment(.center)
            if let target {
                Button("Open \(target.name)") { goToTarget(target) }
                    .buttonStyle(.solid)
            }
            if target == nil {
                Button("Done") { dismiss() }
                    .buttonStyle(.solid)
            } else {
                Button("Stay here") { dismiss() }
                    .buttonStyle(.soft)
            }
        }
    }

    /// Hand you back to the app you were opening.
    private func goToTarget(_ app: GatedApp) {
        guard let url = app.returnURL else { returnFailed = true; return }
        GatedApps.recordRedirect(to: app)
        openURL(url) { opened in returnFailed = !opened }
    }

    private func choiceRow(_ choice: Choice) -> some View {
        Button { answer(choice) } label: {
            Text(choice.text)
                .font(.brandBody)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 17)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: Brand.controlRadius, style: .continuous)
                        .fill(background(for: choice))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.controlRadius, style: .continuous)
                        .strokeBorder(border(for: choice), lineWidth: picked == nil ? 1 : 2)
                )
        }
        .buttonStyle(.plain)
        .disabled(picked != nil)
    }

    private func background(for choice: Choice) -> Color {
        guard picked != nil else { return Brand.surface }
        return (tint(for: choice) ?? .clear).opacity(0.13)
    }

    private func border(for choice: Choice) -> Color {
        guard picked != nil else { return Brand.hairline }
        return tint(for: choice) ?? Brand.hairline
    }

    private func tint(for choice: Choice) -> Color? {
        guard let picked else { return nil }
        if choice.isCorrect { return Brand.correct }
        return choice == picked ? Brand.wrong : nil
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

    private struct Question {
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
