import Foundation
import XCTest
@testable import AnalyticsBar

@MainActor
final class DashboardModelTests: XCTestCase {
    func testConnectionIssueDistinguishesCancellationConfigurationAndPermission() {
        XCTAssertEqual(
            DashboardModel.ConnectionIssue(error: GoogleOAuthError.cancelled),
            .cancelled("Google authorization was cancelled.")
        )
        XCTAssertEqual(
            DashboardModel.ConnectionIssue(error: GoogleOAuthError.configurationMissing),
            .configuration("Google OAuth client configuration is missing.")
        )
        XCTAssertEqual(
            DashboardModel.ConnectionIssue(error: GoogleAPIError.permissionDenied),
            .permission("This Google account cannot read the selected Analytics property.")
        )
    }

    func testConnectSelectAndRefreshTransitionsToLoaded() async {
        let defaults = UserDefaults(suiteName: "DashboardModelTests.\(UUID().uuidString)")!
        let preferences = AppPreferences(defaults: defaults)
        let repository = DashboardModelRepository()
        let scheduler = RefreshScheduler()
        let model = DashboardModel(repository: repository, preferences: preferences, scheduler: scheduler)

        await model.connect()
        guard case let .selectingProperties(properties) = model.state else {
            return XCTFail("Expected property selection")
        }
        XCTAssertEqual(properties.map(\.id), ["1", "2"])

        await model.confirmSelection(["properties/1", "properties/2"])

        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.snapshot?.live.activeUsers, 3)
        XCTAssertEqual(preferences.selectedPropertyResourceNames, ["properties/1", "properties/2"])
    }

    func testAutomaticFailurePreservesLoadedSnapshotAndManualFailureIsVisible() async {
        let defaults = UserDefaults(suiteName: "DashboardModelTests.\(UUID().uuidString)")!
        let preferences = AppPreferences(defaults: defaults)
        let repository = DashboardModelRepository()
        let model = DashboardModel(
            repository: repository,
            preferences: preferences,
            scheduler: RefreshScheduler()
        )
        await model.connect()
        await model.confirmSelection(["properties/1"])
        await repository.setFailsRefresh(true)

        await model.refresh(trigger: .backgroundTimer)
        XCTAssertEqual(model.state, .loaded)
        XCTAssertNil(model.lastManualError)

        await model.refresh(trigger: .manual)
        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.lastManualError, "Refresh failed")
    }
}

private actor DashboardModelRepository: AnalyticsRepositoryProtocol {
    private var failsRefresh = false

    func setFailsRefresh(_ value: Bool) { failsRefresh = value }
    func hasStoredAuthorization() async -> Bool { false }
    func connect() async throws -> [AnalyticsProperty] {
        [TestAnalyticsFixtures.property("1"), TestAnalyticsFixtures.property("2")]
    }
    func availableProperties() async throws -> [AnalyticsProperty] {
        [TestAnalyticsFixtures.property("1"), TestAnalyticsFixtures.property("2")]
    }
    func refreshSelectedProperties(
        _ properties: [AnalyticsProperty],
        trigger: RefreshTrigger,
        now: Date
    ) async throws -> CombinedDashboardSnapshot {
        if failsRefresh { throw TestModelError.failed }
        return DashboardAggregator.aggregate(
            properties.map { TestAnalyticsFixtures.snapshot($0.id, activeUsers: Int($0.id) ?? 0) }
        )
    }
    func cachedSnapshot(resourceNames: [String]?) async -> CombinedDashboardSnapshot? { nil }
    func disconnect() async throws {}
}

private enum TestModelError: Error, LocalizedError {
    case failed
    var errorDescription: String? { "Refresh failed" }
}
