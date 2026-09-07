import DeviceActivity

/// Re-applies the shield when an unlock window expires, even if the app never reopens.
/// The window's *start* is the moment we re-lock (schedules must span 15+ minutes).
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity == BlockingShared.relockActivity { BlockingShared.endUnlock() }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == BlockingShared.relockActivity { BlockingShared.endUnlock() }
    }
}
