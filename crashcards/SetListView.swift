import SwiftUI

/// Study tab: pick which sets to study, then start a shuffled session in one of the modes.
///
/// Selected sets rise off the table the way a held card does, which is the whole selection
/// affordance — there's no checkbox doing the work on its own.
struct SetListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(FlagStore.self) private var flags
    @State private var selected: Set<String> = Prefs.selectedSetIDs
    @State private var studyMode: StudyMode?
    @State private var studyingVoice = false
    @State private var importingFolder = false
    @State private var importingSet = false
    @State private var showingProblems = false

    private var selectedSets: [FlashcardSet] {
        library.sets.filter { selected.contains($0.id) }
    }
    private var allSelected: Bool {
        !library.sets.isEmpty && selected.isSuperset(of: library.sets.map(\.id))
    }
    private var hasProblems: Bool {
        library.issueCount > 0 || flags.loadError != nil
    }

    var body: some View {
        content
            .safeAreaInset(edge: .top) { header }
            .safeAreaInset(edge: .bottom) { studyBar }
            .screenLayer(item: $studyMode) { mode in
                destination(for: mode)
            }
            .screenLayer(isPresented: $studyingVoice) {
                studyScreen(.voice) {
                    VoiceStudyView(session: StudySession(cards: $0)) { studyingVoice = false }
                }
            }
            .screenLayer(isPresented: $showingProblems) {
                FileProblemsView { showingProblems = false }
                    .environment(library)
                    .environment(flags)
            }
            .screenLayer(isPresented: $importingSet) {
                ImportSetView(onClose: { importingSet = false }) { library.reload() }
                    .environment(library)
            }
            .onChange(of: library.sets.map(\.id)) { _, ids in
                selected = selected.intersection(ids)   // forget sets that no longer exist
            }
            .onChange(of: selected) { _, new in
                Prefs.selectedSetIDs = new
            }
            .fileImporter(isPresented: $importingFolder, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url): library.addFolder(url)
                case .failure(let error): library.importFailed(error)
                }
            }
    }

    // MARK: - Study screens

    @ViewBuilder
    private func destination(for mode: StudyMode) -> some View {
        studyScreen(mode) { cards in
            switch mode {
            case .flashcards:
                CardDeckView(cards: cards) { studyMode = nil }
            case .quiz:
                QuizView(session: StudySession(cards: cards)) { studyMode = nil }
            case .voice:
                VoiceStudyView(session: StudySession(cards: cards)) { studyMode = nil }
            }
        }
    }

    /// A mode is only entered with cards it can actually present; otherwise it explains why.
    @ViewBuilder
    private func studyScreen<V: View>(_ mode: StudyMode,
                                      @ViewBuilder study: ([Card]) -> V) -> some View {
        if let reason = mode.unavailableReason(for: selectedSets) {
            ModeUnavailableView(mode: mode, reason: reason) {
                studyMode = nil
                studyingVoice = false
            }
        } else {
            study(mode.usableCards(in: selectedSets))
        }
    }

    // MARK: - The table

    @ViewBuilder private var content: some View {
        if let error = library.loadError {
            EmptyState(glyph: .warning,
                       title: "Couldn't read folder",
                       message: error,
                       tint: Brand.orange)
        } else if library.sets.isEmpty {
            EmptyState(glyph: .cards,
                       title: "No cards yet",
                       message: hasProblems
                            ? "Nothing here parsed into cards. See what's wrong with your files."
                            : "Add a folder of set files, or keep your sets inside the app.") {
                Button("New set") { importingSet = true }
                    .buttonStyle(.solid)
                Button("Add a folder") { importingFolder = true }
                    .buttonStyle(.soft)
                if hasProblems {
                    Button("View file problems") { showingProblems = true }
                        .buttonStyle(CrashButton(kind: .ghost, tint: Brand.orange))
                }
            }
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    if hasProblems { problemBanner }
                    ForEach(library.sets) { set in
                        Button { toggle(set.id) } label: { row(for: set) }
                            .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var problemBanner: some View {
        Button { showingProblems = true } label: {
            HStack(spacing: 12) {
                PixelIcon(glyph: .warning, size: 20, color: Brand.outline)
                Text(problemSummary)
                    .font(.brandLabel)
                    .foregroundStyle(Brand.outline)
                Spacer(minLength: 0)
                PixelIcon(glyph: .chevron, size: 14, color: Brand.outline.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .slab(Brand.orange, highlight: 0.22)
        }
        .buttonStyle(.pressable)
    }

    private var problemSummary: String {
        let count = library.issueCount
        if count == 0 { return "\(FlagStore.filename) couldn't be read" }
        return count == 1 ? "1 file problem found" : "\(count) file problems found"
    }

    /// A set, as a card lying on the table. Picking it up lifts it and lights its edge gold.
    private func row(for set: FlashcardSet) -> some View {
        let isOn = selected.contains(set.id)
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
                Text(cardSummary(for: set))
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
        .accessibilityHint(isOn ? "Tap to deselect" : "Tap to select")
    }

    /// Card count, split by kind so it's obvious which sets a quiz can use.
    private func cardSummary(for set: FlashcardSet) -> String {
        let total = set.cards.count == 1 ? "1 card" : "\(set.cards.count) cards"
        let questions = set.multipleChoiceCount
        guard questions > 0 else { return "\(total) · no questions" }
        return "\(total) · \(questions) question\(questions == 1 ? "" : "s")"
    }

    @ViewBuilder private var studyBar: some View {
        if !library.sets.isEmpty {
            VStack(spacing: 8) {
                if selectedSets.isEmpty {
                    Text("Pick a set to start")
                        .font(.brandCaption)
                        .foregroundStyle(Brand.inkFaint)
                        .transition(.opacity)
                }

                HStack(spacing: 12) {
                    Button("Flashcards") { start(.flashcards) }
                        .buttonStyle(.solid(Brand.chips))
                    Button("Quiz") { start(.quiz) }
                        .buttonStyle(.solid(Brand.purple))
                }
                .disabled(selectedSets.isEmpty)
                .opacity(selectedSets.isEmpty ? 0.45 : 1)
                .saturation(selectedSets.isEmpty ? 0.3 : 1)
            }
            .animation(Motion.settle, value: selectedSets.isEmpty)
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, Brand.ledge)
        }
    }

    private var header: some View {
        ScreenHeader(title: "Sets") {
            if !library.sets.isEmpty {
                Button(allSelected ? "Clear" : "All") { toggleAll() }
                    .buttonStyle(CrashButton(kind: .ghost, tint: Brand.inkDim, fullWidth: false))
                HeaderChip(glyph: .mic, name: "Voice study", tint: Brand.chips) {
                    studyingVoice = true
                }
                .disabled(selectedSets.isEmpty)
                .opacity(selectedSets.isEmpty ? 0.4 : 1)
            }
            HeaderChip(glyph: .plus, name: "New set", tint: Brand.gold) {
                importingSet = true
            }
        }
    }

    private func start(_ mode: StudyMode) {
        Haptics.thud()
        studyMode = mode
    }

    private func toggle(_ id: String) {
        Haptics.select()
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
    private func toggleAll() {
        Haptics.knock()
        selected = allSelected ? [] : Set(library.sets.map(\.id))
    }
}
