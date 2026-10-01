import XCTest
@testable import AnalyticsBar

final class DashboardAggregatorTests: XCTestCase {
    func testAggregatesPropertySumsWithoutClaimingUniqueUsers() throws {
        let first = try snapshot(
            property: property(id: "101", currency: "USD"),
            activeUsers: 10,
            sessions: 5,
            revenue: 12,
            day: "20260809"
        )
        let second = try snapshot(
            property: property(id: "202", currency: "USD"),
            activeUsers: 20,
            sessions: 7,
            revenue: 8,
            day: "20260809"
        )

        let combined = DashboardAggregator.aggregate([first, second])

        XCTAssertEqual(combined.live.activeUsers, 30)
        XCTAssertEqual(combined.today.sessions, 12)
        XCTAssertEqual(combined.properties.map(\.id), ["101", "202"])
        XCTAssertEqual(
            combined.userCountingDisclosure,
            "Property total; users may overlap across properties"
        )
        XCTAssertEqual(combined.revenue, .single(currencyCode: "USD", amount: 20))
        XCTAssertEqual(combined.sevenDay[try AnalyticsDay(gaValue: "20260809")]?.sessions, 12)
    }

    func testKeepsMixedCurrenciesSeparate() throws {
        let usd = try snapshot(
            property: property(id: "101", currency: "USD"),
            activeUsers: 1,
            sessions: 2,
            revenue: 12,
            day: "20260809"
        )
        let tryProperty = try snapshot(
            property: property(id: "202", currency: "TRY"),
            activeUsers: 3,
            sessions: 4,
            revenue: 2_500,
            day: "20260809"
        )

        let combined = DashboardAggregator.aggregate([usd, tryProperty])

        XCTAssertEqual(
            combined.revenue,
            .mixed([
                CurrencyAmount(currencyCode: "TRY", amount: 2_500),
                CurrencyAmount(currencyCode: "USD", amount: 12)
            ])
        )
    }

    func testZeroRevenueRetainsItsCurrencyForTheRevenuePreference() throws {
        let value = try snapshot(
            property: property(id: "101", currency: "USD"),
            activeUsers: 1,
            sessions: 2,
            revenue: 0,
            day: "20260809"
        )

        XCTAssertEqual(DashboardAggregator.aggregate([value]).revenue, .single(currencyCode: "USD", amount: 0))
    }

    func testZeroRevenueInDifferentCurrenciesIsNotCombined() throws {
        let first = try snapshot(property: property(id: "1", currency: "USD"), activeUsers: 0,
                                 sessions: 0, revenue: 0, day: "20260930")
        let second = try snapshot(property: property(id: "2", currency: "TRY"), activeUsers: 0,
                                  sessions: 0, revenue: 0, day: "20260930")
        XCTAssertEqual(DashboardAggregator.aggregate([first, second]).revenue, .mixed([
            CurrencyAmount(currencyCode: "TRY", amount: 0), CurrencyAmount(currencyCode: "USD", amount: 0)
        ]))
    }

    private func property(id: String, currency: String) -> AnalyticsProperty {
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

    private func snapshot(
        property: AnalyticsProperty,
        activeUsers: Int,
        sessions: Int,
        revenue: Decimal,
        day: String
    ) throws -> PropertyDashboardSnapshot {
        let totals = MetricTotals(
            activeUsers: activeUsers,
            sessions: sessions,
            views: sessions * 2,
            eventCount: sessions * 3,
            keyEvents: Decimal(sessions),
            revenue: revenue
        )
        return PropertyDashboardSnapshot(
            property: property,
            live: RealtimeTotals(
                activeUsers: activeUsers,
                views: sessions * 2,
                eventCount: sessions * 3,
                keyEvents: Decimal(sessions)
            ),
            today: totals,
            yesterdayThroughSameHour: .zero,
            sevenDay: [try AnalyticsDay(gaValue: day): totals],
            topPages: [],
            topSources: [],
            fetchedAt: Date(timeIntervalSince1970: 1_786_291_200),
            freshness: .live,
            refreshMessage: nil
        )
    }
}
