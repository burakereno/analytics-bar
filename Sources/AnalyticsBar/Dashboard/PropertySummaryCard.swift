import SwiftUI

struct PropertySummaryCard: View {
    let snapshot: PropertyDashboardSnapshot
    let now: Date
    let maximumAge: TimeInterval

    private var current: Bool { snapshot.coreHealth.isCurrent(at: now, maximumAge: maximumAge) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(snapshot.property.displayName)
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                if !current {
                    Label("Unavailable", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10)).foregroundStyle(.orange)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(current ? snapshot.weeklySessions.map(DashboardPresentation.compactNumber) ?? "—" : "—")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("sessions · last 7 days").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if current, let total = snapshot.weeklySessions, let previous = snapshot.previousWeekSessions {
                    Text(DashboardPresentation.weeklyChange(current: total, previous: previous))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(total >= previous ? .green : .orange)
                }
            }
            if !current {
                Text(snapshot.coreHealth.message ?? "Data is out of date. Check the connection.")
                    .font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
                    .help(snapshot.coreHealth.message ?? "Data is out of date")
                if let last = snapshot.coreHealth.lastSuccess {
                    Text("Last success: \(DashboardPresentation.timestamp(last))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .dashboardCard()
    }
}
