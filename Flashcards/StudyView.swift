import SwiftUI

/// A deck you scroll through, one card per page, ending on the score. Flashcards mode
/// reveals the answer on tap — for a multiple-choice card that answer is its correct
/// option. Quiz mode shows the options to pick from. Shuffle restarts.
struct StudyView: View {
    @State var session: StudySession
    let mode: StudyMode
    @State private var picked: Choice?          // selected option for the current MC card
    @State private var flagging = false
    @Environment(FlagStore.self) private var flags
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            if !session.isFinished {
                Text(session.progressText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            pager
            if currentIsReveal && session.isFlipped {
                gradeBar
            }
        }
        .padding()
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)   // disable the edge swipe-back-to-home
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Label("Sets", systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { flagging = true } label: {
                    Image(systemName: flags.reason(for: session.current) == nil ? "flag" : "flag.fill")
                }
                .disabled(session.current == nil || flags.isLocked)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { restart() } label: {
                    Image(systemName: "shuffle")
                }
                .disabled(session.isEmpty)
            }
        }
        .onChange(of: session.position) { _, _ in picked = nil }
        .confirmationDialog("Flag this card", isPresented: $flagging, titleVisibility: .visible) {
            flagOptions
        } message: {
            if let card = session.current { Text(card.prompt) }
        }
        .alert("Couldn't write \(FlagStore.filename)",
               isPresented: .init(get: { flags.writeError != nil },
                                  set: { if !$0 { flags.writeError = nil } })) {
            Button("OK") { flags.writeError = nil }
        } message: {
            Text(flags.writeError ?? "")
        }
    }

    // MARK: - Cards

    /// One page per card, with the score as the page after the last one.
    private var pager: some View {
        TabView(selection: pageSelection) {
            ForEach(0..<session.total, id: \.self) { index in
                page(at: index)
                    .padding(.horizontal, 4)
                    .tag(index)
            }
            completion.tag(session.total)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.default, value: session.position)
    }

    private var pageSelection: Binding<Int> {
        Binding(get: { session.position }, set: { session.go(to: $0) })
    }

    /// Neighbouring pages are built before you reach them, so "is this the one on screen?"
    /// decides whether the answer shows — otherwise the next card arrives already revealed.
    @ViewBuilder private func page(at index: Int) -> some View {
        if let card = session.card(at: index) {
            let isCurrent = index == session.position
            switch card.content {
            case .flip(let front, let back):
                flipCard(front: front, back: back, revealed: isCurrent && session.isFlipped)
            case .multipleChoice(let question, let choices):
                if mode == .quiz {
                    mcCard(question: question, choices: choices, isCurrent: isCurrent)
                } else {
                    flipCard(front: question, back: card.answer,
                             revealed: isCurrent && session.isFlipped)
                }
            }
        }
    }

    private func flipCard(front: String, back: String, revealed: Bool) -> some View {
        VStack {
            Spacer()
            Text(revealed ? back : front)
                .font(.title2.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(24)
            Spacer()
            Text(revealed ? "answer" : "tap to reveal")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, minHeight: 340)
        .background(revealed ? Color(.secondarySystemBackground) : Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color(.separator)))
        .contentShape(Rectangle())
        .onTapGesture { session.flip() }
    }

    private func mcCard(question: String, choices: [Choice], isCurrent: Bool) -> some View {
        VStack(spacing: 16) {
            Text(question)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            ForEach(choices) { choice in
                choiceRow(choice, isCurrent: isCurrent)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 340, alignment: .top)
    }

    private func choiceRow(_ choice: Choice, isCurrent: Bool) -> some View {
        let state = choiceState(for: choice, isCurrent: isCurrent)
        return Button {
            if picked == nil {
                picked = choice
                session.record(choice.isCorrect)
            }
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

    /// Grade a flip card once its answer is showing.
    private var gradeBar: some View {
        HStack(spacing: 12) {
            Button { session.record(false); session.next() } label: {
                Label("Missed", systemImage: "xmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            Button { session.record(true); session.next() } label: {
                Label("Got it", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .controlSize(.large)
    }

    private var completion: some View {
        let missed = session.missedCards
        return VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(session.isEmpty ? "No cards to study." : "Deck complete.")
                .font(.title2.weight(.semibold))
            if !session.isEmpty {
                Text("\(session.correctCount) / \(session.total) correct")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            if !missed.isEmpty {
                Button { session = StudySession(cards: missed); picked = nil } label: {
                    Label("Review \(missed.count) missed", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            if !session.isEmpty {
                Button("Study Again") { restart() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    /// One tap per reason; re-flagging a card just changes its reason.
    @ViewBuilder private var flagOptions: some View {
        if let card = session.current {
            ForEach(FlagReason.allCases) { reason in
                Button(reason.label) { flags.flag(card, as: reason) }
            }
            if flags.reason(for: card) != nil {
                Button("Unflag", role: .destructive) { flags.unflag(card) }
            }
        }
    }

    // MARK: - Helpers

    /// Reshuffle, clearing the current card's answered state along with it.
    private func restart() {
        session.restart()
        picked = nil
    }

    /// True when the current card is shown as a reveal card rather than pickable options.
    private var currentIsReveal: Bool {
        guard let content = session.current?.content else { return false }
        if case .flip = content { return true }
        return mode == .flashcards
    }

    /// Visual state of an MC option once the user has answered.
    private struct ChoiceStyle {
        var background: Color
        var border: Color
        var foreground: Color
        var tint: Color
        var icon: String?
    }

    private func choiceState(for choice: Choice, isCurrent: Bool) -> ChoiceStyle {
        guard isCurrent, let picked else {
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
