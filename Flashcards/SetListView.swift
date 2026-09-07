import SwiftUI

/// Home screen: pick which sets to study, then start a shuffled session in either mode.
struct SetListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(FlagStore.self) private var flags
    @State private var selected: Set<String> = Prefs.selectedSetIDs
    @State private var studyMode: StudyMode?
    @State private var studyingVoice = false

    private var selectedSets: [FlashcardSet] {
        library.sets.filter { selected.contains($0.id) }
    }
    private var allSelected: Bool {
        !library.sets.isEmpty && selected.isSuperset(of: library.sets.map(\.id))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Sets")
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) { studyBar }
                .navigationDestination(item: $studyMode) { mode in
                    StudyView(session: StudySession(sets: selectedSets), mode: mode)
                }
                .navigationDestination(isPresented: $studyingVoice) {
                    VoiceStudyView(session: StudySession(sets: selectedSets))
                }
        }
        .onChange(of: library.sets.map(\.id)) { _, ids in
            selected = selected.intersection(ids)   // forget sets that no longer exist
        }
        .onChange(of: selected) { _, new in
            Prefs.selectedSetIDs = new
        }
    }

    @ViewBuilder private var content: some View {
        if let error = library.loadError {
            ContentUnavailableView("Couldn't read folder", systemImage: "exclamationmark.triangle",
                                   description: Text(error))
        } else if library.sets.isEmpty {
            ContentUnavailableView("No sets found", systemImage: "tray",
                                   description: Text("Add .md files to your flashcards folder."))
        } else {
            List(library.sets) { set in
                Button { toggle(set.id) } label: { row(for: set) }
                    .tint(.primary)
            }
        }
    }

    private func row(for set: FlashcardSet) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selected.contains(set.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected.contains(set.id) ? Color.accentColor : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(set.title).font(.headline)
                Text(set.cards.count == 1 ? "1 card" : "\(set.cards.count) cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
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
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
    private func toggleAll() {
        selected = allSelected ? [] : Set(library.sets.map(\.id))
    }
}
