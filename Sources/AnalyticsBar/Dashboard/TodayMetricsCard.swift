import SwiftUI

struct TodayMetricsCard: View {
    let snapshot: CombinedDashboardSnapshot
    let showsRevenue: Bool
    let now: Date
    let maximumAge: TimeInterval
    private var current: Bool { snapshot.hasCurrentCore(at: now, maximumAge: maximumAge) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("TODAY", systemImage: "calendar")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.orange)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                metric("Users", snapshot.today.activeUsers, snapshot.yesterdayThroughSameHour.activeUsers, compared: snapshot.todayThroughSameHour?.activeUsers)
                metric("Sessions", snapshot.today.sessions, snapshot.yesterdayThroughSameHour.sessions, compared: snapshot.todayThroughSameHour?.sessions)
                metric("Views", snapshot.today.views, snapshot.yesterdayThroughSameHour.views, compared: snapshot.todayThroughSameHour?.views)
                metric("Key events", NSDecimalNumber(decimal: snapshot.today.keyEvents).intValue, NSDecimalNumber(decimal: snapshot.yesterdayThroughSameHour.keyEvents).intValue, compared: snapshot.todayThroughSameHour.map { NSDecimalNumber(decimal: $0.keyEvents).intValue })
            }

            if current, showsRevenue, let revenue = DashboardPresentation.revenue(snapshot.revenue) {
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

            Text(current ? "Latest data reported by Google; daily figures may be delayed." : "Daily data is unavailable. Check report details in Settings.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("Changes compare completed hours with yesterday in each property's time zone.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .dashboardCard()
    }

    private func metric(_ title: String, _ value: Int, _ previous: Int, compared: Int?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(current ? DashboardPresentation.compactNumber(value) : "—")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            Spacer()
            Text(current ? compared.map { DashboardPresentation.delta(current: $0, previous: previous) } ?? "—" : "—")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle((compared ?? 0) >= previous ? Color.green : Color.orange)
        }
    }
}
