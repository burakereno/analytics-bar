import Foundation
import XCTest
@testable import AnalyticsBar

@MainActor
final class SettingsModelTests: XCTestCase {
    func testMissingSelectedSiteRemainsVisibleAndIsNotRequested() async {
        let fixture = await fixture()
        defer { fixture.scheduler.stop() }
        await fixture.repository.setProperties(["1"])
        await fixture.model.checkConnection()

        XCTAssertEqual(fixture.preferences.selectedPropertyResourceNames, ["properties/1", "properties/2"])
        XCTAssertEqual(fixture.model.snapshot?.properties.map(\.id), ["1", "2"])
        XCTAssertEqual(fixture.model.unavailableSelectedResourceNames, ["properties/2"])
        XCTAssertEqual(fixture.model.propertyDisplayName("properties/2"), "Property 2")
        XCTAssertNotNil(fixture.model.connectionError)
        XCTAssertFalse(fixture.model.snapshot!.properties[1].coreHealth.verified)
        let requested = await fixture.repository.lastRequested
        XCTAssertEqual(requested, ["properties/1"])
    }

    func testChangingAnotherSitePreservesUnavailableSelectionUntilExplicitRemoval() {
        let properties = [TestAnalyticsFixtures.property("1"), TestAnalyticsFixtures.property("3")]
        var selection = PropertySelection(properties: properties, selectedResourceNames: ["properties/1", "properties/2"],
                                          preservesUnavailableSelections: true)
        selection.toggle("properties/3")
        XCTAssertEqual(selection.selectedResourceNames, ["properties/1", "properties/3", "properties/2"])
        selection.removeUnavailable("properties/2")
        XCTAssertEqual(selection.selectedResourceNames, ["properties/1", "properties/3"])
    }

    func testRemovingOnlyUnavailableSiteAllowsChoosingAReplacement() async {
        let fixture = await fixture(selected: ["properties/1"])
        defer { fixture.scheduler.stop() }
        await fixture.repository.setProperties(["2"])
        await fixture.model.checkConnection()
        fixture.model.updateSelection([])
        XCTAssertTrue(fixture.preferences.selectedPropertyResourceNames.isEmpty)
        XCTAssertNil(fixture.model.snapshot)
        XCTAssertTrue(fixture.model.isChoosingProperties)
        XCTAssertNil(fixture.model.connectionError)
    }

    func testCancelledReconnectPreservesWorkingDashboard() async {
        let fixture = await fixture()
        defer { fixture.scheduler.stop() }
        let previous = fixture.model.snapshot
        await fixture.repository.cancelConnect()
        await fixture.model.connect()
        XCTAssertEqual(fixture.model.state, .loaded)
        XCTAssertEqual(fixture.model.snapshot, previous)
        XCTAssertNil(fixture.model.connectionError)
        XCTAssertFalse(fixture.model.needsReconnection)
    }

    func testRefreshCannotReplaceReconnectSelectionScreen() async {
        let fixture = await fixture()
        defer { fixture.scheduler.stop() }
        await fixture.model.connect()
        XCTAssertTrue(fixture.model.isChoosingProperties)
        await fixture.model.refresh(trigger: .backgroundTimer)
        await fixture.model.refresh(trigger: .manual)
        XCTAssertTrue(fixture.model.isChoosingProperties)
        await fixture.model.confirmSelection(["properties/2"])
        XCTAssertEqual(fixture.model.state, .loaded)
        XCTAssertEqual(fixture.model.snapshot?.properties.map(\.id), ["2"])
    }

    func testFailedDisconnectPreservesSelectionAndSurfacesErrorThenCanRetry() async {
        let fixture = await fixture()
        defer { fixture.scheduler.stop() }
        await fixture.repository.setDisconnectFailure(true)
        await fixture.model.disconnect()
        XCTAssertEqual(fixture.model.state, .loaded)
        XCTAssertNotNil(fixture.model.snapshot)
        XCTAssertEqual(fixture.preferences.selectedPropertyResourceNames.count, 2)
        XCTAssertTrue(fixture.model.connectionError?.contains("Audit deletion failed") == true)
        XCTAssertFalse(fixture.model.isDisconnecting)
        await fixture.repository.setDisconnectFailure(false)
        await fixture.model.disconnect()
        XCTAssertEqual(fixture.model.state, .disconnected)
        XCTAssertNil(fixture.model.snapshot)
        XCTAssertTrue(fixture.preferences.selectedPropertyResourceNames.isEmpty)
    }

    func testDisconnectWaitsForInFlightRefreshBeforeDeletingData() async {
        let fixture = await fixture()
        defer { fixture.scheduler.stop() }
        await fixture.repository.delayRefresh()
        let refresh = Task { await fixture.model.refresh(trigger: .manual) }
        while !fixture.model.isRefreshing { await Task.yield() }
        await fixture.model.disconnect()
        await refresh.value
        let overlapped = await fixture.repository.disconnectOverlappedRefresh
        XCTAssertFalse(overlapped)
        XCTAssertEqual(fixture.model.state, .disconnected)
        XCTAssertNil(fixture.model.snapshot)
    }

    func testPartialDisconnectInvalidatesDataAndKeepsCleanupRetryAvailable() async {
        let fixture = await fixture()
        defer { fixture.scheduler.stop() }
        await fixture.repository.failAfterDeletingAuthorization()
        await fixture.model.disconnect()
        XCTAssertTrue(fixture.model.needsReconnection)
        XCTAssertNotNil(fixture.model.connectionError)
        XCTAssertNotEqual(fixture.model.state, .disconnected)
        XCTAssertFalse(fixture.model.snapshot!.properties[0].coreHealth.verified)
        XCTAssertEqual(fixture.preferences.selectedPropertyResourceNames.count, 2)
    }

    private func fixture(selected: [String] = ["properties/1", "properties/2"]) async -> Fixture {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "SettingsModelTests.\(UUID().uuidString)")!)
        let repository = SettingsRepository()
        let scheduler = RefreshScheduler()
        let model = DashboardModel(repository: repository, preferences: preferences, scheduler: scheduler)
        await model.connect()
        await model.confirmSelection(selected)
        return Fixture(preferences: preferences, repository: repository, scheduler: scheduler, model: model)
    }

    private struct Fixture {
        let preferences: AppPreferences
        let repository: SettingsRepository
        let scheduler: RefreshScheduler
        let model: DashboardModel
    }
}

private actor SettingsRepository: AnalyticsRepositoryProtocol {
    private var properties = ["1", "2"]
    private var shouldCancelConnect = false
    private var shouldFailDisconnect = false
    private var hasAuthorization = true
    private var delaysRefresh = false
    private var refreshing = false
    private(set) var lastRequested: [String] = []
    private(set) var disconnectOverlappedRefresh = false
    func setProperties(_ ids: [String]) { properties = ids }
    func cancelConnect() { shouldCancelConnect = true }
    func setDisconnectFailure(_ value: Bool) { shouldFailDisconnect = value }
    func failAfterDeletingAuthorization() {
        shouldFailDisconnect = true
        hasAuthorization = false
    }
    func delayRefresh() { delaysRefresh = true }
    func hasStoredAuthorization() async -> Bool { hasAuthorization }
    func connect() async throws -> [AnalyticsProperty] {
        if shouldCancelConnect { throw GoogleOAuthError.cancelled }
        return properties.map { TestAnalyticsFixtures.property($0) }
    }
    func availableProperties() async throws -> [AnalyticsProperty] { properties.map { TestAnalyticsFixtures.property($0) } }
    func refreshSelectedProperties(_ properties: [AnalyticsProperty], trigger: RefreshTrigger, now: Date) async throws -> CombinedDashboardSnapshot {
        refreshing = true
        defer { refreshing = false }
        if delaysRefresh { try await Task.sleep(for: .milliseconds(200)) }
        lastRequested = properties.map(\.resourceName)
        return DashboardAggregator.aggregate(properties.map { TestAnalyticsFixtures.snapshot($0.id, activeUsers: 1) })
    }
    func cachedSnapshot(resourceNames: [String]?) async -> CombinedDashboardSnapshot? { nil }
    func disconnect() async throws {
        disconnectOverlappedRefresh = refreshing
        if shouldFailDisconnect { throw AnalyticsRepositoryError.requestFailed("Audit deletion failed") }
        hasAuthorization = false
    }
}
