import SwiftUI

/// Study tab: pick which sets to study, then start a shuffled session in one of the modes.
struct SetListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(FlagStore.self) private var flags
    @State private var selected: Set<String> = Prefs.selectedSetIDs
    @State private var studyMode: StudyMode?
    @State private var studyingVoice = false
    @State private var importingFolder = false
    @State private var importingSet = false

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
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top) { header }
                .safeAreaInset(edge: .bottom) { studyBar }
                .navigationDestination(item: $studyMode) { mode in
                    destination(for: mode) { cards in
                        switch mode {
                        case .flashcards: CardDeckView(cards: cards)
                        case .quiz: QuizView(session: StudySession(cards: cards))
                        case .voice: VoiceStudyView(session: StudySession(cards: cards))
                        }
                    }
                }
                .navigationDestination(isPresented: $studyingVoice) {
                    destination(for: .voice) { VoiceStudyView(session: StudySession(cards: $0)) }
                }
        }
        .onChange(of: library.sets.map(\.id)) { _, ids in
            selected = selected.intersection(ids)   // forget sets that no longer exist
        }
        .onChange(of: selected) { _, new in
            Prefs.selectedSetIDs = new
        }
        .sheet(isPresented: $importingSet) {
            ImportSetView { library.reload() }
                .environment(library)
        }
        .fileImporter(isPresented: $importingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): library.addFolder(url)
            case .failure(let error): library.importFailed(error)
            }
        }
    }

    /// A mode is only entered with cards it can actually present; otherwise it explains why.
    @ViewBuilder
    private func destination<V: View>(for mode: StudyMode,
                                      @ViewBuilder study: ([Card]) -> V) -> some View {
        if let reason = mode.unavailableReason(for: selectedSets) {
            ModeUnavailableView(mode: mode, reason: reason)
        } else {
            study(mode.usableCards(in: selectedSets))
        }
    }

    @ViewBuilder private var content: some View {
        if let error = library.loadError {
            ContentUnavailableView {
                Label("Couldn't read folder", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else if library.sets.isEmpty {
            ContentUnavailableView {
                Label("No cards yet", systemImage: "tray")
            } description: {
                Text(hasProblems
                     ? "Nothing here parsed into cards. See what's wrong with your files."
                     : "Add a folder of set files, or keep your sets inside the app.")
            } actions: {
                Button("New Set") { importingSet = true }
                    .buttonStyle(.borderedProminent)
                Button("Add a Folder") { importingFolder = true }
                if hasProblems {
                    NavigationLink("View File Problems") {
                        FileProblemsView().environment(library).environment(flags)
                    }
                }
            }
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    if hasProblems {
                        NavigationLink {
                            FileProblemsView().environment(library).environment(flags)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(problemSummary).font(.brandLabel)
                                Spacer()
                            }
                            .foregroundStyle(.orange)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.orange.opacity(0.12))
                            )
                        }
                    }
                    ForEach(library.sets) { set in
                        Button { toggle(set.id) } label: { row(for: set) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .background(Brand.canvas)
        }
    }

    private var problemSummary: String {
        let count = library.issueCount
        if count == 0 { return "\(FlagStore.filename) couldn't be read" }
        return count == 1 ? "1 file problem found" : "\(count) file problems found"
    }

    private func row(for set: FlashcardSet) -> some View {
        let isOn = selected.contains(set.id)
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .strokeBorder(isOn ? Color.clear : Brand.hairline, lineWidth: 2)
                    .background(Circle().fill(isOn ? Brand.accent : Color.clear))
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.brand(13, .bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(set.title).font(.brandBody).foregroundStyle(.primary)
                Text(cardSummary(for: set))
                    .font(.brandCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Brand.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isOn ? Brand.accent : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isOn)
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
            VStack(spacing: 10) {
                if selectedSets.isEmpty {
                    Text("Pick a set to start")
                        .font(.brandCaption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }

                HStack(spacing: 12) {
                    Button("Flashcards") { start(.flashcards) }
                        .buttonStyle(.solid)
                    Button("Quiz") { start(.quiz) }
                        .buttonStyle(.soft)
                }
                .disabled(selectedSets.isEmpty)
                .opacity(selectedSets.isEmpty ? 0.5 : 1)
            }
            .animation(.easeInOut(duration: 0.2), value: selectedSets.isEmpty)
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 18)   // clears the ledge under each button
            .background(Brand.canvas.opacity(0.94))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Sets")
                .font(.brandDisplay)
            Spacer()
            if !library.sets.isEmpty {
                Button(allSelected ? "Clear" : "All") { toggleAll() }
                    .buttonStyle(CrashButton(kind: .ghost, fullWidth: false))
                HeaderChip(symbol: "mic.fill", name: "Voice study", tint: Brand.accent) {
                    studyingVoice = true
                }
                .disabled(selectedSets.isEmpty)
                .opacity(selectedSets.isEmpty ? 0.4 : 1)
            }
            HeaderChip(symbol: "plus", name: "New set", tint: Brand.accent) {
                importingSet = true
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .background(Brand.canvas)
    }

    private func start(_ mode: StudyMode) {
        Haptics.knock()
        studyMode = mode
    }

    private func toggle(_ id: String) {
        Haptics.select()
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
    private func toggleAll() {
        selected = allSelected ? [] : Set(library.sets.map(\.id))
    }
}
