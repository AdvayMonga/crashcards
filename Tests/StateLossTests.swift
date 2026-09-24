import Foundation
import Testing
@testable import crashcards

/// Three ways the app could lose something the user can't get back. Each of these fails
/// against the code as it was.
struct StateLossTests {

    // MARK: - Flags survive a bracket in the filename

    /// "Bio (1)" renders as "## Bio (1) (Bio (1).md)". Split at the last bracket that reads
    /// back as "1).md", and every flag in the set is orphaned for good.
    @Test func readsTheIdBackFromAHeadingWhoseTitleHasBrackets() {
        let (title, id) = FlagStore.splitHeading("Bio (1) (Bio (1).md)")
        #expect(title == "Bio (1)")
        #expect(id == "Bio (1).md")
    }

    @Test(arguments: [
        ("Biology (Biology.md)", "Biology", "Biology.md"),
        ("Chem 2 (Chem 2.csv)", "Chem 2", "Chem 2.csv"),
        ("Notes (a) (b) (Notes (a) (b).md)", "Notes (a) (b)", "Notes (a) (b).md"),
        ("Set (1) (2) (Set (1) (2).txt)", "Set (1) (2)", "Set (1) (2).txt"),
    ])
    func splitsEveryShapeOfHeading(heading: String, title: String, id: String) {
        let split = FlagStore.splitHeading(heading)
        #expect(split.title == title)
        #expect(split.id == id)
    }

    /// A heading nobody's renderer wrote — hand-typed in Obsidian. It must still group its
    /// flags rather than dropping them.
    @Test func keepsAHeadingThatNamesNoFile() {
        let (title, id) = FlagStore.splitHeading("Just a heading")
        #expect(title == "Just a heading")
        #expect(id == "Just a heading")
    }

    /// The round trip is what actually matters: what `render` writes, `parse` must read back.
    @Test func survivesTheRoundTripThroughTheFile() {
        let card = Card(content: .flip(front: "q", back: "a"),
                        setID: "Bio (1).md", setTitle: "Bio (1)")
        let suite = "flag-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let heading = "## \(card.setTitle) (\(card.setID))"
        let (title, id) = FlagStore.splitHeading(String(heading.dropFirst(3)))
        #expect(id == card.setID)
        #expect(title == card.setTitle)
    }

    // MARK: - A window ending at midnight

    /// 1440 minutes is hour 24, which is not a time of day. DeviceActivitySchedule throws on
    /// it, and the registration loop used to give up at the first throw — so one window set
    /// to midnight quietly switched off every window after it.
    @Test func midnightBecomesTheLastMinuteOfTheDayNotHour24() {
        let parts = ScreenTimeManager.components(minute: 24 * 60, weekday: nil)
        #expect(parts.hour == 23)
        #expect(parts.minute == 59)
    }

    @Test(arguments: [(0, 0, 0), (9 * 60, 9, 0), (13 * 60 + 30, 13, 30), (23 * 60 + 59, 23, 59)])
    func keepsEveryOtherTimeExactly(minute: Int, hour: Int, min: Int) {
        let parts = ScreenTimeManager.components(minute: minute, weekday: nil)
        #expect(parts.hour == hour)
        #expect(parts.minute == min)
    }

    @Test func aWindowEndingAtMidnightIsStillAValidWindow() {
        let evening = FocusSchedule(start: 22 * 60, end: 24 * 60, days: FocusSchedule.everyDay)
        #expect(evening.isValid)
        let end = ScreenTimeManager.components(minute: evening.end, weekday: nil)
        #expect(end.hour == 23 && end.minute == 59)
    }

    // MARK: - Lifetime stats outliving a format change

    private func store(raw: String) -> StatsStore {
        let suite = "stats-loss-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(Data(raw.utf8), forKey: StatsStore.key)
        return StatsStore(defaults: defaults)
    }

    /// A row written before a figure existed still reads, with the new figure at zero. Without
    /// this, adding one property to DayStats in a later version reads a year as nothing.
    @Test func readsARowThatPredatesTodaysFields() {
        let stats = store(raw: #"[{"day":"2026-01-01","answered":10,"correct":7}]"#)

        #expect(stats.days.count == 1)
        #expect(stats.totalAnswered == 10)
        #expect(stats.totalCorrect == 7)
        #expect(stats.days[0].bestStreak == 0)   // absent from the stored row
        #expect(!stats.isUnreadable)
    }

    /// A row from a *later* version reads too — the extra figure is simply ignored.
    @Test func readsARowFromANewerVersion() {
        let stats = store(raw: #"[{"day":"2026-01-01","answered":4,"correct":4,"somethingNew":9}]"#)
        #expect(stats.totalAnswered == 4)
        #expect(!stats.isUnreadable)
    }

    /// Genuinely unreadable bytes: report it and write nothing. Recording over them would
    /// destroy whatever was there, and nobody can get that back.
    @Test func refusesToWriteOverSomethingItCouldNotRead() {
        let suite = "stats-loss-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let corrupt = Data("not json at all".utf8)
        defaults.set(corrupt, forKey: StatsStore.key)

        let stats = StatsStore(defaults: defaults)
        #expect(stats.isUnreadable)

        stats.record(StudyRun(answered: 5, correct: 5, seconds: 10, isComplete: true))
        #expect(defaults.data(forKey: StatsStore.key) == corrupt)   // untouched
    }

    /// An empty store is not an unreadable one — that is every first launch.
    @Test func afirstLaunchIsNotAFailure() {
        let suite = "stats-loss-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let stats = StatsStore(defaults: defaults)
        #expect(!stats.isUnreadable)
        stats.record(StudyRun(answered: 3, correct: 2, seconds: 9, isComplete: true))
        #expect(stats.totalAnswered == 3)
        #expect(defaults.data(forKey: StatsStore.key) != nil)
    }
}
