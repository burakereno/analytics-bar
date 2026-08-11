import XCTest
@testable import AnalyticsBar

final class SevenDayTrendBarMetricsTests: XCTestCase {
    func testOrdinaryScaleUsesActualMaximum() {
        let scale = SevenDayTrendBarScale(values: [1_000, 700, 400, 100])

        XCTAssertEqual(scale.displayMaximumValue, 1_000)
        XCTAssertEqual(scale.actualMaximumValue, 1_000)
        XCTAssertFalse(scale.hasCappedOutlier)
        XCTAssertFalse(scale.isCapped(1_000))
    }

    func testIsolatedOutlierUsesSecondHighestWithHeadroom() {
        let scale = SevenDayTrendBarScale(values: [2_756, 400, 200, 100])

        XCTAssertEqual(scale.displayMaximumValue, 480)
        XCTAssertEqual(scale.actualMaximumValue, 2_756)
        XCTAssertTrue(scale.hasCappedOutlier)
        XCTAssertTrue(scale.isCapped(2_756))
        XCTAssertFalse(scale.isCapped(400))
    }

    func testBarHeightClampsAndKeepsSmallValuesVisible() {
        XCTAssertEqual(
            SevenDayTrendBarMetrics.height(for: 1_000, relativeTo: 1_000),
            SevenDayTrendBarMetrics.maximumHeight
        )
        XCTAssertEqual(
            SevenDayTrendBarMetrics.height(for: 1, relativeTo: 1_000),
            SevenDayTrendBarMetrics.minimumNonzeroHeight
        )
        XCTAssertEqual(
            SevenDayTrendBarMetrics.height(for: 0, relativeTo: 1_000),
            SevenDayTrendBarMetrics.zeroHeight
        )
    }
}
