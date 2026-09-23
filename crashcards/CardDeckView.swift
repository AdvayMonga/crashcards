import SwiftUI
import UIKit

/// Flashcards: a stack of cards on the table. Swipe the top one away for the next, tap to
/// flip it over.
///
/// No grading and no buttons — this mode is for going through a deck, not scoring yourself.
/// Quiz mode is where answers are judged.
struct CardDeckView: View {
    @Environment(FlagStore.self) private var flags
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    let onClose: () -> Void

    /// Shuffled once, on entry. The library re-scans on every foreground, so holding the
    /// cards the parent hands us would swap the deck out from under a session in progress.
    @State private var deck: [Card]
    /// How far into the deck we are. Everything before this has been thrown.
    @State private var position = 0
    @State private var flagging = false
    /// Which cards are face-up, by card identity rather than by slot, so a shuffle can't
    /// hand you a card that is already turned over.
    @State private var flipped: Set<Card.ID> = []
    /// Where the finger has dragged the top card. Zero whenever nothing is being held.
    @State private var held: CGSize = .zero
    /// The prompt waiting for you to say which chatbot should answer it.
    @State private var explaining: ExplainRequest?

    /// A playing card's proportions, the margin it keeps from the screen edge, and how far
    /// each card behind the top one is offset — which is all you ever see of them.
    private static let aspect: CGFloat = 0.72
    private static let margin: CGFloat = 26
    private static let step: CGFloat = 13
    /// How far the top card travels before letting go throws it rather than returns it.
    private static let throwDistance: CGFloat = 96

    init(cards: [Card], onClose: @escaping () -> Void) {
        _deck = State(initialValue: cards.shuffled())
        self.onClose = onClose
    }

    private var currentCard: Card? {
        guard deck.indices.contains(position) else { return nil }
        return deck[position]
    }

    /// The top card and the two behind it, nearest last so the ZStack puts it on top.
    private var visible: [(depth: Int, card: Card)] {
        (position..<min(position + 3, deck.count))
            .map { (depth: $0 - position, card: deck[$0]) }
            .reversed()
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
            } else if position >= deck.count {
                DeckEnd(count: deck.count, onShuffle: shuffle, onDone: onClose)
                    .padding(.horizontal, 26)
                    .transition(.dealIn)
            } else {
                stack
            }

            if flagging {
                CrashDialog(title: "Flag this card",
                            message: currentCard?.prompt,
                            onCancel: { flagging = false }) {
                    FlagOptions(card: currentCard) { flagging = false }
                }
                .zIndex(2)
            }
        }
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) { navigator }
        .screenLayer(item: $explaining) { request in
            AIPickerView(prompt: request.prompt) { explaining = nil }
        }
        .animation(Motion.pop, value: flagging)
    }

    // MARK: - The stack

    private var stack: some View {
        GeometryReader { geometry in
            let room = geometry.size
            let width = min(room.width - Self.margin * 2, (room.height - 40) * Self.aspect)

            ZStack {
                ForEach(visible, id: \.card.id) { entry in
                    let depth = CGFloat(entry.depth)
                    let top = entry.depth == 0

                    FlipCard(card: entry.card, isFlipped: flipped.contains(entry.card.id))
                        .frame(width: width, height: width / Self.aspect)
                        // The cards behind sit down and to the right, so all that shows of
                        // them is an edge. They are still whole cards, so the one that comes
                        // up next is already right rather than popping into place.
                        .scaleEffect(top ? 1 : 1 - depth * 0.035, anchor: .top)
                        .offset(x: top ? 0 : depth * Self.step,
                                y: top ? 0 : depth * Self.step)
                        .rotationEffect(.degrees(top ? 0 : Double(depth) * 1.6), anchor: .top)
                        .modifier(HeldCard(offset: top ? held : .zero))
                        .breathing(top && !flipped.contains(entry.card.id) ? 0.8 : 0, period: 3.4)
                        .zIndex(Double(-entry.depth))
                        .allowsHitTesting(top)
                        .accessibilityHidden(!top)
                        .onTapGesture { toggleFlip(entry.card) }
                        .gesture(top ? swipe : nil)
                }
            }
            .frame(width: room.width, height: room.height)
            .animation(Motion.settle, value: position)
        }
    }

    /// Drag the top card and it follows; let go past `throwDistance`, or with enough flick
    /// behind it, and it carries on off the table instead of settling back.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { held = $0.translation }
            .onEnded { value in
                let thrown = abs(value.translation.width) > Self.throwDistance
                    || abs(value.predictedEndTranslation.width) > 240
                if thrown {
                    throwAway(toward: value.translation.width < 0 ? -1 : 1)
                } else {
                    withAnimation(Motion.pop(reduceMotion)) { held = .zero }
                }
            }
    }

    private func throwAway(toward direction: CGFloat) {
        Haptics.knock()
        guard !reduceMotion else {
            advance()
            return
        }
        withAnimation(.easeOut(duration: 0.24)) {
            held = CGSize(width: direction * 900, height: held.height - 60)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.24))
            advance()
        }
    }

    /// Both halves in one update: the thrown card leaves the stack and the hand resets, so
    /// the card coming up is never briefly drawn where the last one was flung.
    private func advance() {
        position += 1
        held = .zero
    }

    /// Bring the last card back.
    ///
    /// It slides in from the side rather than appearing, so going back reads as the reverse
    /// of a throw. The card is placed off the table without animation first, then animated
    /// home on the next turn of the run loop — set both in one tick and SwiftUI coalesces
    /// them, so the card never renders off-table and there is nothing to animate from.
    private func goBack() {
        guard position > 0 else { return }
        Haptics.knock()

        guard !reduceMotion else {
            position -= 1
            held = .zero
            return
        }

        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            position -= 1
            held = CGSize(width: -560, height: -50)
        }
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.28)) { held = .zero }
        }
    }

    /// Back and forward, for going through a deck without throwing cards around — and the
    /// only way back to a card already passed, which swiping alone can't do.
    private var navigator: some View {
        HStack(spacing: 14) {
            HeaderChip(glyph: .chevronLeft, name: "Previous card",
                       tint: canGoBack ? Brand.ink : Brand.inkFaint) { goBack() }
                .disabled(!canGoBack)

            HeaderChip(glyph: .chevron, name: "Next card",
                       tint: canGoForward ? Brand.ink : Brand.inkFaint) { throwAway(toward: -1) }
                .disabled(!canGoForward)
        }
        .padding(.bottom, 6)
        .animation(Motion.pop, value: position)
    }

    private var canGoBack: Bool { position > 0 && !deck.isEmpty }
    /// False on the end screen: there is no card there to throw.
    private var canGoForward: Bool { position < deck.count }

    private func shuffle() {
        Haptics.thud()
        deck.shuffle()
        flipped.removeAll()
        held = .zero
        position = 0
    }

    private func explainCurrent() {
        guard let card = currentCard else { return }
        Haptics.tap()
        explaining = ExplainRequest(prompt: ExplainPrompt.text(for: [card]))
    }

    private func toggleFlip(_ card: Card) {
        Haptics.knock()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.22)
                                   : .spring(response: 0.46, dampingFraction: 0.68)) {
            if flipped.contains(card.id) { flipped.remove(card.id) } else { flipped.insert(card.id) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HeaderChip(glyph: .close, name: "Close") { onClose() }

            ProgressTrack(value: min(position + 1, deck.count), total: deck.count,
                          label: "Card \(min(position + 1, deck.count)) of \(deck.count)")

            // Only once the answer is showing: explaining a card you haven't attempted
            // hands you the answer instead of teaching you anything.
            let turned = currentCard.map { flipped.contains($0.id) } ?? false
            HeaderChip(glyph: .question, name: "Explain with AI",
                       tint: turned ? Brand.chips : Brand.inkFaint) { explainCurrent() }
                .disabled(!turned)

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

/// A card being dragged: it follows the finger and leans the way it is going, pivoting about
/// its bottom edge the way a card pulled off a stack actually does.
private struct HeldCard: ViewModifier {
    let offset: CGSize

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(Double(offset.width / 22)), anchor: .bottom)
            .offset(offset)
    }
}

/// A playing card with two faces. Stock, edge and corner rank come from `CardFace` and
/// `CardFlipper` — the same ones the quiz and the unlock gate use, so a card is one object
/// wherever you meet it.
private struct FlipCard: View {
    let card: Card
    let isFlipped: Bool

    var body: some View {
        CardFlipper(turn: isFlipped ? 1 : 0) { index in
            if index == 0 {
                face(card.prompt, rank: "Q", tint: Brand.chips, hint: "Tap to reveal")
            } else {
                face(card.answer, rank: "A", tint: Brand.gold, hint: "Answer")
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isFlipped ? card.answer : card.prompt)
        .accessibilityHint("Tap to turn the card over, swipe for the next one")
    }

    private func face(_ text: String, rank: String, tint: Color, hint: String) -> some View {
        CardFace(tint: tint) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(text)
                    .font(.brandCard)
                    .foregroundStyle(Brand.cardInk)
                    .multilineTextAlignment(.center)
                    // The card is a fixed size, so past a point text has to give: it
                    // shrinks first and truncates rather than spilling over the edge.
                    .lineLimit(12)
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
