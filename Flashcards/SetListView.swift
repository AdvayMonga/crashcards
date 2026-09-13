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
                .navigationTitle("Sets")
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) { studyBar }
                .navigationDestination(item: $studyMode) { mode in
                    destination(for: mode) { StudyView(session: StudySession(cards: $0), mode: mode) }
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
            List {
                if hasProblems {
                    Section {
                        NavigationLink {
                            FileProblemsView().environment(library).environment(flags)
                        } label: {
                            Label(problemSummary, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Section {
                    ForEach(library.sets) { set in
                        Button { toggle(set.id) } label: { row(for: set) }
                            .tint(.primary)
                    }
                }
            }
        }
    }

    private var problemSummary: String {
        let count = library.issueCount
        if count == 0 { return "\(FlagStore.filename) couldn't be read" }
        return count == 1 ? "1 file problem found" : "\(count) file problems found"
    }

    private func row(for set: FlashcardSet) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected.contains(set.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected.contains(set.id) ? Color.accentColor : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(set.title).font(.headline)
                Text(cardSummary(for: set))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
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
                    Text("Pick a set to start.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button { studyMode = .flashcards } label: {
                        Text("Flashcards").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button { studyMode = .quiz } label: {
                        Text("Quiz").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                }
                .controlSize(.large)
                .disabled(selectedSets.isEmpty)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .background(.bar)
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !library.sets.isEmpty {
                Button(allSelected ? "Deselect All" : "Select All") { toggleAll() }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { studyingVoice = true } label: {
                Label("Voice", systemImage: "mic.fill")
            }
            .disabled(selectedSets.isEmpty)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { importingSet = true } label: {
                Label("New Set", systemImage: "plus")
            }
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
    private func toggleAll() {
        selected = allSelected ? [] : Set(library.sets.map(\.id))
    }
}
