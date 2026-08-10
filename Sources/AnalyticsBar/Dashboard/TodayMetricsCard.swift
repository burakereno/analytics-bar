import SwiftUI

struct TodayMetricsCard: View {
    let snapshot: CombinedDashboardSnapshot
    let showsRevenue: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("TODAY", systemImage: "calendar")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.orange)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                metric("Users", snapshot.today.activeUsers, snapshot.yesterdayThroughSameHour.activeUsers)
                metric("Sessions", snapshot.today.sessions, snapshot.yesterdayThroughSameHour.sessions)
                metric("Views", snapshot.today.views, snapshot.yesterdayThroughSameHour.views)
                metric("Key events", NSDecimalNumber(decimal: snapshot.today.keyEvents).intValue, NSDecimalNumber(decimal: snapshot.yesterdayThroughSameHour.keyEvents).intValue)
            }

            if showsRevenue, let revenue = DashboardPresentation.revenue(snapshot.revenue) {
                Divider().opacity(0.35)
                HStack {
                    Text("Revenue")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(revenue)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
            }

            Text("Compared with yesterday through the same completed property-local hour")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .dashboardCard()
    }

    private func metric(_ title: String, _ current: Int, _ previous: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(DashboardPresentation.compactNumber(current))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            Spacer()
            Text(DashboardPresentation.delta(current: current, previous: previous))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(current >= previous ? .green : .orange)
        }
    }
}
