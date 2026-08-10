import XCTest
@testable import AnalyticsBar

final class AppConfigurationTests: XCTestCase {
    func testProductionIdentityIsStable() {
        XCTAssertEqual(AppConfiguration.appName, "Analytics Bar")
        XCTAssertEqual(AppConfiguration.bundleIdentifier, "com.burakerenoglu.AnalyticsBar")
        XCTAssertEqual(AppConfiguration.githubOwner, "burakereno")
        XCTAssertEqual(AppConfiguration.githubRepo, "analytics-bar")
        XCTAssertEqual(AppConfiguration.teamIdentifier, "66K3EFBVB6")
        XCTAssertEqual(AppConfiguration.dmgAssetName, "AnalyticsBar.dmg")
    }
}
