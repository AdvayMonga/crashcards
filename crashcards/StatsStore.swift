import Foundation
import Observation

/// One local day's activity. Every figure in Settings is folded from these rows.
struct DayStats: Codable, Hashable {
    let day: String
    var answered = 0
    var correct = 0
    var seconds = 0
    var sessions = 0
    var unlocks = 0
    /// Points earned. Recorded for a possible lifetime tier system; nothing displays it yet.
    var score = 0
    var bestScore = 0
    var bestStreak = 0
}

/// One pass through some cards, handed over when it ends. Flashcards mode doesn't produce
/// these — it isn't graded, so there's nothing to count.
struct StudyRun {
    var answered = 0
    var correct = 0
    var seconds = 0
    var bestStreak = 0
    /// Quiz only. The gate isn't scored, so it leaves this at zero.
    var score = 0
    /// Whether the run was played to the end. One left early still counts as activity, but
    /// can't stand as a personal best.
    var isComplete = false
    var unlocks = 0
}

/// Daily activity totals, kept in the App Group.
///
/// The `.md` files stay the source of truth for cards; this is the one thing the app knows
/// that they don't. It lives in `UserDefaults` rather than a file in your folder because a
/// folder is optional, and because nobody hand-edits their own accuracy.
///
/// Rows are per day, not per answer: a year of study is 365 small structs, and a run is
/// written once when it ends rather than on every card.
@Observable
final class StatsStore {
    static let key = "dailyStats"

    private let defaults: UserDefaults
    private(set) var days: [DayStats] = []

    init(defaults: UserDefaults = BlockingShared.defaults) {
        self.defaults = defaults
        load()
    }

    func load() {
        guard let data = defaults.data(forKey: Self.key),
              let saved = try? JSONDecoder().decode([DayStats].self, from: data)
        else { return }
        days = saved.sorted { $0.day < $1.day }
    }

    /// Fold a run into today's row.
    func record(_ run: StudyRun) {
        guard run.answered > 0 else { return }
        let key = Self.dayKey(Date())
        var day = days.first { $0.day == key } ?? DayStats(day: key)

        day.answered += run.answered
        day.correct += run.correct
        day.seconds += run.seconds
        day.sessions += 1
        day.unlocks += run.unlocks
        day.score += run.score
        day.bestStreak = max(day.bestStreak, run.bestStreak)
        if run.isComplete { day.bestScore = max(day.bestScore, run.score) }

        if let index = days.firstIndex(where: { $0.day == key }) {
            days[index] = day
        } else {
            days.append(day)
            days.sort { $0.day < $1.day }
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(days) else { return }
        defaults.set(data, forKey: Self.key)
    }

    // MARK: - Reading

    var today: DayStats {
        let key = Self.dayKey(Date())
        return days.first { $0.day == key } ?? DayStats(day: key)
    }

    var totalAnswered: Int { days.reduce(0) { $0 + $1.answered } }
    var totalCorrect: Int { days.reduce(0) { $0 + $1.correct } }
    var totalSeconds: Int { days.reduce(0) { $0 + $1.seconds } }
    var totalSessions: Int { days.reduce(0) { $0 + $1.sessions } }
    var totalUnlocks: Int { days.reduce(0) { $0 + $1.unlocks } }

    var bestScore: Int { days.map(\.bestScore).max() ?? 0 }
    var bestStreak: Int { days.map(\.bestStreak).max() ?? 0 }

    /// Lifetime accuracy, or nil before a single question has been answered.
    var accuracy: Int? { Self.percent(totalCorrect, of: totalAnswered) }

    /// Days studied back-to-back, counting to today. A day you haven't started yet doesn't
    /// break it — the streak you earned yesterday is still yours this morning.
    var dayStreak: Int {
        let active = Set(days.filter { $0.answered > 0 }.map(\.day))
        guard !active.isEmpty else { return 0 }

        let calendar = Calendar.current
        var cursor = Date()
        if !active.contains(Self.dayKey(cursor)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  active.contains(Self.dayKey(yesterday)) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while active.contains(Self.dayKey(cursor)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    var longestDayStreak: Int {
        let calendar = Calendar.current
        let dates = days.filter { $0.answered > 0 }.compactMap { Self.date(from: $0.day) }.sorted()
        guard !dates.isEmpty else { return 0 }

        var longest = 1, run = 1
        for (earlier, later) in zip(dates, dates.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: earlier, to: later).day ?? 0
            run = gap == 1 ? run + 1 : 1
            longest = max(longest, run)
        }
        return longest
    }

    /// The last `count` days, oldest first, with nil for days nothing was answered.
    func recent(_ count: Int) -> [DayStats?] {
        let calendar = Calendar.current
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let rows: [DayStats?] = (0..<count).map { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return byDay[Self.dayKey(date)]
        }
        return rows.reversed()
    }

    // MARK: - Days

    static func percent(_ part: Int, of whole: Int) -> Int? {
        guard whole > 0 else { return nil }
        return Int((Double(part) / Double(whole) * 100).rounded())
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(_ date: Date) -> String { formatter.string(from: date) }
    static func date(from key: String) -> Date? { formatter.date(from: key) }
}
