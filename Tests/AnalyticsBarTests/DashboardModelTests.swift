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
    func testStartupDiscoveryFailureInvalidatesCacheAndRecoversOnNextTick() async {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.selectedPropertyResourceNames = ["properties/1"]
        let repository = DashboardModelRepository()
        await repository.setDiscoveryFails(true)
        let scheduler = RefreshScheduler()
        let model = DashboardModel(repository: repository, preferences: preferences, scheduler: scheduler)
        await model.bootstrap()
        XCTAssertEqual(model.state, .loaded)
        XCTAssertNotNil(model.connectionError)
        XCTAssertEqual(model.snapshot?.properties.first?.freshness, .stale)
        await repository.setDiscoveryFails(false)
        await model.refresh(trigger: .backgroundTimer)
        XCTAssertNil(model.connectionError)
        XCTAssertEqual(model.snapshot?.properties.first?.freshness, .live)
        scheduler.stop()
    }

    func testExpiredAuthorizationIsVisibleEvenWithLoadedData() async {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.selectedPropertyResourceNames = ["properties/1"]
        let repository = DashboardModelRepository()
        let scheduler = RefreshScheduler()
        let model = DashboardModel(repository: repository, preferences: preferences, scheduler: scheduler)
        await model.bootstrap()
        await repository.setAuthorizationExpired()
        await model.refresh(trigger: .backgroundTimer)
        XCTAssertTrue(model.needsReconnection)
        XCTAssertNotNil(model.connectionError)
        XCTAssertEqual(model.snapshot?.properties.first?.freshness, .stale)
        scheduler.stop()
    }

    func testMissingAuthorizationDoesNotPresentCacheAsConnected() async {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.selectedPropertyResourceNames = ["properties/1"]
        let repository = DashboardModelRepository()
        await repository.setHasAuthorization(false)
        let model = DashboardModel(repository: repository, preferences: preferences, scheduler: RefreshScheduler())
        await model.bootstrap()
        XCTAssertTrue(model.needsReconnection)
        XCTAssertEqual(model.snapshot?.properties.first?.freshness, .stale)
    }

    func testSelectionChangedDuringRefreshEventuallyLoadsTheNewProperty() async throws {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let repository = DashboardModelRepository()
        let scheduler = RefreshScheduler()
        defer { scheduler.stop() }
        let model = DashboardModel(repository: repository, preferences: preferences, scheduler: scheduler)
        await model.connect()
        await model.confirmSelection(["properties/1"])
        await repository.setRefreshDelay(600)
        let ongoing = Task { await model.refresh(trigger: .backgroundTimer) }
        while !model.isRefreshing { await Task.yield() }
        model.updateSelection(["properties/2"])
        XCTAssertNil(model.snapshot, "The old selection must disappear immediately")
        await ongoing.value
        let deadline = Date().addingTimeInterval(3)
        while model.snapshot?.properties.map(\.id) != ["2"] && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.snapshot?.properties.map(\.id), ["2"])
        XCTAssertEqual(model.state, .loaded)
    }

}

private actor DashboardModelRepository: AnalyticsRepositoryProtocol {
    private var failsRefresh = false
    private var discoveryFails = false
    private var authorizationExpired = false
    private var hasAuthorization = true
    private var refreshDelay = 0
    func setRefreshDelay(_ milliseconds: Int) { refreshDelay = milliseconds }
    func setDiscoveryFails(_ value: Bool) { discoveryFails = value }
    func setAuthorizationExpired() { authorizationExpired = true }
    func setHasAuthorization(_ value: Bool) { hasAuthorization = value }

    func setFailsRefresh(_ value: Bool) { failsRefresh = value }
    func hasStoredAuthorization() async -> Bool { hasAuthorization }
    func connect() async throws -> [AnalyticsProperty] {
        [TestAnalyticsFixtures.property("1"), TestAnalyticsFixtures.property("2")]
    }
    func availableProperties() async throws -> [AnalyticsProperty] {
        if discoveryFails { throw TestModelError.failed }
        return [TestAnalyticsFixtures.property("1"), TestAnalyticsFixtures.property("2")]
    }
    func refreshSelectedProperties(
        _ properties: [AnalyticsProperty],
        trigger: RefreshTrigger,
        now: Date
    ) async throws -> CombinedDashboardSnapshot {
        if refreshDelay > 0 { try await Task.sleep(for: .milliseconds(refreshDelay)) }
        if authorizationExpired { throw AnalyticsRepositoryError.authorizationExpired }
        if failsRefresh { throw TestModelError.failed }
        return DashboardAggregator.aggregate(
            properties.map { TestAnalyticsFixtures.snapshot($0.id, activeUsers: Int($0.id) ?? 0) }
        )
    }
    func cachedSnapshot(resourceNames: [String]?) async -> CombinedDashboardSnapshot? { DashboardAggregator.aggregate([TestAnalyticsFixtures.snapshot("1", activeUsers: 1)]) }
    func disconnect() async throws {}
}

private enum TestModelError: Error, LocalizedError {
    case failed
    var errorDescription: String? { "Refresh failed" }
}
