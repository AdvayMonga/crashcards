import SwiftUI

/// Home screen: pick which sets to study, then start a shuffled Classic session.
struct SetListView: View {
    @Environment(LibraryStore.self) private var library
    @State private var selected: Set<String> = Prefs.selectedSetIDs
    @State private var studying = false
    @State private var showSettings = false

    private var selectedSets: [FlashcardSet] {
        library.sets.filter { selected.contains($0.id) }
    }
    private var selectedCardCount: Int {
        selectedSets.reduce(0) { $0 + $1.cards.count }
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
                .navigationDestination(isPresented: $studying) {
                    StudyView(session: StudySession(sets: selectedSets))
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView().environment(library)
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
            Button { studying = true } label: {
                Text(selectedSets.isEmpty ? "Select sets to study"
                                          : "Study \(selectedCardCount) cards")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedSets.isEmpty)
            .padding()
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
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
    private func toggleAll() {
        selected = allSelected ? [] : Set(library.sets.map(\.id))
    }
}
