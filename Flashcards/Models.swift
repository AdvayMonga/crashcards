import Foundation

/// A single flashcard: a front (prompt) and a back (answer).
struct Card: Identifiable, Hashable {
    let id = UUID()
    let front: String
    let back: String
}

/// One `.md` file's worth of cards. `id` is the filename (unique within the folder).
struct FlashcardSet: Identifiable, Hashable {
    let id: String
    let title: String
    let cards: [Card]
}
