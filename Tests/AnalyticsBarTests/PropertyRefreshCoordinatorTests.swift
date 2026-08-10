import Foundation
import XCTest
@testable import AnalyticsBar

final class PropertyRefreshCoordinatorTests: XCTestCase {
    func testLimitsPropertyConcurrencyToThreeAndPreservesOrder() async throws {
        let dataClient = InstrumentedAnalyticsDataClient()
        let coordinator = PropertyRefreshCoordinator(dataClient: dataClient, maximumConcurrency: 3)
        let properties = (1...6).map { TestAnalyticsFixtures.property("\($0)") }

        let outcomes = await coordinator.refresh(
            properties: properties,
            accessToken: "access",
            now: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(outcomes.map(\.property.id), ["1", "2", "3", "4", "5", "6"])
        let maximumActiveProperties = await dataClient.maximumActiveProperties
        XCTAssertEqual(maximumActiveProperties, 3)
    }
}

private actor InstrumentedAnalyticsDataClient: AnalyticsDataClientProtocol {
    private var activeProperties = Set<String>()
    private(set) var maximumActiveProperties = 0

    func fetchRealtime(property: AnalyticsProperty, accessToken: String) async throws -> RealtimeTotals {
        activeProperties.insert(property.id)
        maximumActiveProperties = max(maximumActiveProperties, activeProperties.count)
        try? await Task.sleep(for: .milliseconds(20))
        activeProperties.remove(property.id)
        return RealtimeTotals(activeUsers: Int(property.id) ?? 0, views: 0, eventCount: 0, keyEvents: 0)
    }

    func fetchCore(property: AnalyticsProperty, now: Date, accessToken: String) async throws -> PropertyCoreReport {
        try? await Task.sleep(for: .milliseconds(10))
        return TestAnalyticsFixtures.core(activeUsers: Int(property.id) ?? 0)
    }
}
