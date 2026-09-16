import SwiftUI

/// Flashcards: a vertical feed of cards. Scroll up for the next one, tap to flip.
///
/// No grading and no buttons — this mode is for going through a deck, not scoring yourself.
/// Quiz mode is where answers are judged.
struct CardDeckView: View {
    let cards: [Card]
    @Environment(FlagStore.self) private var flags
    @Environment(\.dismiss) private var dismiss

    @State private var order: [Int] = []
    @State private var visible: Int?
    @State private var flagging = false

    private var position: Int { visible ?? 0 }
    private var currentCard: Card? {
        guard order.indices.contains(position) else { return nil }
        return cards[order[position]]
    }

    var body: some View {
        ZStack {
            Brand.canvas.ignoresSafeArea()

            if cards.isEmpty {
                EmptyDeck(dismiss: dismiss)
            } else {
                feed
            }
        }
        .safeAreaInset(edge: .top) { header }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)   // studying is full-screen
        .onAppear { if order.isEmpty { order = Array(cards.indices).shuffled() } }
        .confirmationDialog("Flag this card", isPresented: $flagging, titleVisibility: .visible) {
            FlagOptions(card: currentCard)
        } message: {
            if let currentCard { Text(currentCard.prompt) }
        }
    }

    /// One card per screenful, snapping like a reel.
    private var feed: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(order.enumerated()), id: \.offset) { index, cardIndex in
                    FlipCard(card: cards[cardIndex])
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .containerRelativeFrame(.vertical)
                        .id(index)
                }
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
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.brand(15, .bold))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(Circle().fill(Brand.surface))
            }
            .buttonStyle(.plain)

            ProgressTrack(value: position + 1, total: order.count)

            Button { flagging = true } label: {
                Image(systemName: flags.reason(for: currentCard) == nil ? "flag" : "flag.fill")
                    .font(.brand(15, .bold))
                    .foregroundStyle(flags.reason(for: currentCard) == nil ? .secondary : Brand.accent)
                    .padding(10)
                    .background(Circle().fill(Brand.surface))
            }
            .buttonStyle(.plain)
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
    @State private var flipped = false

    var body: some View {
        ZStack {
            face(card.prompt, muted: false)
                .opacity(flipped ? 0 : 1)
            face(card.answer, muted: true)
                .rotation3DEffect(.degrees(180), axis: (x: 1, y: 0, z: 0))
                .opacity(flipped ? 1 : 0)
        }
        .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: flipped)
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
