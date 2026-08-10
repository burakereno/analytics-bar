import Foundation

enum DashboardAggregator {
    static let userCountingDisclosure = "Property total; users may overlap across properties"

    static func aggregate(_ snapshots: [PropertyDashboardSnapshot]) -> CombinedDashboardSnapshot {
        let live = snapshots.reduce(.zero) { $0 + $1.live }
        let today = snapshots.reduce(.zero) { $0 + $1.today }
        let yesterday = snapshots.reduce(.zero) { $0 + $1.yesterdayThroughSameHour }
        let fetchedAt = snapshots.map(\.fetchedAt).max() ?? .distantPast

        var sevenDay: [AnalyticsDay: MetricTotals] = [:]
        for snapshot in snapshots {
            for (day, totals) in snapshot.sevenDay {
                sevenDay[day] = (sevenDay[day] ?? .zero) + totals
            }
        }

        return CombinedDashboardSnapshot(
            properties: snapshots,
            live: live,
            today: today,
            yesterdayThroughSameHour: yesterday,
            sevenDay: sevenDay,
            revenue: revenueSummary(for: snapshots),
            userCountingDisclosure: userCountingDisclosure,
            fetchedAt: fetchedAt
        )
    }

    private static func revenueSummary(for snapshots: [PropertyDashboardSnapshot]) -> RevenueSummary {
        var amounts: [String: Decimal] = [:]
        for snapshot in snapshots where snapshot.today.revenue != 0 {
            amounts[snapshot.property.currencyCode, default: 0] += snapshot.today.revenue
        }

        let values = amounts
            .map { CurrencyAmount(currencyCode: $0.key, amount: $0.value) }
            .sorted { $0.currencyCode < $1.currencyCode }

        switch values.count {
        case 0:
            return .none
        case 1:
            return .single(currencyCode: values[0].currencyCode, amount: values[0].amount)
        default:
            return .mixed(values)
        }
    }
}
