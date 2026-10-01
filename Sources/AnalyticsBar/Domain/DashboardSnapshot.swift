import Foundation

struct PropertyCoreReport: Codable, Equatable, Sendable {
    let today: MetricTotals
    let yesterdayThroughSameHour: MetricTotals
    let sevenDay: [AnalyticsDay: MetricTotals]
    let topPages: [RankedDimensionRow]
    let topSources: [RankedDimensionRow]
    var todayThroughSameHour: MetricTotals? = nil
    var weeklySessions: Int? = nil
    var previousWeekSessions: Int? = nil
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
    var realtimeStatus: ReportStatus? = nil
    var coreStatus: ReportStatus? = nil
    var todayThroughSameHour: MetricTotals? = nil
    var weeklySessions: Int? = nil
    var previousWeekSessions: Int? = nil

    var realtimeHealth: ReportStatus {
        realtimeStatus ?? legacyHealth
    }

    var coreHealth: ReportStatus {
        coreStatus ?? legacyHealth
    }

    private var legacyHealth: ReportStatus {
        ReportStatus(lastSuccess: fetchedAt, lastAttempt: fetchedAt,
                     message: refreshMessage, verified: freshness == .live)
    }

    func markedStale(message: String, attemptedAt: Date? = nil) -> Self {
        var copy = self
        copy.realtimeStatus = realtimeHealth.invalidated(message: message, attemptedAt: attemptedAt)
        copy.coreStatus = coreHealth.invalidated(message: message, attemptedAt: attemptedAt)
        return PropertyDashboardSnapshot(
            property: property, live: live, today: today,
            yesterdayThroughSameHour: yesterdayThroughSameHour, sevenDay: sevenDay,
            topPages: topPages, topSources: topSources, fetchedAt: fetchedAt,
            freshness: .stale, refreshMessage: message,
            realtimeStatus: copy.realtimeStatus, coreStatus: copy.coreStatus,
            todayThroughSameHour: todayThroughSameHour,
            weeklySessions: weeklySessions, previousWeekSessions: previousWeekSessions
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

    var weeklySessions: Int? {
        guard properties.allSatisfy({ $0.weeklySessions != nil }) else { return nil }
        return properties.reduce(0) { $0 + ($1.weeklySessions ?? 0) }
    }

    var previousWeekSessions: Int? {
        guard properties.allSatisfy({ $0.previousWeekSessions != nil }) else { return nil }
        return properties.reduce(0) { $0 + ($1.previousWeekSessions ?? 0) }
    }

    var todayThroughSameHour: MetricTotals? {
        guard properties.allSatisfy({ $0.todayThroughSameHour != nil }) else { return nil }
        return properties.reduce(.zero) { $0 + ($1.todayThroughSameHour ?? .zero) }
    }

    func hasCurrentCore(at date: Date, maximumAge: TimeInterval) -> Bool {
        !properties.isEmpty && properties.allSatisfy { $0.coreHealth.isCurrent(at: date, maximumAge: maximumAge) }
    }

    func hasCurrentRealtime(at date: Date, maximumAge: TimeInterval) -> Bool {
        !properties.isEmpty && properties.allSatisfy { $0.realtimeHealth.isCurrent(at: date, maximumAge: maximumAge) }
    }

    func markedStale(message: String, attemptedAt: Date? = nil) -> Self {
        DashboardAggregator.aggregate(properties.map { $0.markedStale(message: message, attemptedAt: attemptedAt) })
    }
}
