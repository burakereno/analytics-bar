import SwiftUI

struct LiveSummaryCard: View {
    let snapshot: CombinedDashboardSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.green)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Last 30 min")
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.green)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(DashboardPresentation.compactNumber(snapshot.live.activeUsers))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
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

            Text(snapshot.userCountingDisclosure)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .dashboardCard()
    }

    private func smallMetric(_ label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DashboardPresentation.compactNumber(value))
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
