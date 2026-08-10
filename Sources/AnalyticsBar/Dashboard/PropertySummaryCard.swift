import SwiftUI

struct PropertySummaryCard: View {
    let snapshot: PropertyDashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.property.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                    Text(snapshot.property.accountDisplayName)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if snapshot.freshness == .stale {
                    Label("Stale", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                } else {
                    Text("\(snapshot.live.activeUsers) live")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 0) {
                metric("Users", snapshot.today.activeUsers, previous: snapshot.yesterdayThroughSameHour.activeUsers)
                metric("Sessions", snapshot.today.sessions, previous: snapshot.yesterdayThroughSameHour.sessions)
                metric("Views", snapshot.today.views, previous: snapshot.yesterdayThroughSameHour.views)
            }
        }
        .dashboardCard()
    }

    private func metric(_ title: String, _ value: Int, previous: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DashboardPresentation.compactNumber(value))
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
            Text(DashboardPresentation.delta(current: value, previous: previous))
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(value >= previous ? .green : .orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
