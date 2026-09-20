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

/// A playing card with two faces that turns over when tapped.
///
/// The flip is driven by one number so the card can do more than rotate on the way round:
/// it lunges towards you at the halfway point and settles back, which is what stops a
/// 3D rotation from reading as a page turning.
private struct FlipCard: View {
    let card: Card
    let isFlipped: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // The caller animates `isFlipped`; `Flipper` is animatable on this number, so
            // it still gets every value in between.
            Flipper(progress: isFlipped ? 1 : 0) {
                face(card.prompt, index: "Q", tint: Brand.chips, hint: "Tap to reveal")
            } back: {
                face(card.answer, index: "A", tint: Brand.gold, hint: "Answer")
            }
        }
        .buttonStyle(.plain)
        .breathing(isFlipped ? 0.6 : 1, period: 3.1)
        .accessibilityElement()
        .accessibilityLabel(isFlipped ? card.answer : card.prompt)
        .accessibilityHint("Tap to turn the card over")
    }

    /// Cream stock, black edge, an inner frame line and a rank in two corners — the things
    /// that make a rectangle read as a playing card rather than a panel.
    private func face(_ text: String, index: String, tint: Color, hint: String) -> some View {
        ZStack {
            // The shadow belongs to the stock, not to what's printed on it — put it on the
            // whole stack and the card's own text gets a blurry halo.
            RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                .fill(Brand.cardFace)
                .shadow(color: .black.opacity(0.5), radius: 16, y: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.cardRadius - 6, style: .continuous)
                        .strokeBorder(tint.opacity(0.45), lineWidth: 2)
                        .padding(9))
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                        .strokeBorder(Brand.outline, lineWidth: 3))

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

            // The rank, in opposite corners, the second one upside down.
            VStack {
                HStack {
                    rank(index, tint: tint)
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    rank(index, tint: tint).rotationEffect(.degrees(180))
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rank(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.pixel(28))
            .foregroundStyle(tint)
    }
}

/// Turns one view into another around the vertical axis. `progress` runs 0 → 1; the body is
/// re-evaluated at every interpolated value, which is what lets the lunge track the rotation.
private struct Flipper<Front: View, Back: View>: View, Animatable {
    var progress: Double
    @ViewBuilder var front: Front
    @ViewBuilder var back: Back

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        // Peaks at the halfway point, where the card is edge-on and nothing else is visible.
        let lunge = sin(min(max(progress, 0), 1) * .pi)
        let showingBack = progress > 0.5

        ZStack {
            front.opacity(showingBack ? 0 : 1)
            back
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(showingBack ? 1 : 0)
        }
        .rotation3DEffect(.degrees(progress * 180), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .scaleEffect(1 + 0.09 * lunge)
        .offset(y: -14 * lunge)
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
