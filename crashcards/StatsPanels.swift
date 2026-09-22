import SwiftUI

/// The Settings read-out of `StatsStore`: what you've done today, and what you've done
/// since you started. Both graded modes feed it — quiz sessions and gate questions alike.
struct StatsPanels: View {
    @Environment(StatsStore.self) private var stats

    var body: some View {
        VStack(spacing: 16) {
            todayPanel
            lifetimePanel
        }
    }

    private var todayPanel: some View {
        Panel(title: "Today", footnote: "The last 30 days, today on the right.") {
            PanelRow(first: true) {
                StatRow(label: "Answered", value: "\(stats.today.answered)")
            }
            PanelRow {
                StatRow(label: "Correct", value: "\(stats.today.correct)")
            }
            PanelRow {
                StatRow(label: "Accuracy",
                        value: Self.percent(StatsStore.percent(stats.today.correct,
                                                               of: stats.today.answered)))
            }
            PanelRow {
                ActivityStrip(days: stats.recent(30))
            }
        }
    }

    private var lifetimePanel: some View {
        Panel(title: "Lifetime") {
            PanelRow(first: true) {
                StatRow(label: "Questions answered", value: "\(stats.totalAnswered)")
            }
            PanelRow {
                StatRow(label: "Accuracy", value: Self.percent(stats.accuracy))
            }
            PanelRow {
                StatRow(label: "Time studied", value: Self.duration(stats.totalSeconds))
            }
            PanelRow {
                StatRow(label: "Sessions", value: "\(stats.totalSessions)")
            }
            PanelRow {
                StatRow(label: "Unlocks earned", value: "\(stats.totalUnlocks)")
            }
            PanelRow {
                StatRow(label: "Day streak", value: Self.days(stats.dayStreak))
            }
            PanelRow {
                StatRow(label: "Longest streak", value: Self.days(stats.longestDayStreak))
            }
        }
    }

    // MARK: - Formatting

    /// An em dash rather than 0%, so a figure nothing has been measured for doesn't read
    /// as a bad one.
    private static func percent(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value)%"
    }

    private static func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }

    private static func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        guard minutes >= 60 else { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

/// Thirty days as one row of blocks: the more you answered that day, the brighter it burns.
/// Days you didn't study are left as empty sockets rather than skipped, so a gap looks like
/// a gap.
private struct ActivityStrip: View {
    let days: [DayStats?]

    /// The busiest day sets the top of the scale, so the row reads against your own habit
    /// rather than some fixed idea of a good day.
    private var busiest: Int { max(days.compactMap { $0?.answered }.max() ?? 0, 1) }

    private var studied: Int { days.compactMap { $0 }.filter { $0.answered > 0 }.count }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                Rectangle()
                    .fill(fill(day))
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("Studied \(studied) of the last \(days.count) days")
    }

    private func fill(_ day: DayStats?) -> Color {
        guard let day, day.answered > 0 else { return Brand.outline.opacity(0.55) }
        return Brand.green.opacity(0.35 + 0.65 * Double(day.answered) / Double(busiest))
    }
}
