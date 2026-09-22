import Testing
import Foundation
@testable import crashcards

/// `isActive(at:)` is the whole scheduling feature — the shield is derived from it, so every
/// edge it gets wrong is an hour of blocking that doesn't happen, or won't stop.
struct FocusScheduleTests {

    /// Fixed so a test never depends on where it runs. Sunday 2026-09-20 is a known weekday.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// `weekday` is a Calendar weekday, 1 = Sunday. 2026-09-20 is a Sunday.
    private func date(weekday: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 19 + weekday,
                                           hour: hour, minute: minute))!
    }

    private func weekdaySchedule(start: Int = 9 * 60, end: Int = 11 * 60) -> FocusSchedule {
        FocusSchedule(start: start, end: end, days: FocusSchedule.weekdays)
    }

    @Test func dateHelperLandsOnTheWeekdayItClaims() {
        for weekday in 1...7 {
            #expect(calendar.component(.weekday, from: date(weekday: weekday, hour: 12)) == weekday)
        }
    }

    // MARK: - Inside and outside the window

    @Test func activeInsideTheWindowOnAScheduledDay() {
        let schedule = weekdaySchedule()
        #expect(schedule.isActive(at: date(weekday: 2, hour: 10), calendar: calendar))
    }

    @Test func inactiveBeforeAndAfterTheWindow() {
        let schedule = weekdaySchedule()
        #expect(!schedule.isActive(at: date(weekday: 2, hour: 8, minute: 59), calendar: calendar))
        #expect(!schedule.isActive(at: date(weekday: 2, hour: 11, minute: 1), calendar: calendar))
    }

    /// The start is inclusive and the end exclusive, so back-to-back windows can't overlap.
    @Test func startIsInclusiveAndEndIsExclusive() {
        let schedule = weekdaySchedule()
        #expect(schedule.isActive(at: date(weekday: 2, hour: 9), calendar: calendar))
        #expect(!schedule.isActive(at: date(weekday: 2, hour: 11), calendar: calendar))
    }

    @Test func inactiveOnADayItDoesNotCover() {
        let schedule = weekdaySchedule()
        #expect(!schedule.isActive(at: date(weekday: 1, hour: 10), calendar: calendar))
        #expect(!schedule.isActive(at: date(weekday: 7, hour: 10), calendar: calendar))
    }

    @Test func disabledNeverRuns() {
        var schedule = weekdaySchedule()
        schedule.enabled = false
        #expect(!schedule.isActive(at: date(weekday: 2, hour: 10), calendar: calendar))
    }

    /// An invalid window can't be registered with iOS, so it must not shield on its own either.
    @Test func invalidNeverRuns() {
        let tooShort = FocusSchedule(start: 9 * 60, end: 9 * 60 + 5, days: FocusSchedule.weekdays)
        #expect(!tooShort.isActive(at: date(weekday: 2, hour: 9), calendar: calendar))

        let noDays = FocusSchedule(start: 9 * 60, end: 11 * 60, days: [])
        #expect(!noDays.isActive(at: date(weekday: 2, hour: 10), calendar: calendar))
    }

    @Test func aWindowEndingAtMidnightRunsUpToIt() {
        let evening = FocusSchedule(start: 22 * 60, end: 24 * 60, days: FocusSchedule.everyDay)
        #expect(evening.isValid)
        #expect(evening.isActive(at: date(weekday: 4, hour: 23, minute: 59), calendar: calendar))
        #expect(!evening.isActive(at: date(weekday: 4, hour: 21, minute: 59), calendar: calendar))
    }

    // MARK: - Validation

    @Test func validityTracksTheFifteenMinuteFloor() {
        #expect(FocusSchedule(start: 600, end: 615, days: [2]).isValid)
        #expect(!FocusSchedule(start: 600, end: 614, days: [2]).isValid)
    }

    @Test func aBackwardsWindowIsInvalid() {
        #expect(!FocusSchedule(start: 11 * 60, end: 9 * 60, days: [2]).isValid)
    }

    // MARK: - Next start

    @Test func nextStartFindsLaterTheSameDay() {
        let schedule = weekdaySchedule()
        let next = schedule.nextStart(after: date(weekday: 2, hour: 7), calendar: calendar)
        #expect(next == date(weekday: 2, hour: 9))
    }

    /// Once today's window has opened, the next one is the next scheduled day — not today.
    @Test func nextStartSkipsToTheFollowingDayOnceTodayHasOpened() {
        let schedule = weekdaySchedule()
        let next = schedule.nextStart(after: date(weekday: 2, hour: 10), calendar: calendar)
        #expect(next == date(weekday: 3, hour: 9))
    }

    @Test func nextStartJumpsTheWeekendForAWeekdaySchedule() {
        let schedule = weekdaySchedule()
        let next = schedule.nextStart(after: date(weekday: 6, hour: 12), calendar: calendar)
        #expect(next == date(weekday: 2 + 7, hour: 9))
    }

    @Test func nextStartIsNilForAScheduleThatNeverRuns() {
        var schedule = weekdaySchedule()
        schedule.enabled = false
        #expect(schedule.nextStart(after: date(weekday: 2, hour: 7), calendar: calendar) == nil)
    }

    // MARK: - Round trip and description

    @Test func survivesEncodingRoundTrip() throws {
        let schedule = FocusSchedule(start: 9 * 60 + 30, end: 11 * 60, days: [2, 4, 6],
                                     enabled: false)
        let data = try JSONEncoder().encode([schedule])
        let back = try JSONDecoder().decode([FocusSchedule].self, from: data)
        #expect(back == [schedule])
    }

    @Test func namesTheDayShapesWorthNaming() {
        #expect(FocusSchedule(start: 0, end: 60, days: FocusSchedule.everyDay).daysText
                == "Every day")
        #expect(FocusSchedule(start: 0, end: 60, days: FocusSchedule.weekdays).daysText
                == "Weekdays")
        #expect(FocusSchedule(start: 0, end: 60, days: [1, 7]).daysText == "Weekends")
    }

    @Test func everyDayCostsOneActivityInsteadOfSeven() {
        #expect(FocusSchedule(start: 0, end: 60, days: FocusSchedule.everyDay).coversEveryDay)
        #expect(!FocusSchedule(start: 0, end: 60, days: FocusSchedule.weekdays).coversEveryDay)
    }
}
