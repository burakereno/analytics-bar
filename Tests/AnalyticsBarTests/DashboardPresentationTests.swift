import XCTest
@testable import AnalyticsBar

final class DashboardPresentationTests: XCTestCase {
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
