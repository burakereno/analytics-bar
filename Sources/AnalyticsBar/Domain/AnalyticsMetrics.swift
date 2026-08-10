import Foundation

struct MetricTotals: Codable, Equatable, Sendable {
    var activeUsers: Int
    var sessions: Int
    var views: Int
    var eventCount: Int
    var keyEvents: Decimal
    var revenue: Decimal

    static let zero = MetricTotals(
        activeUsers: 0,
        sessions: 0,
        views: 0,
        eventCount: 0,
        keyEvents: 0,
        revenue: 0
    )

    static func + (lhs: Self, rhs: Self) -> Self {
        MetricTotals(
            activeUsers: lhs.activeUsers + rhs.activeUsers,
            sessions: lhs.sessions + rhs.sessions,
            views: lhs.views + rhs.views,
            eventCount: lhs.eventCount + rhs.eventCount,
            keyEvents: lhs.keyEvents + rhs.keyEvents,
            revenue: lhs.revenue + rhs.revenue
        )
    }
}

struct RealtimeTotals: Codable, Equatable, Sendable {
    var activeUsers: Int
    var views: Int
    var eventCount: Int
    var keyEvents: Decimal

    static let zero = RealtimeTotals(activeUsers: 0, views: 0, eventCount: 0, keyEvents: 0)

    static func + (lhs: Self, rhs: Self) -> Self {
        RealtimeTotals(
            activeUsers: lhs.activeUsers + rhs.activeUsers,
            views: lhs.views + rhs.views,
            eventCount: lhs.eventCount + rhs.eventCount,
            keyEvents: lhs.keyEvents + rhs.keyEvents
        )
    }
}

struct RankedDimensionRow: Codable, Equatable, Identifiable, Sendable {
    let label: String
    let value: Decimal

    var id: String { label }
}

struct CurrencyAmount: Codable, Equatable, Identifiable, Sendable {
    let currencyCode: String
    let amount: Decimal

    var id: String { currencyCode }
}

enum RevenueSummary: Codable, Equatable, Sendable {
    case none
    case single(currencyCode: String, amount: Decimal)
    case mixed([CurrencyAmount])
}
