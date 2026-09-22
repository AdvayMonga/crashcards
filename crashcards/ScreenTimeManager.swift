import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity
import Observation
import UserNotifications

/// Blocks user-chosen apps via Screen Time (Family Controls). Opening a blocked app shows
/// the system shield; answering questions in the app lifts it for a grace window.
/// Real behavior is device-only — the simulator can't shield apps.
@MainActor
@Observable
final class ScreenTimeManager {
    var selection = FamilyActivitySelection()
    var isAuthorized = false
    var isBlocking = false
    var unlockedUntil: Date?
    var errorText: String?

    var schedules: [FocusSchedule] = []

    /// Correct answers required to unlock, and how long an unlock lasts. Both are settings
    /// now, and both are read by the shield extension, so they live in the App Group.
    var questionsToUnlock = BlockingShared.questionsToUnlock {
        didSet { BlockingShared.questionsToUnlock = questionsToUnlock }
    }
    var unlockMinutes = BlockingShared.unlockMinutes {
        didSet { BlockingShared.unlockMinutes = unlockMinutes }
    }

    /// What the steppers offer. Past these an unlock stops being a speed bump either way.
    static let questionRange = 1...10
    static let minuteRange = 5...60
    static let minuteStep = 5

    /// iOS caps how many activities one app may monitor; one slot is kept for the re-lock.
    static let maxScheduleActivities = 19

    private let center = DeviceActivityCenter()

    init() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        isBlocking = BlockingShared.isBlocking
        selection = BlockingShared.selection
        unlockedUntil = BlockingShared.unlockedUntil
        schedules = BlockingShared.schedules
        // Registrations live in iOS, not here, and a reinstall or a dropped registration
        // would leave windows that block only while the app happens to be open.
        registerSchedules()
        refresh()
    }

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

    /// True while an unlock window is running.
    var isUnlockedNow: Bool { BlockingShared.isUnlocked }

    /// True while apps are shielded — by the switch or by a schedule, and not unlocked.
    /// The same rule as `BlockingShared.shouldShield`, over the loaded schedules.
    var isShieldActive: Bool {
        hasSelection && !BlockingShared.isUnlocked && (isBlocking || activeSchedule != nil)
    }

    /// Switched on, or inside a window, but nothing picked to block — so nothing is. The
    /// screen says this out loud rather than claiming a shield that isn't there.
    var needsApps: Bool {
        !hasSelection && (isBlocking || activeSchedule != nil)
    }

    /// The schedule doing the blocking right now, if that's why the shield is up.
    /// Read from the loaded array rather than `BlockingShared`, which would decode the
    /// stored JSON on every pass of `body`. Only this class writes schedules, so the two
    /// can't disagree; the extensions, which have no such array, go through `BlockingShared`.
    var activeSchedule: FocusSchedule? { schedules.first { $0.isActive(at: Date()) } }

    /// The next window to open, and when. Drives the "next block" line on the Focus tab.
    var nextScheduled: (schedule: FocusSchedule, date: Date)? {
        let now = Date()
        return schedules
            .compactMap { schedule in schedule.nextStart(after: now).map { (schedule, $0) } }
            .min { $0.1 < $1.1 }
    }

    /// Re-sync with shared state and expire a stale unlock. Safe to call on every foreground.
    ///
    /// This is also the self-heal: the shield is recomputed from the clock, so a schedule
    /// whose DeviceActivity callback never arrived still takes effect the next time the app
    /// is looked at.
    func refresh() {
        unlockedUntil = BlockingShared.isUnlocked ? BlockingShared.unlockedUntil : nil
        if unlockedUntil == nil { BlockingShared.unlockedUntil = nil }
        BlockingShared.applyShield()
    }

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
            errorText = nil
            // Any window added before permission was granted could not be registered then.
            if isAuthorized { registerSchedules(); requestNotifications() }
        } catch {
            errorText = error.localizedDescription
            isAuthorized = false
        }
    }

    func saveSelection() {
        BlockingShared.selection = selection
        BlockingShared.applyShield()   // keep an active shield in sync with edits
    }

    func startBlocking() {
        requestNotifications()
        isBlocking = true
        unlockedUntil = nil
        BlockingShared.isBlocking = true
        BlockingShared.unlockedUntil = nil
        center.stopMonitoring([BlockingShared.relockActivity])
        BlockingShared.applyShield()
    }

    func stopBlocking() {
        isBlocking = false
        unlockedUntil = nil
        BlockingShared.isBlocking = false
        BlockingShared.unlockedUntil = nil
        center.stopMonitoring([BlockingShared.relockActivity])
        BlockingShared.applyShield()
    }

    /// Lift the shield for the grace window, then have the monitor extension re-apply it.
    func unlock() {
        let until = Date().addingTimeInterval(TimeInterval(unlockMinutes * 60))
        unlockedUntil = until
        BlockingShared.unlockedUntil = until
        BlockingShared.applyShield()
        scheduleRelock(at: until)
    }

    /// Before iOS 26.5 the shield's Answer button reaches the app through a notification,
    /// so the permission is asked for where blocking is turned on. Asked once; iOS remembers.
    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Schedules

    func addSchedule(_ schedule: FocusSchedule) {
        schedules.append(schedule)
        saveSchedules()
    }

    func removeSchedule(_ schedule: FocusSchedule) {
        schedules.removeAll { $0.id == schedule.id }
        saveSchedules()
    }

    func setSchedule(_ schedule: FocusSchedule, enabled: Bool) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[index].enabled = enabled
        saveSchedules()
    }

    private func saveSchedules() {
        BlockingShared.schedules = schedules
        registerSchedules()
        BlockingShared.applyShield()
    }

    /// Hand every enabled schedule to DeviceActivity so its edges wake the monitor extension
    /// with the app closed. Registrations are rebuilt wholesale — reconciling them one by one
    /// would be more code than simply starting over.
    private func registerSchedules() {
        // Monitoring can't be started before Screen Time is authorized; requesting it
        // registers whatever is already saved, so nothing is lost by returning here.
        guard isAuthorized else { return }

        let stale = center.activities.filter {
            $0.rawValue.hasPrefix(BlockingShared.scheduleActivityPrefix)
        }
        if !stale.isEmpty { center.stopMonitoring(stale) }

        let live = schedules.filter { $0.enabled && $0.isValid }
        let cost = live.reduce(0) { $0 + ($1.coversEveryDay ? 1 : $1.days.count) }
        guard cost <= Self.maxScheduleActivities else {
            errorText = "That's more scheduled windows than iOS will track at once. "
                + "Remove one, or set a schedule to every day so it counts once instead of seven times."
            return
        }

        for schedule in live {
            // A daily repeat needs time-only components; a weekly one pins the weekday too.
            let days: [Int?] = schedule.coversEveryDay ? [nil] : schedule.days.sorted().map { $0 }
            for day in days {
                let window = DeviceActivitySchedule(
                    intervalStart: components(minute: schedule.start, weekday: day),
                    intervalEnd: components(minute: schedule.end, weekday: day),
                    repeats: true
                )
                do {
                    try center.startMonitoring(name(schedule, day: day), during: window)
                } catch {
                    errorText = "Couldn't schedule \(schedule.timeText): \(error.localizedDescription)"
                    return
                }
            }
        }
        errorText = nil
    }

    private func components(minute: Int, weekday: Int?) -> DateComponents {
        var parts = DateComponents()
        parts.hour = minute / 60
        parts.minute = minute % 60
        parts.weekday = weekday
        return parts
    }

    private func name(_ schedule: FocusSchedule, day: Int?) -> DeviceActivityName {
        let suffix = day.map(String.init) ?? "all"
        return DeviceActivityName(
            "\(BlockingShared.scheduleActivityPrefix)\(schedule.id.uuidString)-\(suffix)")
    }

    /// DeviceActivity schedules must span at least 15 minutes, so the window we care about is
    /// the *start* — `intervalDidStart` re-shields at `date`; the end is padding to satisfy that.
    private func scheduleRelock(at date: Date) {
        let calendar = Calendar.current
        let fields: Set<Calendar.Component> = [.hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(fields, from: date),
            intervalEnd: calendar.dateComponents(fields, from: date.addingTimeInterval(15 * 60)),
            repeats: false
        )
        center.stopMonitoring([BlockingShared.relockActivity])
        do {
            try center.startMonitoring(BlockingShared.relockActivity, during: schedule)
        } catch {
            errorText = "Couldn't schedule the re-lock: \(error.localizedDescription)"
        }
    }
}
