import XCTest
@testable import AnalyticsBar

@MainActor
final class AppPreferencesTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AnalyticsBarTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsAndSelectedPropertyRoundTrip() {
        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.menuBarMetric, .realtimeActiveUsers)
        XCTAssertEqual(preferences.backgroundRefreshInterval, .fiveMinutes)
        XCTAssertEqual(preferences.selectedPropertyResourceNames, [])
        XCTAssertTrue(preferences.showsRevenue)

        preferences.selectedPropertyResourceNames = ["properties/101", "properties/202"]
        preferences.menuBarMetric = .sessionsToday

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.selectedPropertyResourceNames, ["properties/101", "properties/202"])
        XCTAssertEqual(reloaded.menuBarMetric, .sessionsToday)
    }
}
