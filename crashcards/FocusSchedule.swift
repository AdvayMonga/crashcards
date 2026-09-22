import Foundation

/// A recurring window during which apps are blocked without anyone turning anything on.
///
/// Times are minutes from midnight rather than `Date`s: a schedule is a time of day, not a
/// moment, and storing it as a `Date` would pin it to the day it was created. Whether a
/// schedule is running right now is a pure function of the clock, which is what lets the
/// shield be derived rather than toggled — see `BlockingShared.shouldShield`.
struct FocusSchedule: Codable, Identifiable, Hashable {
    var id = UUID()
    /// Minutes from midnight. `end` is exclusive, and always later the same day.
    var start: Int
    var end: Int
    /// `Calendar` weekdays — 1 is Sunday.
    var days: Set<Int>
    var enabled = true

    /// DeviceActivity refuses to monitor a window shorter than this.
    static let minimumMinutes = 15
    static let everyDay: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    static let weekdays: Set<Int> = [2, 3, 4, 5, 6]

    /// A schedule iOS will actually accept: long enough, on at least one day, same-day.
    var isValid: Bool {
        !days.isEmpty && start >= 0 && end <= 24 * 60 && end - start >= Self.minimumMinutes
    }

    /// Every day means one daily DeviceActivity instead of seven weekly ones.
    var coversEveryDay: Bool { days.count == 7 }

    /// Is this window running at `date`? The whole feature rests on this one function.
    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, isValid else { return false }
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, days.contains(weekday),
              let hour = parts.hour, let minute = parts.minute
        else { return false }
        let nowMinute = hour * 60 + minute
        return nowMinute >= start && nowMinute < end
    }

    /// When this window next opens, so the Focus screen can say what's coming. Searches a
    /// week and a day — any enabled schedule recurs within that, or it never runs at all.
    func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        guard enabled, isValid else { return nil }
        let midnight = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: midnight),
                  let weekday = calendar.dateComponents([.weekday], from: day).weekday,
                  days.contains(weekday),
                  let opens = calendar.date(byAdding: .minute, value: start, to: day)
            else { continue }
            if opens > date { return opens }
        }
        return nil
    }

    // MARK: - Display

    var timeText: String { "\(Self.timeText(start)) – \(Self.timeText(end))" }

    /// "Every day" / "Weekdays" / "Mon, Wed, Fri" — the shapes worth naming, then the list.
    var daysText: String {
        if coversEveryDay { return "Every day" }
        if days == Self.weekdays { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        return Self.ordered(days).map(Self.dayAbbreviation).joined(separator: ", ")
    }

    /// Weekdays in the user's own week order — a week starts on Monday in most of the world.
    static func ordered(_ days: Set<Int>, calendar: Calendar = .current) -> [Int] {
        let first = calendar.firstWeekday
        return days.sorted { lhs, rhs in
            ((lhs - first) + 7) % 7 < ((rhs - first) + 7) % 7
        }
    }

    static func dayAbbreviation(_ weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return symbols[(weekday - 1) % symbols.count]
    }

    /// Minutes from midnight as a clock time, in whatever format the device uses.
    static func timeText(_ minute: Int) -> String {
        var parts = DateComponents()
        parts.hour = (minute / 60) % 24
        parts.minute = minute % 60
        let date = Calendar.current.date(from: parts) ?? Date()
        return timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0,
                                                        locale: .current)
        return formatter
    }()
}
