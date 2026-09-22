import SwiftUI

/// Build one recurring focus window: when it opens, when it closes, and on which days.
///
/// Times are set with steppers rather than a wheel picker — the system picker is the one
/// control that can't be dressed, and hours plus five-minute steps is all a study block ever
/// needs. The window you're describing is spelled out at the top as you change it.
struct ScheduleEditorView: View {
    /// The window being edited, or a fresh one. Seeded by the caller.
    @State var schedule: FocusSchedule
    let onSave: (FocusSchedule) -> Void
    let onClose: () -> Void

    private var tooShort: Bool { schedule.end - schedule.start < FocusSchedule.minimumMinutes }
    private var canSave: Bool { schedule.isValid }

    var body: some View {
        CrashModal(title: "Focus window",
                   confirm: (label: "Save", enabled: canSave, action: save),
                   onCancel: onClose) {
            VStack(spacing: 16) {
                summary
                timesPanel
                daysPanel
            }
        }
    }

    private func save() {
        Haptics.knock()
        onSave(schedule)
        onClose()
    }

    /// The whole window in one line, so the steppers below never have to be read as numbers.
    private var summary: some View {
        VStack(spacing: 8) {
            PixelIcon(glyph: .clock, size: 30, color: Brand.gold)
            Text(schedule.timeText)
                .font(.brandTitle)
                .foregroundStyle(Brand.ink)
                .monospacedDigit()
            Text(schedule.days.isEmpty ? "Pick at least one day"
                                       : "\(schedule.daysText) · \(lengthText)")
                .font(.brandCaption)
                .foregroundStyle(schedule.days.isEmpty ? Brand.mult : Brand.inkDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .slab(Brand.surfaceHigh, radius: Brand.cardRadius)
        .padding(.bottom, Brand.ledge)
    }

    private var timesPanel: some View {
        Panel(title: "When",
              footnote: tooShort
                ? "A window has to run for at least \(FocusSchedule.minimumMinutes) minutes — that's iOS's limit, not ours."
                : "Apps are blocked for this window every week, whether or not the app is open.") {
            PanelRow(first: true) {
                CrashStepper(label: "Starts", value: hour(\.start), range: 0...23,
                             format: { FocusSchedule.timeText($0 * 60) })
            }
            PanelRow {
                CrashStepper(label: "Start minute", value: minute(\.start), range: 0...55,
                             step: 5, format: { String(format: ":%02d", $0) })
            }
            PanelRow {
                CrashStepper(label: "Ends", value: hour(\.end), range: 0...24,
                             format: { FocusSchedule.timeText($0 * 60) })
            }
            PanelRow {
                CrashStepper(label: "End minute", value: minute(\.end), range: 0...55,
                             step: 5, format: { String(format: ":%02d", $0) })
            }
        }
    }

    private var daysPanel: some View {
        Panel(title: "Days") {
            PanelRow(first: true) {
                HStack(spacing: 6) {
                    ForEach(FocusSchedule.ordered(FocusSchedule.everyDay), id: \.self) { day in
                        dayKey(day)
                    }
                }
            }
            PanelRow {
                HStack(spacing: 8) {
                    preset("Every day", FocusSchedule.everyDay)
                    preset("Weekdays", FocusSchedule.weekdays)
                    preset("Weekends", [1, 7])
                }
            }
        }
    }

    private func dayKey(_ day: Int) -> some View {
        let on = schedule.days.contains(day)
        return Button {
            Haptics.select()
            if on { schedule.days.remove(day) } else { schedule.days.insert(day) }
        } label: {
            Text(FocusSchedule.dayAbbreviation(day).prefix(1))
                .font(.brandLabel)
                .foregroundStyle(on ? Brand.outline : Brand.inkDim)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .slab(on ? Brand.gold : Brand.surfaceLedge, radius: 9,
                      lift: on ? 0 : 3, highlight: on ? 0.22 : 0.04)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(dayName(day))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func preset(_ title: String, _ days: Set<Int>) -> some View {
        Button {
            Haptics.select()
            schedule.days = days
        } label: {
            Text(title)
                .font(.brandCaption)
                .foregroundStyle(schedule.days == days ? Brand.outline : Brand.inkDim)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .slab(schedule.days == days ? Brand.gold : Brand.surfaceLedge, radius: 9,
                      lift: schedule.days == days ? 0 : 3)
        }
        .buttonStyle(.pressable)
    }

    private func dayName(_ day: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[(day - 1) % symbols.count]
    }

    private var lengthText: String {
        let total = max(0, schedule.end - schedule.start)
        let hours = total / 60, minutes = total % 60
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    // MARK: - Splitting a minute-of-day into two steppers

    private func hour(_ key: WritableKeyPath<FocusSchedule, Int>) -> Binding<Int> {
        Binding(
            get: { schedule[keyPath: key] / 60 },
            set: { set(key, to: $0 * 60 + schedule[keyPath: key] % 60) })
    }

    private func minute(_ key: WritableKeyPath<FocusSchedule, Int>) -> Binding<Int> {
        Binding(
            get: { schedule[keyPath: key] % 60 },
            set: { set(key, to: (schedule[keyPath: key] / 60) * 60 + $0) })
    }

    /// Midnight is the last minute a window may end on, so 24:30 clamps back to 24:00.
    private func set(_ key: WritableKeyPath<FocusSchedule, Int>, to value: Int) {
        schedule[keyPath: key] = min(value, 24 * 60)
    }
}
