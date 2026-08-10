import XCTest
@testable import AnalyticsBar

final class PopoverLayoutTests: XCTestCase {
    func testPreferredHeightFitsMeasuredHeaderAndBody() {
        XCTAssertEqual(
            PopoverLayout.preferredHeight(header: 42, body: 301, dividerCount: 1),
            344
        )
    }

    func testMeasuredHeightClampsToScreenAndMinimum() {
        XCTAssertEqual(
            PopoverLayout.clampedHeight(344, visibleScreenHeight: 900),
            344
        )
        XCTAssertEqual(
            PopoverLayout.clampedHeight(1_200, visibleScreenHeight: 900),
            872
        )
        XCTAssertEqual(
            PopoverLayout.clampedHeight(100, visibleScreenHeight: 900),
            220
        )
    }
}
