import DeviceActivity

/// Wakes on the edges of every window we care about, with the app closed.
///
/// Two kinds arrive here. `relock` is the one-shot whose *start* is the moment an unlock
/// expires (schedules must span 15+ minutes, so the end is only padding). Everything else is
/// a scheduled focus window, where both edges simply mean "the answer may have changed" —
/// `applyShield` decides from the clock, so neither callback needs to know which way.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        handle(activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        handle(activity)
    }

    private func handle(_ activity: DeviceActivityName) {
        if activity == BlockingShared.relockActivity {
            BlockingShared.endUnlock()
        } else {
            BlockingShared.applyShield()
        }
    }
}
