import XCTest
@testable import AnalyticsBar

final class RefreshSchedulerTests: XCTestCase {
    func testOpenPopoverAlwaysUsesSixtySeconds() {
        XCTAssertEqual(
            RefreshScheduler.nextInterval(isPopoverOpen: true, background: .thirtyMinutes),
            60
        )
    }

    func testClosedPopoverUsesPreference() {
        XCTAssertEqual(
            RefreshScheduler.nextInterval(isPopoverOpen: false, background: .fiveMinutes),
            300
        )
        XCTAssertEqual(
            RefreshScheduler.nextInterval(isPopoverOpen: false, background: .fifteenMinutes),
            900
        )
    }
}
