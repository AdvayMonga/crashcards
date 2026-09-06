import SwiftUI

/// Shown instead of a study screen when the selected sets can't supply what the mode needs —
/// e.g. Quiz mode on sets that only contain `::` flip cards.
///
/// Says what's missing and, when the fix is a file edit, the exact format to write.
struct ModeUnavailableView: View {
    let mode: StudyMode
    let reason: ModeUnavailable
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: reason.symbol)
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(reason.title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(reason.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let expected = reason.expected {
                Text(expected)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Spacer()
            Button("Back to Sets") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(24)
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
