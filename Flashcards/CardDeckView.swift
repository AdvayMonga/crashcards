import SwiftUI

/// Flashcards: a vertical feed of cards. Scroll up for the next one, tap to flip.
///
/// No grading and no buttons — this mode is for going through a deck, not scoring yourself.
/// Quiz mode is where answers are judged.
struct CardDeckView: View {
    @Environment(FlagStore.self) private var flags
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    /// Shuffled once, on entry. The library re-scans on every foreground, so holding the
    /// cards the parent hands us would swap the deck out from under a session in progress.
    @State private var deck: [Card]
    @State private var visible: Int?
    @State private var flagging = false

    init(cards: [Card]) {
        _deck = State(initialValue: cards.shuffled())
    }

    private var position: Int { visible ?? 0 }
    private var currentCard: Card? {
        guard deck.indices.contains(position) else { return nil }
        return deck[position]
    }

    var body: some View {
        ZStack {
            Brand.canvas.ignoresSafeArea()

            if deck.isEmpty {
                EmptyDeck(dismiss: dismiss)
            } else {
                feed
            }
        }
        .safeAreaInset(edge: .top) { header }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)   // studying is full-screen
        .confirmationDialog("Flag this card", isPresented: $flagging, titleVisibility: .visible) {
            FlagOptions(card: currentCard)
        } message: {
            if let currentCard { Text(currentCard.prompt) }
        }
    }

    private func shuffle() {
        Haptics.knock()
        deck.shuffle()
        visible = 0
    }

    /// One card per screenful, snapping like a reel.
    private var feed: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(deck.enumerated()), id: \.offset) { index, card in
                    FlipCard(card: card, reduceMotion: reduceMotion)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .containerRelativeFrame(.vertical)
                        .id(index)
                }
                DeckEnd(count: deck.count, onShuffle: shuffle, onDone: { dismiss() })
                    .padding(.horizontal, 18)
                    .containerRelativeFrame(.vertical)
                    .id(deck.count)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $visible)
        .scrollIndicators(.hidden)
        .onChange(of: visible) { _, _ in Haptics.tap() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            HeaderChip(symbol: "xmark", name: "Close", tint: .secondary) { dismiss() }

            ProgressTrack(value: min(position + 1, deck.count), total: deck.count,
                          label: "Card \(min(position + 1, deck.count)) of \(deck.count)")

            let flagged = flags.reason(for: currentCard) != nil
            HeaderChip(symbol: flagged ? "flag.fill" : "flag",
                       name: flagged ? "Flagged" : "Flag this card",
                       tint: flagged ? Brand.accent : .secondary) { flagging = true }
                .disabled(currentCard == nil || flags.isLocked)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .background(Brand.canvas)
    }
}

/// A card with two faces that turns over when tapped.
private struct FlipCard: View {
    let card: Card
    let reduceMotion: Bool
    @State private var flipped = false

    var body: some View {
        ZStack {
            face(card.prompt, muted: false)
                .opacity(flipped ? 0 : 1)
            face(card.answer, muted: true)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 1, y: 0, z: 0))
                .opacity(flipped ? 1 : 0)
        }
        .rotation3DEffect(.degrees(flipped && !reduceMotion ? 180 : 0),
                          axis: (x: 1, y: 0, z: 0), perspective: 0.35)
        .animation(reduceMotion ? .easeInOut(duration: 0.2)
                                : .spring(response: 0.45, dampingFraction: 0.78),
                   value: flipped)
        .contentShape(Rectangle())
        .onTapGesture {
            flipped.toggle()
            Haptics.knock()
        }
        .accessibilityElement()
        .accessibilityLabel(flipped ? card.answer : card.prompt)
        .accessibilityHint("Tap to turn the card over")
    }

    private func face(_ text: String, muted: Bool) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Text(text)
                .font(.brandCard)
                .multilineTextAlignment(.center)
                .foregroundStyle(muted ? Brand.accent : Color.primary)
                .padding(.horizontal, 28)
            Spacer(minLength: 0)
            Text(muted ? "Answer" : "Tap to reveal")
                .font(.brandCaption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                .fill(Brand.surface)
                .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
        )
    }
}

/// The page after the last card — the feed needs an ending, and shuffling again was the
/// one thing the old screen's toolbar did that scrolling doesn't replace.
private struct DeckEnd: View {
    let count: Int
    let onShuffle: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("That's the deck")
                .font(.brandTitle)
            Text(count == 1 ? "1 card" : "\(count) cards")
                .font(.brandBody)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Shuffle again") { onShuffle() }
                .buttonStyle(.solid)
            Button("Done") { onDone() }
                .buttonStyle(.soft)
        }
        .padding(.bottom, 30)
    }
}

private struct EmptyDeck: View {
    let dismiss: DismissAction

    var body: some View {
        VStack(spacing: 20) {
            Text("Nothing to study")
                .font(.brandTitle)
            Text("The sets you picked have no cards in them yet.")
                .font(.brandBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Back to sets") { dismiss() }
                .buttonStyle(CrashButton(fullWidth: false))
        }
        .padding(32)
    }
}

/// A round header button. 44pt of target under a 38pt circle, and a name for VoiceOver.
struct HeaderChip: View {
    let symbol: String
    let name: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.brand(15, .bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Brand.surface))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }
}

/// Shared by both study modes: one tap per reason, re-flagging changes the reason.
struct FlagOptions: View {
    let card: Card?
    @Environment(FlagStore.self) private var flags

    var body: some View {
        if let card {
            ForEach(FlagReason.allCases) { reason in
                Button(reason.label) { flags.flag(card, as: reason) }
            }
            if flags.reason(for: card) != nil {
                Button("Unflag", role: .destructive) { flags.unflag(card) }
            }
        }
    }
}
