import SwiftUI
import Foundation

/// Study tab: pick which sets to study, then start a shuffled session in one of the modes.
///
/// Selected sets rise off the table the way a held card does, which is the whole selection
/// affordance — there's no checkbox doing the work on its own.
struct SetListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(FlagStore.self) private var flags
    @Environment(StatsStore.self) private var stats
    @State private var selected: Set<String> = Prefs.selectedSetIDs
    @State private var studyMode: StudyMode?
    @State private var importingFolder = false
    @State private var importingSet = false
    @State private var showingProblems = false
    @State private var renaming: FlashcardSet?
    @State private var deleting: FlashcardSet?
    @State private var newTitle = ""
    /// Picking sets to delete rather than to study. The two selections are kept apart so
    /// leaving this mode doesn't cost you the sets you had lined up.
    @State private var culling = false
    @State private var marked: Set<String> = []
    @State private var confirmingCull = false

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
            .screenLayer(isPresented: $showingProblems) {
                FileProblemsView { showingProblems = false }
                    .environment(library)
                    .environment(flags)
            }
            .screenLayer(isPresented: $importingSet) {
                ImportSetView(onClose: { importingSet = false }) { library.reload() }
                    .environment(library)
            }
            .overlay { setDialogs }
            .animation(Motion.pop, value: renaming?.id)
            .animation(Motion.pop, value: deleting?.id)
            .animation(Motion.pop, value: confirmingCull)
            .animation(Motion.settle, value: culling)
            .onChange(of: library.sets.map(\.id)) { _, ids in
                // Only prune against a scan that actually saw everything. A folder that is
                // offline, moved, or not yet downloaded from iCloud is reported as a
                // recoverable folderError and its sets are simply absent — pruning on that
                // would clear the selection permanently, since the next change writes it
                // straight to Prefs.
                guard library.folderErrors.isEmpty, library.loadError == nil else { return }
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
        if let reason = mode.unavailableReason(for: selectedSets) {
            ModeUnavailableView(mode: mode, reason: reason) { studyMode = nil }
        } else {
            let cards = mode.usableCards(in: selectedSets)
            switch mode {
            case .flashcards:
                CardDeckView(cards: cards) { studyMode = nil }
            case .quiz:
                // The days you've already put in set the mult this run opens on.
                QuizView(session: StudySession(cards: cards, dayStreak: stats.dayStreak)) {
                    studyMode = nil
                }
            }
        }
    }

    // MARK: - Renaming and deleting

    /// Only sets the app owns can be renamed or deleted — a file in an attached folder is
    /// the user's, and the app never edits those.
    @ViewBuilder private var setDialogs: some View {
        if let set = renaming {
            CrashModal(title: "Rename set",
                       confirm: (label: "Rename",
                                 enabled: !newTitle.trimmingCharacters(in: .whitespaces).isEmpty,
                                 action: {
                                     library.renameSet(set, to: newTitle)
                                     renaming = nil
                                 }),
                       onCancel: { renaming = nil }) {
                Panel(footnote: "Renames the file in the app's own library.") {
                    PanelRow(first: true) {
                        CrashField(placeholder: "Name", text: $newTitle)
                    }
                }
            }
        } else if let set = deleting {
            CrashDialog(title: "Delete this set?",
                        message: "“\(set.title)” is removed from the app's library. This can't be undone.",
                        onCancel: { deleting = nil }) {
                Button("Delete") {
                    Haptics.wrong()
                    library.deleteSet(set)
                    deleting = nil
                }
                .buttonStyle(.solid(Brand.mult))
            }
        } else if confirmingCull {
            CrashDialog(title: markedSets.count == 1 ? "Delete this set?" : "Delete \(markedSets.count) sets?",
                        message: "\(markedNames) will be removed from the app's library. This can't be undone.",
                        onCancel: { confirmingCull = false }) {
                Button("Delete") { cull() }
                    .buttonStyle(.solid(Brand.mult))
            }
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
                        Button { tap(set) } label: { row(for: set) }
                            .buttonStyle(.pressable)
                            // A folder's file isn't the app's to delete, so it can't be marked.
                            .disabled(culling && !set.isLocal)
                            .opacity(culling && !set.isLocal ? 0.4 : 1)
                            .contextMenu { if !culling { actions(for: set) } }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private func actions(for set: FlashcardSet) -> some View {
        if set.isLocal {
            Button {
                newTitle = set.title
                renaming = set
            } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { deleting = set } label: {
                Label("Delete", systemImage: "trash")
            }
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
        // While culling, a lit row is one about to be deleted, so it lights red instead
        // of gold — the same affordance saying the opposite thing.
        let isOn = culling ? marked.contains(set.id) : selected.contains(set.id)
        let lit = culling ? Brand.mult : Brand.gold
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOn ? lit : Brand.surfaceLedge)
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
                    .foregroundStyle(isOn ? lit : Brand.inkFaint)
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
                .strokeBorder(lit, lineWidth: isOn ? 2.5 : 0)
                .padding(1.5))
        .offset(y: isOn ? -3 : 0)
        .animation(Motion.pop, value: isOn)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isOn ? "Tap to deselect" : "Tap to select")
    }

    /// Card count, split by kind so it's obvious which sets a quiz can use.
    private func cardSummary(for set: FlashcardSet) -> String {
        // Just the count. Every set can be quizzed whatever its cards look like, so naming
        // the answer style here only added a distinction you don't act on.
        set.cards.count == 1 ? "1 card" : "\(set.cards.count) cards"
    }

    @ViewBuilder private var studyBar: some View {
        if !library.sets.isEmpty {
            VStack(spacing: 8) {
                Text(barHint)
                    .font(.brandCaption)
                    .foregroundStyle(culling ? Brand.mult : Brand.inkFaint)
                    .opacity(barHint.isEmpty ? 0 : 1)
                    .transition(.opacity)

                HStack(spacing: 12) {
                    if culling {
                        Button("Cancel") { endCulling() }
                            .buttonStyle(.soft)
                        Button("Delete") { confirmingCull = true }
                            .buttonStyle(.solid(Brand.mult))
                            .disabled(marked.isEmpty)
                    } else {
                        Group {
                            Button("Flashcards") { start(.flashcards) }
                                .buttonStyle(.solid(Brand.chips))
                            Button("Quiz") { start(.quiz) }
                                .buttonStyle(.solid(Brand.purple))
                        }
                        // Not on the HStack: in delete mode that would take Cancel with it.
                        .disabled(selectedSets.isEmpty)
                    }
                }
            }
            .animation(Motion.settle, value: selectedSets.isEmpty)
            .animation(Motion.settle, value: culling)
            .animation(Motion.settle, value: marked.isEmpty)
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, Brand.ledge)
        }
    }

    private var header: some View {
        ScreenHeader(title: "Sets") {
            if !library.sets.isEmpty, !culling {
                Button(allSelected ? "Clear" : "All") { toggleAll() }
                    .buttonStyle(CrashButton(kind: .ghost, tint: Brand.inkDim, fullWidth: false))
            }
            // The way out is Cancel in the bar below, so the header offers no second one.
            if !culling {
                // Only the app's own sets can go, so the way in only appears when there is
                // one to delete.
                if library.sets.contains(where: \.isLocal) {
                    HeaderChip(glyph: .trash, name: "Delete sets", tint: Brand.gold) {
                        Haptics.knock()
                        culling = true
                    }
                }
                HeaderChip(glyph: .plus, name: "New set", tint: Brand.gold) {
                    importingSet = true
                }
            }
        }
    }

    /// The line above the buttons: what to do, or what is about to happen.
    private var barHint: String {
        if culling {
            if marked.isEmpty { return "Pick the sets to delete" }
            return marked.count == 1 ? "1 set will be deleted" : "\(marked.count) sets will be deleted"
        }
        return selectedSets.isEmpty ? "Pick a set to start" : ""
    }

    private func start(_ mode: StudyMode) {
        Haptics.thud()
        studyMode = mode
    }

    private func tap(_ set: FlashcardSet) {
        Haptics.select()
        if culling {
            if marked.contains(set.id) { marked.remove(set.id) } else { marked.insert(set.id) }
        } else if selected.contains(set.id) {
            selected.remove(set.id)
        } else {
            selected.insert(set.id)
        }
    }

    private func endCulling() {
        culling = false
        marked = []
    }

    /// Filtered by `isLocal` as well as by mark, so a folder's file can never be caught up
    /// in a delete even if it somehow got marked.
    private var markedSets: [FlashcardSet] {
        library.sets.filter { marked.contains($0.id) && $0.isLocal }
    }

    /// Named while the list is short enough to read; counted once it isn't.
    private var markedNames: String {
        let names = markedSets.map { "“\($0.title)”" }
        guard names.count <= 3 else { return "\(names.count) sets" }
        return ListFormatter.localizedString(byJoining: names)
    }

    /// Only the app's own sets go. A file in an attached folder is yours, and the app has
    /// never written to those.
    private func cull() {
        Haptics.wrong()
        for set in markedSets { library.deleteSet(set) }
        selected.subtract(marked)
        confirmingCull = false
        endCulling()
    }
    private func toggleAll() {
        Haptics.knock()
        selected = allSelected ? [] : Set(library.sets.map(\.id))
    }
}
