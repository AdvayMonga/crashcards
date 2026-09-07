import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity
import Observation

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

    /// Correct answers required to unlock, and how long an unlock lasts.
    static let questionsToUnlock = 3
    static let unlockMinutes = 10

    private let center = DeviceActivityCenter()

    init() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        isBlocking = BlockingShared.isBlocking
        selection = BlockingShared.selection
        unlockedUntil = BlockingShared.unlockedUntil
        refresh()
    }

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

    /// True while apps are shielded — i.e. blocking is on and no unlock window is running.
    var isShieldActive: Bool { isBlocking && !BlockingShared.isUnlocked }

    /// Re-sync with shared state and expire a stale unlock. Safe to call on every foreground.
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
        let until = Date().addingTimeInterval(TimeInterval(Self.unlockMinutes * 60))
        unlockedUntil = until
        BlockingShared.unlockedUntil = until
        BlockingShared.applyShield()
        scheduleRelock(at: until)
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
