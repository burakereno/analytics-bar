import SwiftUI

struct WeeklySummaryCard: View {
    let snapshot: CombinedDashboardSnapshot
    let now: Date
    let maximumAge: TimeInterval

    private var current: Bool { snapshot.hasCurrentCore(at: now, maximumAge: maximumAge) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("LAST 7 COMPLETE DAYS", systemImage: "calendar")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.orange)
            HStack(alignment: .firstTextBaseline) {
                Text(current ? snapshot.weeklySessions.map(DashboardPresentation.compactNumber) ?? "—" : "—")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("sessions").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if current, let total = snapshot.weeklySessions, let previous = snapshot.previousWeekSessions {
                    Text(DashboardPresentation.weeklyChange(current: total, previous: previous))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(total >= previous ? .green : .orange)
                }
            }
            if current, let previous = snapshot.previousWeekSessions {
                Text("\(DashboardPresentation.compactNumber(previous)) in the previous week")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("Current weekly data is unavailable. Check the connection in Settings.")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }
            if current, snapshot.weeklySessions == 0 {
                Text("No sessions reported in this period.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .dashboardCard()
    }
}
