import XCTest
@testable import AnalyticsBar

final class DashboardPresentationTests: XCTestCase {
    func testWeeklyAndRealtimeSummariesKeepTheirOwnSuccessDates() {
        let now = Date(timeIntervalSince1970: 100_000)
        let old = now.addingTimeInterval(-31 * 86_400)
        let core = DashboardPresentation.reportSummary([.success(at: now), .success(at: now)], now: now, maximumAge: 390)
        let realtime = DashboardPresentation.reportSummary([
            ReportStatus.success(at: old).invalidated(message: "Realtime failed")
        ], now: now, maximumAge: 390)
        XCTAssertEqual(core.status, "Up to date")
        XCTAssertEqual(core.oldestSuccess, now)
        XCTAssertEqual(realtime.status, "Unavailable")
        XCTAssertEqual(realtime.oldestSuccess, old)
        XCTAssertFalse(realtime.isCurrent)
    }

    func testPartialAndMissingReportSummariesDoNotClaimFullFreshness() {
        let now = Date(timeIntervalSince1970: 100_000)
        let missing = ReportStatus(lastSuccess: nil, lastAttempt: now, message: "Failed", verified: false)
        let partial = DashboardPresentation.reportSummary([.success(at: now), missing], now: now, maximumAge: 390)
        XCTAssertEqual(partial.status, "1/2 up to date")
        XCTAssertFalse(partial.isCurrent)
        XCTAssertNil(partial.oldestSuccess)
        XCTAssertFalse(DashboardPresentation.reportSummary([], now: now, maximumAge: 390).isCurrent)
    }

    func testCompactNumbersAndDeltas() {
        XCTAssertEqual(DashboardPresentation.compactNumber(999), "999")
        XCTAssertEqual(DashboardPresentation.compactNumber(1_234), "1.2K")
        XCTAssertEqual(DashboardPresentation.compactNumber(1_500_000), "1.5M")
        XCTAssertEqual(DashboardPresentation.delta(current: 120, previous: 100), "+20%")
        XCTAssertEqual(DashboardPresentation.delta(current: 80, previous: 100), "−20%")
        XCTAssertEqual(DashboardPresentation.delta(current: 10, previous: 0), "—")
    }

    func testRevenueDoesNotMergeCurrencies() {
        XCTAssertEqual(
            DashboardPresentation.revenue(
                .mixed([
                    CurrencyAmount(currencyCode: "TRY", amount: 2_500),
                    CurrencyAmount(currencyCode: "USD", amount: 12)
                ])
            ),
            "TRY 2,500 · USD 12"
        )
    }
}
