import Foundation

enum DashboardPreviewFixtures {
    static func snapshots(named name: String) -> [PropertyDashboardSnapshot]? {
        let count: Int
        switch name {
        case "one", "zero", "expired", "realtime-failed", "login-approval": count = 1
        case "three", "missing-site": count = 3
        case "eight": count = 8
        default: return nil
        }
        return (1...count).map { index in
            var value = snapshot(index: index)
            if name == "zero" {
                value = PropertyDashboardSnapshot(property: value.property, live: .zero, today: .zero,
                    yesterdayThroughSameHour: .zero, sevenDay: value.sevenDay.mapValues { _ in .zero },
                    topPages: [], topSources: [], fetchedAt: Date(), freshness: .live, refreshMessage: nil,
                    todayThroughSameHour: .zero, weeklySessions: 0, previousWeekSessions: 0)
            }
            if name == "expired" {
                let old = ReportStatus.success(at: Date().addingTimeInterval(-86_400 * 31))
                value.coreStatus = old.invalidated(message: "Google authorization expired. Please reconnect.", attemptedAt: Date(), requiresReconnection: true)
                value.realtimeStatus = value.coreStatus
            }
            if name == "realtime-failed" {
                value.realtimeStatus = ReportStatus.success(at: Date().addingTimeInterval(-86_400 * 31))
                    .invalidated(message: "Realtime report could not be read.", attemptedAt: Date())
            }
            return value
        }
    }

    private static func snapshot(index: Int) -> PropertyDashboardSnapshot {
        let property = AnalyticsProperty(
            id: "100\(index)",
            resourceName: "properties/100\(index)",
            accountResourceName: index > 4 ? "accounts/2" : "accounts/1",
            accountDisplayName: index > 4 ? "Work" : "Personal",
            displayName: ["Main Site", "Shop", "Blog", "App", "Docs", "Landing", "Community", "Labs"][index - 1],
            timeZoneIdentifier: "Europe/Istanbul",
            currencyCode: index == 2 ? "USD" : "TRY"
        )
        let active = index * 7
        let today = MetricTotals(
            activeUsers: active * 12,
            sessions: active * 16,
            views: active * 42,
            eventCount: active * 108,
            keyEvents: Decimal(active * 2),
            revenue: index <= 2 ? Decimal(active * 48) : 0
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: property.timeZoneIdentifier) ?? .gmt
        let days = Dictionary(uniqueKeysWithValues: (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset - 7, to: Date())!
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return (
                AnalyticsDay(year: parts.year!, month: parts.month!, day: parts.day!),
                MetricTotals(
                    activeUsers: active * (offset + 5),
                    sessions: active * (offset + 7),
                    views: active * (offset + 14),
                    eventCount: active * (offset + 30),
                    keyEvents: Decimal(active + offset),
                    revenue: 0
                )
            )
        })
        return PropertyDashboardSnapshot(
            property: property,
            live: RealtimeTotals(
                activeUsers: active,
                views: active * 3,
                eventCount: active * 8,
                keyEvents: Decimal(index)
            ),
            today: today,
            yesterdayThroughSameHour: MetricTotals(
                activeUsers: Int(Double(today.activeUsers) * 0.85),
                sessions: Int(Double(today.sessions) * 0.9),
                views: Int(Double(today.views) * 0.88),
                eventCount: Int(Double(today.eventCount) * 0.9),
                keyEvents: today.keyEvents,
                revenue: today.revenue
            ),
            sevenDay: days,
            topPages: [
                RankedDimensionRow(label: "/", value: Decimal(active * 20)),
                RankedDimensionRow(label: "/pricing", value: Decimal(active * 12)),
                RankedDimensionRow(label: "/blog", value: Decimal(active * 8))
            ],
            topSources: [
                RankedDimensionRow(label: "Organic Search", value: Decimal(active * 14)),
                RankedDimensionRow(label: "Direct", value: Decimal(active * 9)),
                RankedDimensionRow(label: "Referral", value: Decimal(active * 4))
            ],
            fetchedAt: Date(),
            freshness: index == 3 ? .stale : .live,
            refreshMessage: index == 3 ? "Using cached data" : nil,
            todayThroughSameHour: today,
            weeklySessions: days.values.reduce(0) { $0 + $1.sessions },
            previousWeekSessions: days.values.reduce(0) { $0 + $1.sessions } * 4 / 5
        )
    }
}
