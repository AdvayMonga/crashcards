import SwiftUI

/// Picks which sets the unlock gate asks from.
///
/// Separate from the Study tab's selection on purpose: the set you sit down to learn and
/// the set that stands between you and your apps are different choices. Picking nothing
/// means every set, so the gate keeps working for someone who never opens this screen.
struct GateSetsView: View {
    @Environment(LibraryStore.self) private var library
    let onClose: () -> Void

    /// Held locally and written on every change, the way the Study tab does it — there is
    /// no Save button to press, so there is nothing to lose by leaving.
    @State private var picked: Set<String> = Prefs.gateSetIDs

    /// What the gate would actually ask from, given what's ticked. Empty ticks mean all.
    private var effective: [FlashcardSet] {
        let chosen = library.sets.filter { picked.contains($0.id) }
        return chosen.isEmpty ? library.sets : chosen
    }

    private var questionCount: Int {
        UnlockView.answerable(in: effective.flatMap(\.cards)).count
    }

    var body: some View {
        ZStack {
            TableBackground()

            if library.sets.isEmpty {
                EmptyState(glyph: .cards,
                           title: "No sets yet",
                           message: "Add a set on the Study tab and it'll show up here.") {
                    Button("Back") { onClose() }
                        .buttonStyle(CrashButton(fullWidth: false))
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        summary
                        VStack(spacing: 12) {
                            ForEach(library.sets) { set in
                                Button { toggle(set) } label: { row(for: set) }
                                    .buttonStyle(.pressable)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
                .contentMargins(.top, 4, for: .scrollContent)
            }
        }
        .safeAreaInset(edge: .top) { header }
        .onTable()
    }

    private var header: some View {
        ScreenHeader(title: "Question sets") {
            HeaderChip(glyph: .close, name: "Done") { onClose() }
        }
    }

    /// Says what the choice actually buys, because "3 of 7 sets" doesn't tell you whether
    /// the gate can ask anything at all.
    private var summary: some View {
        Panel(title: picked.isEmpty ? "Every set" : "\(picked.count) of \(library.sets.count) sets") {
            PanelRow(first: true) {
                StatRow(label: "Questions the gate can ask", value: "\(questionCount)")
            }
            if questionCount == 0 {
                PanelRow {
                    Text("These sets have nothing the gate can ask. It needs multiple-choice questions, or two cards with different answers.")
                        .font(.reading(14))
                        .foregroundStyle(Brand.mult)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !picked.isEmpty {
                PanelAction(title: "Use every set") { useAll() }
            }
        }
    }

    private func row(for set: FlashcardSet) -> some View {
        // Nothing ticked means every set is in play, so every row is drawn lit rather than
        // leaving the screen looking like the gate has nothing to ask.
        let isOn = picked.isEmpty || picked.contains(set.id)
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn ? Brand.gold : Brand.surfaceLedge)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Brand.outline, lineWidth: 2))
                    .frame(width: 26, height: 26)
                if isOn {
                    PixelIcon(glyph: .check, size: 18, color: Brand.outline)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(set.title)
                    .font(.brandLabel)
                    .foregroundStyle(isOn ? Brand.ink : Brand.ink.opacity(0.85))
                Text(summary(for: set))
                    .font(.brandCaption)
                    .foregroundStyle(isOn ? Brand.gold : Brand.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 16)
        .slab(isOn ? Brand.surfaceHigh : Brand.surface,
              lift: isOn ? Brand.ledge + 3 : Brand.ledge,
              highlight: isOn ? 0.16 : 0.08)
        .overlay(
            RoundedRectangle(cornerRadius: Brand.slabRadius, style: .continuous)
                .strokeBorder(Brand.gold, lineWidth: isOn ? 2.5 : 0)
                .padding(1.5))
        .offset(y: isOn ? -3 : 0)
        .animation(Motion.pop, value: isOn)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isOn ? "Tap to leave this set out of the gate" : "Tap to ask from this set")
    }

    /// How many of this set's cards the gate could actually put in front of you — which is
    /// not its card count: a set of flip cards sharing one answer has nothing to ask.
    private func summary(for set: FlashcardSet) -> String {
        let count = UnlockView.answerable(in: set.cards).count
        guard count > 0 else { return "nothing to ask" }
        return count == 1 ? "1 question" : "\(count) questions"
    }

    private func toggle(_ set: FlashcardSet) {
        Haptics.tap()
        withAnimation(Motion.pop) {
            // The first tap on an all-sets screen means "just this one", not "all but this
            // one" — every row is lit, so tapping one reads as choosing it.
            if picked.isEmpty {
                picked = [set.id]
            } else if picked.contains(set.id) {
                picked.remove(set.id)
            } else {
                picked.insert(set.id)
            }
        }
        Prefs.gateSetIDs = picked
    }

    private func useAll() {
        Haptics.knock()
        withAnimation(Motion.pop) { picked = [] }
        Prefs.gateSetIDs = picked
    }
}
