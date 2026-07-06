import SwiftUI

/// Classic study: one card at a time, tap to flip, next/prev, shuffle, completion.
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { session.restart() } label: {
                    Image(systemName: "shuffle")
                }
                .disabled(session.isEmpty)
            }
        }
    }

    private var cardView: some View {
        Button {
            session.flip()
        } label: {
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
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button("Prev") { session.prev() }
                .buttonStyle(.bordered)
                .disabled(session.position == 0)
            Button(session.isFlipped ? "Hide" : "Flip") { session.flip() }
                .buttonStyle(.borderedProminent)
            Button("Next") { session.next() }
                .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity)
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
}
