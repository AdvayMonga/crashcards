import SwiftUI
import FamilyControls

/// Focus tab: what's blocked, whether the shield is up, and the way past it.
struct FocusView: View {
    @Environment(ScreenTimeManager.self) private var manager
    @Environment(LibraryStore.self) private var library
    @State private var pickerShown = false
    @State private var unlocking = false
    @State private var startAfterPicking = false
    @State private var gatedApps = GatedApps.all
    @State private var addingApp = false
    @State private var copied: String?
    @State private var editing: FocusSchedule?

    /// Keeps the countdown honest while the screen is open.
    private let tick = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                status
                blockingPanel
                schedulePanel
                unlockPanel
                gatedPanel
                appsPanel
                if let error = manager.errorText {
                    Text(error)
                        .font(.reading(14))
                        .foregroundStyle(Brand.mult)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .slab(Brand.surface)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top) { ScreenHeader("Focus") }
        .familyActivityPicker(isPresented: $pickerShown, selection: pickerBinding)
        .screenLayer(isPresented: $addingApp) {
            AddGatedAppView(onClose: { addingApp = false }) { app in
                GatedApps.add(app)
                gatedApps = GatedApps.all
            }
        }
        .screenLayer(isPresented: $unlocking) {
            UnlockView(cards: library.quizCards, manager: manager) { unlocking = false }
        }
        .screenLayer(item: $editing) { draft in
            ScheduleEditorView(schedule: draft,
                               onSave: { manager.addSchedule($0) },
                               onClose: { editing = nil })
        }
        .onReceive(tick) { _ in manager.refresh() }
    }

    /// The one thing this screen is really answering: can I open my apps right now?
    private var status: some View {
        VStack(spacing: 14) {
            PixelIcon(glyph: statusGlyph, size: 54, color: statusColor)
                .padding(24)
                .slab(Brand.surfaceHigh, radius: Brand.cardRadius)
                .breathing(manager.isShieldActive ? 1.6 : 0.8, period: 3.0)

            Text(statusTitle)
                .font(.brandTitle)
                .foregroundStyle(Brand.ink)

            if let until = manager.unlockedUntil {
                Text(until, style: .timer)
                    .font(.number(30))
                    .foregroundStyle(Brand.green)
                    .monospacedDigit()
            } else if !statusDetail.isEmpty {
                Text(statusDetail)
                    .font(.reading(15))
                    .foregroundStyle(Brand.inkDim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if manager.isShieldActive {
                Button("Answer \(manager.questionsToUnlock) \(manager.questionsToUnlock == 1 ? "question" : "questions") to unlock") {
                    Haptics.thud()
                    unlocking = true
                }
                .buttonStyle(.solid)
                .disabled(library.quizCards.isEmpty)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
    }

    private var blockingPanel: some View {
        Panel(footnote: "Blocks apps until you turn this off. Scheduled windows below block on their own, whether or not this is on.") {
            PanelRow(first: true) {
                CrashToggle(label: "Block apps", isOn: blockingBinding)
            }
        }
    }

    /// Windows that block on their own. Rows can be switched off or deleted, not edited —
    /// a window is two times and a few days, which is quicker to re-add than to amend.
    private var schedulePanel: some View {
        Panel(title: "Scheduled focus",
              footnote: "Apps block themselves for these windows even if Crash Cards is closed. Unlocking during one still works — it just lasts \(manager.unlockMinutes) minutes, and then the window takes over again.") {
            if manager.schedules.isEmpty {
                PanelRow(first: true) {
                    Text("No windows yet. Set one for the hours you mean to study.")
                        .font(.reading(15))
                        .foregroundStyle(Brand.inkFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(Array(manager.schedules.enumerated()), id: \.element.id) { index, schedule in
                    PanelRow(first: index == 0) {
                        scheduleRow(schedule)
                    }
                }
            }
            PanelRow(first: false) {
                PanelAction(title: "Add a window") {
                    editing = FocusSchedule(start: 9 * 60, end: 11 * 60,
                                            days: FocusSchedule.weekdays)
                }
            }
        }
    }

    private func scheduleRow(_ schedule: FocusSchedule) -> some View {
        let running = schedule.isActive(at: Date())
        return HStack(spacing: 12) {
            PixelIcon(glyph: .clock, size: 18,
                      color: running ? Brand.gold : (schedule.enabled ? Brand.inkDim : Brand.inkFaint))

            VStack(alignment: .leading, spacing: 3) {
                Text(schedule.timeText)
                    .font(.brandLabel)
                    .foregroundStyle(schedule.enabled ? Brand.ink : Brand.inkFaint)
                    .monospacedDigit()
                Text(running ? "Blocking now" : schedule.daysText)
                    .font(.reading(12))
                    .foregroundStyle(running ? Brand.gold : Brand.inkFaint)
            }

            Spacer(minLength: 0)

            CrashToggle(label: "", isOn: Binding(
                get: { schedule.enabled },
                set: { manager.setSchedule(schedule, enabled: $0) }))
                .fixedSize()
                .accessibilityLabel("\(schedule.timeText), \(schedule.daysText)")

            Button {
                Haptics.tap()
                manager.removeSchedule(schedule)
            } label: {
                PixelIcon(glyph: .close, size: 12, color: Brand.outline)
                    .frame(width: 34, height: 30)
                    .slab(Brand.mult, radius: 9, lift: 3, highlight: 0.22)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Remove \(schedule.timeText)")
        }
    }

    /// What it costs to get past the shield. Both numbers reach the block screen too.
    private var unlockPanel: some View {
        Panel(title: "Unlock rules",
              footnote: "Answer this many questions correctly and every blocked app opens for this long. Wrong answers don't count against you — the gate just keeps asking.") {
            PanelRow(first: true) {
                CrashStepper(label: "Questions",
                             value: Binding(get: { manager.questionsToUnlock },
                                            set: { manager.questionsToUnlock = $0 }),
                             range: ScreenTimeManager.questionRange)
            }
            PanelRow {
                CrashStepper(label: "Unlocks for",
                             value: Binding(get: { manager.unlockMinutes },
                                            set: { manager.unlockMinutes = $0 }),
                             range: ScreenTimeManager.minuteRange,
                             step: ScreenTimeManager.minuteStep,
                             format: { "\($0) min" })
            }
        }
    }

    /// Apps that hand you to the questions and take you back when you're done.
    private var gatedPanel: some View {
        Panel(title: "Straight to the questions",
              footnote: "Set this up once per app in Shortcuts: Automation → When \(gatedApps.first?.name ?? "an app") is opened → Run Immediately → Open URL, pasted from the row above. Opening that app then jumps here for the questions and back to it when you pass.") {
            ForEach(Array(gatedApps.enumerated()), id: \.element.id) { index, app in
                PanelRow(first: index == 0) {
                    HStack(spacing: 10) {
                        Button { copy(app) } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name)
                                        .font(.brandLabel)
                                        .foregroundStyle(Brand.ink)
                                    Text(copied == app.id ? "Link copied" : app.triggerURL)
                                        .font(.reading(12))
                                        .foregroundStyle(copied == app.id ? Brand.green : Brand.inkFaint)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                PixelIcon(glyph: .copy, size: 16, color: Brand.inkDim)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)

                        Button {
                            Haptics.tap()
                            GatedApps.remove(app)
                            gatedApps = GatedApps.all
                        } label: {
                            PixelIcon(glyph: .close, size: 14, color: Brand.mult)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Remove \(app.name)")
                    }
                }
            }
            PanelRow(first: gatedApps.isEmpty) {
                PanelAction(title: "Add an app") { addingApp = true }
            }
        }
    }

    /// The tokens are rendered by FamilyControls, which only ever draws them its own way.
    private var appsPanel: some View {
        Panel(title: "Blocked apps") {
            let apps = Array(manager.selection.applicationTokens)
            let categories = Array(manager.selection.categoryTokens)

            ForEach(Array(apps.enumerated()), id: \.element) { index, token in
                PanelRow(first: index == 0) {
                    Label(token).font(.reading(15)).foregroundStyle(Brand.ink)
                }
            }
            ForEach(Array(categories.enumerated()), id: \.element) { index, token in
                PanelRow(first: apps.isEmpty && index == 0) {
                    Label(token).font(.reading(15)).foregroundStyle(Brand.ink)
                }
            }
            PanelRow(first: apps.isEmpty && categories.isEmpty) {
                PanelAction(title: manager.hasSelection ? "Change apps" : "Choose apps") {
                    pickerShown = true
                }
            }
        }
    }

    private func copy(_ app: GatedApp) {
        Haptics.tap()
        UIPasteboard.general.string = app.triggerURL
        copied = app.id
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copied == app.id { copied = nil }
        }
    }

    /// Blocked shows the joker, not a padlock: the point isn't that something is locked,
    /// it's *what* is locked. The same card is on the block screen and the app icon.
    private var statusGlyph: PixelGlyph {
        if manager.isShieldActive { return .joker }
        if !manager.isBlocking, manager.nextScheduled != nil { return .clock }
        return .lockOpen
    }
    private var statusColor: Color {
        if manager.isShieldActive { return Brand.gold }
        if manager.isBlocking { return Brand.green }
        return manager.nextScheduled != nil ? Brand.inkDim : Brand.inkFaint
    }

    /// Why the shield is up matters: a scheduled window says so, because the way to end one
    /// is to edit the window, not to look for a switch that isn't on.
    private var statusTitle: String {
        if manager.isShieldActive {
            return manager.activeSchedule != nil ? "Focus window" : "Apps blocked"
        }
        if manager.isUnlockedNow { return "Unlocked" }
        return manager.nextScheduled != nil ? "Focus scheduled" : "Focus off"
    }
    private var statusDetail: String {
        if manager.isShieldActive || manager.isBlocking { return "" }
        if let next = manager.nextScheduled { return "Next window \(nextText(next))" }
        return "Turn on blocking, or schedule the hours you mean to study."
    }

    /// "today at 9:00 AM" / "Mon at 9:00 AM" — enough to tell a schedule was set right.
    private func nextText(_ next: (schedule: FocusSchedule, date: Date)) -> String {
        let calendar = Calendar.current
        let time = FocusSchedule.timeText(next.schedule.start)
        if calendar.isDateInToday(next.date) { return "today at \(time)" }
        if calendar.isDateInTomorrow(next.date) { return "tomorrow at \(time)" }
        let weekday = calendar.component(.weekday, from: next.date)
        return "\(FocusSchedule.dayAbbreviation(weekday)) at \(time)"
    }

    /// Turning blocking on walks the whole setup: permission, then apps, then shield.
    private var blockingBinding: Binding<Bool> {
        Binding(
            get: { manager.isBlocking },
            set: { on in
                guard on else { manager.stopBlocking(); return }
                Task {
                    if !manager.isAuthorized { await manager.requestAuthorization() }
                    guard manager.isAuthorized else { return }
                    if manager.hasSelection {
                        manager.startBlocking()
                    } else {
                        startAfterPicking = true
                        pickerShown = true
                    }
                }
            }
        )
    }

    /// Saving on every edit keeps an active shield in sync with the picker.
    private var pickerBinding: Binding<FamilyActivitySelection> {
        Binding(
            get: { manager.selection },
            set: { newValue in
                manager.selection = newValue
                manager.saveSelection()
                if startAfterPicking, manager.hasSelection {
                    startAfterPicking = false
                    manager.startBlocking()
                }
            }
        )
    }
}
