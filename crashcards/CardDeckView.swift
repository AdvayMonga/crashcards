import SwiftUI

/// Flashcards: a vertical feed of cards. Scroll up for the next one, tap to flip.
///
/// No grading and no buttons — this mode is for going through a deck, not scoring yourself.
/// Quiz mode is where answers are judged.
struct CardDeckView: View {
    @Environment(FlagStore.self) private var flags
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onClose: () -> Void

    /// Shuffled once, on entry. The library re-scans on every foreground, so holding the
    /// cards the parent hands us would swap the deck out from under a session in progress.
    @State private var deck: [Card]
    @State private var visible: Int?
    @State private var flagging = false
    /// Which cards are face-up, by card identity. Held here rather than inside `FlipCard`
    /// because the feed identifies rows by position: after a shuffle the view in a given
    /// slot is reused, and per-view state would land on a different card.
    @State private var flipped: Set<Card.ID> = []

    init(cards: [Card], onClose: @escaping () -> Void) {
        _deck = State(initialValue: cards.shuffled())
        self.onClose = onClose
    }

    private var position: Int { visible ?? 0 }
    private var currentCard: Card? {
        guard deck.indices.contains(position) else { return nil }
        return deck[position]
    }

    var body: some View {
        ZStack {
            TableBackground()

            if deck.isEmpty {
                EmptyState(glyph: .cards,
                           title: "Nothing to study",
                           message: "The sets you picked have no cards in them yet.") {
                    Button("Back to sets") { onClose() }
                        .buttonStyle(CrashButton(fullWidth: false))
                }
            } else {
                feed
            }

            if flagging {
                CrashDialog(title: "Flag this card",
                            message: currentCard?.prompt,
                            onCancel: { flagging = false }) {
                    FlagOptions(card: currentCard) { flagging = false }
                }
                .zIndex(1)
            }
        }
        .safeAreaInset(edge: .top) { header }
        .animation(Motion.pop, value: flagging)
    }

    private func shuffle() {
        Haptics.thud()
        deck.shuffle()
        flipped.removeAll()
        visible = 0
    }

    private func toggleFlip(_ card: Card) {
        Haptics.knock()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.22)
                                   : .spring(response: 0.46, dampingFraction: 0.68)) {
            if flipped.contains(card.id) { flipped.remove(card.id) } else { flipped.insert(card.id) }
        }
    }

    /// One card per screenful, snapping like a reel. Scrolling is the one place a swipe
    /// belongs, so this is a real paging scroll rather than a styled transition.
    private var feed: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(deck.enumerated()), id: \.offset) { index, card in
                    // Held to a playing card's proportions rather than filling the page, so
                    // there is always table around it.
                    FlipCard(card: card, isFlipped: flipped.contains(card.id)) {
                        toggleFlip(card)
                    }
                        .aspectRatio(0.72, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .containerRelativeFrame(.vertical)
                        .id(index)
                }
                DeckEnd(count: deck.count, onShuffle: shuffle, onDone: onClose)
                    .padding(.horizontal, 20)
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
        HStack(spacing: 12) {
            HeaderChip(glyph: .close, name: "Close") { onClose() }

            ProgressTrack(value: min(position + 1, deck.count), total: deck.count,
                          label: "Card \(min(position + 1, deck.count)) of \(deck.count)")

            let flagged = flags.reason(for: currentCard) != nil
            HeaderChip(glyph: flagged ? .flagFilled : .flag,
                       name: flagged ? "Flagged" : "Flag this card",
                       tint: flagged ? Brand.gold : Brand.inkDim) { flagging = true }
                .disabled(currentCard == nil || flags.isLocked)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }
}

/// A playing card with two faces that turns over when tapped. Stock, edge and corner rank
/// come from `CardFace` and `CardFlipper` — the same ones the quiz and the unlock gate use,
/// so a card is one object wherever you meet it.
private struct FlipCard: View {
    let card: Card
    let isFlipped: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // The caller animates `isFlipped`; `CardFlipper` is animatable on this number,
            // so it still gets every value in between.
            CardFlipper(turn: isFlipped ? 1 : 0) { index in
                if index == 0 {
                    face(card.prompt, rank: "Q", tint: Brand.chips, hint: "Tap to reveal")
                } else {
                    face(card.answer, rank: "A", tint: Brand.gold, hint: "Answer")
                }
            }
        }
        .buttonStyle(.plain)
        .breathing(isFlipped ? 0.6 : 1, period: 3.1)
        .accessibilityElement()
        .accessibilityLabel(isFlipped ? card.answer : card.prompt)
        .accessibilityHint("Tap to turn the card over")
    }

    private func face(_ text: String, rank: String, tint: Color, hint: String) -> some View {
        CardFace(tint: tint) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(text)
                    .font(.brandCard)
                    .foregroundStyle(Brand.cardInk)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, 30)
                Spacer(minLength: 0)
                Text(hint)
                    .font(.brandCaption)
                    .foregroundStyle(Brand.cardInk.opacity(0.45))
                    .padding(.bottom, 24)
            }
            CardIndex(text: rank, tint: tint)
        }
    }
}

/// The page after the last card — the feed needs an ending, and shuffling again was the
/// one thing the old screen's toolbar did that scrolling doesn't replace.
private struct DeckEnd: View {
    let count: Int
    let onShuffle: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            PixelIcon(glyph: .cards, size: 54, color: Brand.gold)
                .padding(22)
                .slab(Brand.surface, radius: Brand.cardRadius)
                .breathing(1.4, period: 3.4)
            Text("That's the deck")
                .font(.brandTitle)
                .foregroundStyle(Brand.ink)
            Text(count == 1 ? "1 card" : "\(count) cards")
                .font(.brandLabel)
                .foregroundStyle(Brand.inkDim)
            Spacer()
            Button("Shuffle again") { onShuffle() }
                .buttonStyle(.solid)
            Button("Done") { onDone() }
                .buttonStyle(.soft)
        }
        .padding(.bottom, 36)
    }
}

/// Shared by both study modes: one tap per reason, re-flagging changes the reason.
struct FlagOptions: View {
    let card: Card?
    let onDone: () -> Void
    @Environment(FlagStore.self) private var flags

    var body: some View {
        if let card {
            VStack(spacing: 10) {
                ForEach(FlagReason.allCases) { reason in
                    Button(reason.label) {
                        Haptics.tap()
                        flags.flag(card, as: reason)
                        onDone()
                    }
                    .buttonStyle(.soft(Brand.gold))
                }
                if flags.reason(for: card) != nil {
                    Button("Unflag") {
                        Haptics.tap()
                        flags.unflag(card)
                        onDone()
                    }
                    .buttonStyle(.soft(Brand.mult))
                }
            }
        }
    }
}
