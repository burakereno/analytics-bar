import Foundation
@testable import AnalyticsBar

enum TestAnalyticsFixtures {
    static func property(_ id: String, currency: String = "USD") -> AnalyticsProperty {
        AnalyticsProperty(
            id: id,
            resourceName: "properties/\(id)",
            accountResourceName: "accounts/1",
            accountDisplayName: "Personal",
            displayName: "Property \(id)",
            timeZoneIdentifier: "Europe/Istanbul",
            currencyCode: currency
        )
    }

    static func core(activeUsers: Int) -> PropertyCoreReport {
        let totals = MetricTotals(
            activeUsers: activeUsers,
            sessions: activeUsers * 2,
            views: activeUsers * 3,
            eventCount: activeUsers * 4,
            keyEvents: Decimal(activeUsers),
            revenue: 0
        )
        return PropertyCoreReport(
            today: totals,
            yesterdayThroughSameHour: .zero,
            sevenDay: [AnalyticsDay(year: 2026, month: 8, day: 10): totals],
            topPages: [],
            topSources: [], todayThroughSameHour: totals,
            weeklySessions: totals.sessions, previousWeekSessions: totals.sessions / 2
        )
    }

    static func snapshot(_ id: String, activeUsers: Int, freshness: PropertyDashboardSnapshot.Freshness = .live) -> PropertyDashboardSnapshot {
        let property = property(id)
        let core = core(activeUsers: activeUsers)
        return PropertyDashboardSnapshot(
            property: property,
            live: RealtimeTotals(activeUsers: activeUsers, views: 0, eventCount: 0, keyEvents: 0),
            today: core.today,
            yesterdayThroughSameHour: core.yesterdayThroughSameHour,
            sevenDay: core.sevenDay,
            topPages: [],
            topSources: [],
            fetchedAt: Date(timeIntervalSince1970: 1_000),
            freshness: freshness,
            refreshMessage: nil, todayThroughSameHour: core.todayThroughSameHour,
            weeklySessions: core.weeklySessions, previousWeekSessions: core.previousWeekSessions
        )
    }
}
