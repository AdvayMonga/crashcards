import SwiftUI

/// Gate in front of blocked apps: answer questions until enough are right, then the shield
/// lifts for the grace window. Cards are drawn at random and keep coming until you're done.
struct UnlockView: View {
    let cards: [Card]
    let manager: ScreenTimeManager
    @Environment(\.dismiss) private var dismiss

    @State private var question: Question?
    @State private var picked: Choice?
    @State private var correct = 0
    @State private var unlocked = false

    private var needed: Int { ScreenTimeManager.questionsToUnlock }

    var body: some View {
        VStack(spacing: 20) {
            if unlocked {
                success
            } else if let question {
                Text("\(correct) of \(needed) correct")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(question.prompt)
                    .font(.title3.weight(.semibold))
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
        .padding()
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
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Your apps re-block automatically when the time is up.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private func choiceRow(_ choice: Choice) -> some View {
        Button { answer(choice) } label: {
            Text(choice.text)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(background(for: choice))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separator)))
        }
        .buttonStyle(.plain)
        .disabled(picked != nil)
    }

    private func background(for choice: Choice) -> Color {
        guard let picked else { return Color(.secondarySystemBackground) }
        if choice.isCorrect { return .green.opacity(0.18) }
        if choice == picked { return .red.opacity(0.18) }
        return Color(.secondarySystemBackground)
    }

    /// Score the tap, show the result briefly, then advance — or unlock once we hit the target.
    private func answer(_ choice: Choice) {
        guard picked == nil else { return }
        picked = choice
        if choice.isCorrect { correct += 1 }
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            if correct >= needed {
                manager.unlock()
                unlocked = true
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
