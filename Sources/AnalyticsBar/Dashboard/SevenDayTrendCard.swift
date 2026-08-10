import Charts
import SwiftUI

struct SevenDayTrendCard: View {
    enum TrendMetric: String, CaseIterable, Identifiable {
        case users = "Users"
        case sessions = "Sessions"
        case views = "Views"
        var id: String { rawValue }
    }

    let snapshot: CombinedDashboardSnapshot
    @State private var metric: TrendMetric = .sessions

    private var points: [(AnalyticsDay, Int)] {
        snapshot.sevenDay.keys.sorted().map { day in
            let totals = snapshot.sevenDay[day] ?? .zero
            let value: Int
            switch metric {
            case .users: value = totals.activeUsers
            case .sessions: value = totals.sessions
            case .views: value = totals.views
            }
            return (day, value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("LAST 7 DAYS", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.orange)
                Spacer()
                Picker("Metric", selection: $metric) {
                    ForEach(TrendMetric.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 178)
                .controlSize(.mini)
            }

            Chart(points, id: \.0) { day, value in
                BarMark(
                    x: .value("Day", day.gaValue),
                    y: .value(metric.rawValue, value)
                )
                .foregroundStyle(.orange.gradient)
                .cornerRadius(3)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 105)

            Text("Each property uses its Analytics reporting time zone")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .dashboardCard()
    }
}
