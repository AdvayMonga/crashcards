import SwiftUI

/// Classic study: one card at a time, tap to flip, swipe or arrows for prev/next, shuffle.
struct StudyView: View {
    @State var session: StudySession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            if session.isFinished {
                completion
            } else {
                Text(session.progressText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                cardView
                controls
            }
        }
        .padding()
        .navigationTitle("Classic")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)   // disable the edge swipe-back-to-home
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Label("Sets", systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { session.restart() } label: {
                    Image(systemName: "shuffle")
                }
                .disabled(session.isEmpty)
            }
        }
    }

    private var cardView: some View {
        VStack {
            Spacer()
            Text(session.isFlipped ? (session.current?.back ?? "") : (session.current?.front ?? ""))
                .font(.title2.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(24)
            Spacer()
            Text(session.isFlipped ? "answer" : "tap to reveal")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, minHeight: 340)
        .background(session.isFlipped ? Color(.secondarySystemBackground) : Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color(.separator)))
        .contentShape(Rectangle())
        .onTapGesture { session.flip() }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in handleSwipe(value.translation) }
        )
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { session.prev() } label: {
                Image(systemName: "chevron.left").font(.title3)
            }
            .buttonStyle(.bordered)
            .disabled(session.position == 0)

            Button(session.isFlipped ? "Hide" : "Flip") { session.flip() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

            Button { session.next() } label: {
                Image(systemName: "chevron.right").font(.title3)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private var completion: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(session.isEmpty ? "No cards to study." : "Deck complete.")
                .font(.title2.weight(.semibold))
            if !session.isEmpty {
                Button("Study Again") { session.restart() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    /// A decisive horizontal swipe moves cards: left = next, right = previous.
    private func handleSwipe(_ translation: CGSize) {
        guard abs(translation.width) > 50, abs(translation.width) > abs(translation.height) else { return }
        if translation.width < 0 { session.next() } else { session.prev() }
    }
}
