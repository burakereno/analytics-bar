import Foundation

struct PropertyCoreReport: Codable, Equatable, Sendable {
    let today: MetricTotals
    let yesterdayThroughSameHour: MetricTotals
    let sevenDay: [AnalyticsDay: MetricTotals]
    let topPages: [RankedDimensionRow]
    let topSources: [RankedDimensionRow]
}

struct PropertyDashboardSnapshot: Codable, Identifiable, Equatable, Sendable {
    enum Freshness: String, Codable, Sendable {
        case live
        case stale
    }

    var id: String { property.id }

    let property: AnalyticsProperty
    let live: RealtimeTotals
    let today: MetricTotals
    let yesterdayThroughSameHour: MetricTotals
    let sevenDay: [AnalyticsDay: MetricTotals]
    let topPages: [RankedDimensionRow]
    let topSources: [RankedDimensionRow]
    let fetchedAt: Date
    let freshness: Freshness
    let refreshMessage: String?

    func markedStale(message: String) -> Self {
        PropertyDashboardSnapshot(
            property: property,
            live: live,
            today: today,
            yesterdayThroughSameHour: yesterdayThroughSameHour,
            sevenDay: sevenDay,
            topPages: topPages,
            topSources: topSources,
            fetchedAt: fetchedAt,
            freshness: .stale,
            refreshMessage: message
        )
    }
}

struct CombinedDashboardSnapshot: Codable, Equatable, Sendable {
    let properties: [PropertyDashboardSnapshot]
    let live: RealtimeTotals
    let today: MetricTotals
    let yesterdayThroughSameHour: MetricTotals
    let sevenDay: [AnalyticsDay: MetricTotals]
    let revenue: RevenueSummary
    let userCountingDisclosure: String
    let fetchedAt: Date
}
