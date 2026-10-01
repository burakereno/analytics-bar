import SwiftUI

struct LiveSummaryCard: View {
    let snapshot: CombinedDashboardSnapshot
    let now: Date
    let maximumAge: TimeInterval
    private var current: Bool { snapshot.hasCurrentRealtime(at: now, maximumAge: maximumAge) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(current ? "REALTIME" : "REALTIME UNAVAILABLE", systemImage: current ? "dot.radiowaves.left.and.right" : "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(current ? Color.green : Color.orange)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(current ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text("Last 30 min")
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(current ? Color.green : Color.orange)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(current ? DashboardPresentation.compactNumber(snapshot.live.activeUsers) : "—")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(current ? Color.green : Color.orange)
                Text("active users")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 18) {
                smallMetric("Views", value: snapshot.live.views)
                smallMetric("Events", value: snapshot.live.eventCount)
                smallMetric("Key events", value: NSDecimalNumber(decimal: snapshot.live.keyEvents).intValue)
            }

        }
        .dashboardCard()
    }

    private func smallMetric(_ label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(current ? DashboardPresentation.compactNumber(value) : "—")
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
