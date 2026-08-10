import XCTest
@testable import AnalyticsBar

final class MenuBarRendererTests: XCTestCase {
    func testDerivesConfiguredMetricAndRetainsStaleValue() {
        let snapshot = DashboardAggregator.aggregate([
            TestAnalyticsFixtures.snapshot("1", activeUsers: 12),
            TestAnalyticsFixtures.snapshot("2", activeUsers: 8, freshness: .stale)
        ])

        XCTAssertEqual(
            MenuBarRenderer.title(snapshot: snapshot, metric: .realtimeActiveUsers).value,
            "20"
        )
        XCTAssertEqual(
            MenuBarRenderer.title(snapshot: snapshot, metric: .sessionsToday).value,
            "40"
        )
        XCTAssertNil(MenuBarRenderer.title(snapshot: snapshot, metric: .iconOnly).value)
        XCTAssertEqual(
            MenuBarRenderer.title(snapshot: nil, metric: .realtimeActiveUsers).value,
            "--"
        )
    }
}
