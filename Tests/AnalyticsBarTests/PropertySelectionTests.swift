import XCTest
@testable import AnalyticsBar

final class PropertySelectionTests: XCTestCase {
    func testToggleSelectAllAndFilterPreservePropertyOrder() {
        let properties = [
            TestAnalyticsFixtures.property("1"),
            TestAnalyticsFixtures.property("2"),
            AnalyticsProperty(
                id: "3",
                resourceName: "properties/3",
                accountResourceName: "accounts/2",
                accountDisplayName: "Work",
                displayName: "Shop",
                timeZoneIdentifier: "Europe/Istanbul",
                currencyCode: "TRY"
            )
        ]
        var selection = PropertySelection(properties: properties, selectedResourceNames: [])

        selection.toggle("properties/2")
        selection.toggle("properties/1")
        XCTAssertEqual(selection.selectedResourceNames, ["properties/1", "properties/2"])

        selection.selectAll(accountResourceName: "accounts/2")
        XCTAssertEqual(selection.selectedResourceNames, ["properties/1", "properties/2", "properties/3"])
        XCTAssertEqual(selection.filtered(query: "shop").map(\.id), ["3"])

        selection.clearAll()
        XCTAssertEqual(selection.selectedResourceNames, [])
    }
}
