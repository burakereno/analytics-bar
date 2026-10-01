import XCTest
@testable import AnalyticsBar

final class MenuBarRendererTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testCurrentWeeklySessionsAreThePrimaryMetric() {
        let snapshot = DashboardAggregator.aggregate([TestAnalyticsFixtures.snapshot("1", activeUsers: 12)])
        let title = MenuBarRenderer.title(snapshot: snapshot, metric: .sessionsLast7Days, now: now)
        XCTAssertEqual(title.value, "24")
        XCTAssertFalse(title.warning)
    }

    func testStaleMissingAndAgedDataNeverAppearAsVerifiedNumbers() {
        let stale = DashboardAggregator.aggregate([TestAnalyticsFixtures.snapshot("1", activeUsers: 12, freshness: .stale)])
        XCTAssertEqual(MenuBarRenderer.title(snapshot: stale, metric: .sessionsLast7Days, now: now).value, "—")
        XCTAssertTrue(MenuBarRenderer.title(snapshot: stale, metric: .sessionsLast7Days, now: now).warning)
        XCTAssertEqual(MenuBarRenderer.title(snapshot: nil, metric: .usersToday, now: now).value, "—")
        let fresh = DashboardAggregator.aggregate([TestAnalyticsFixtures.snapshot("1", activeUsers: 12)])
        XCTAssertEqual(MenuBarRenderer.title(snapshot: fresh, metric: .usersToday, now: now.addingTimeInterval(400)).value, "—")
        XCTAssertEqual(MenuBarRenderer.title(snapshot: fresh, metric: .usersToday, now: now, connectionError: "Offline").value, "—")
    }

    func testSuccessfulZeroDiffersFromUnavailableAndIconOnlyStillWarns() {
        let zero = DashboardAggregator.aggregate([TestAnalyticsFixtures.snapshot("1", activeUsers: 0)])
        let title = MenuBarRenderer.title(snapshot: zero, metric: .realtimeActiveUsers, now: now)
        XCTAssertEqual(title.value, "0")
        XCTAssertFalse(title.warning)
        let icon = MenuBarRenderer.title(snapshot: nil, metric: .iconOnly, now: now)
        XCTAssertNil(icon.value)
        XCTAssertTrue(icon.warning)
    }

    func testFailedRealtimeDoesNotHideSuccessfulWeeklySessions() {
        var property = TestAnalyticsFixtures.snapshot("1", activeUsers: 3)
        property.realtimeStatus = ReportStatus.success(at: now).invalidated(message: "Realtime failed")
        let snapshot = DashboardAggregator.aggregate([property])
        let title = MenuBarRenderer.title(snapshot: snapshot, metric: .sessionsLast7Days, now: now)
        XCTAssertEqual(title.value, "6")
        XCTAssertTrue(title.warning)
        XCTAssertEqual(MenuBarRenderer.title(snapshot: snapshot, metric: .realtimeActiveUsers, now: now).value, "—")
    }
}
