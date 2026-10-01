import Foundation
import XCTest
@testable import AnalyticsBar

final class AnalyticsRepositoryTests: XCTestCase {
    func testRefreshingSubsetRetainsCachedMetadataForUnavailableSelections() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DashboardCache(directoryURL: directory)
        try await cache.save([TestAnalyticsFixtures.snapshot("2", activeUsers: 99)])
        let repository = AnalyticsRepository(oauthSession: TestOAuthSession(), adminClient: TestAdminClient(),
            refreshCoordinator: PropertyRefreshCoordinator(dataClient: BehaviorAnalyticsDataClient(failingPropertyID: "none")), cache: cache)
        _ = try await repository.refreshSelectedProperties([TestAnalyticsFixtures.property("1")], trigger: .manual, now: Date())
        let saved = try await cache.load()
        XCTAssertEqual(Set(saved.keys), ["properties/1", "properties/2"])
        XCTAssertEqual(saved["properties/2"]?.live.activeUsers, 99)
    }

    func testDisconnectAttemptsCacheCleanupEvenWhenTokenDeletionFails() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DashboardCache(directoryURL: directory)
        try await cache.save([TestAnalyticsFixtures.snapshot("1", activeUsers: 1)])
        let repository = AnalyticsRepository(oauthSession: TestOAuthSession(failSignOut: true), adminClient: TestAdminClient(),
            refreshCoordinator: PropertyRefreshCoordinator(dataClient: BehaviorAnalyticsDataClient(failingPropertyID: "none")), cache: cache)
        do {
            try await repository.disconnect()
            XCTFail("Expected token deletion error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Google authorization"))
        }
        let saved = try await cache.load()
        XCTAssertTrue(saved.isEmpty)
    }

    func testUsesStaleCacheForOneFailedProperty() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsBarRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DashboardCache(directoryURL: directory)
        try await cache.save([TestAnalyticsFixtures.snapshot("2", activeUsers: 20)])
        let dataClient = BehaviorAnalyticsDataClient(failingPropertyID: "2")
        let repository = AnalyticsRepository(
            oauthSession: TestOAuthSession(),
            adminClient: TestAdminClient(),
            refreshCoordinator: PropertyRefreshCoordinator(dataClient: dataClient, maximumConcurrency: 3),
            cache: cache
        )
        let properties = [TestAnalyticsFixtures.property("1"), TestAnalyticsFixtures.property("2")]

        let snapshot = try await repository.refreshSelectedProperties(
            properties,
            trigger: .manual,
            now: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(snapshot.properties.map(\.id), ["1", "2"])
        XCTAssertEqual(snapshot.properties[0].freshness, .live)
        XCTAssertEqual(snapshot.properties[1].freshness, .stale)
        XCTAssertEqual(snapshot.live.activeUsers, 21)
        XCTAssertNotNil(snapshot.properties[1].refreshMessage)
    }

    func testNoSuccessfulPropertySurfacesRequestFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsBarRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AnalyticsRepository(
            oauthSession: TestOAuthSession(),
            adminClient: TestAdminClient(),
            refreshCoordinator: PropertyRefreshCoordinator(
                dataClient: BehaviorAnalyticsDataClient(failingPropertyID: "2"),
                maximumConcurrency: 3
            ),
            cache: DashboardCache(directoryURL: directory)
        )

        let snapshot = try await repository.refreshSelectedProperties(
            [TestAnalyticsFixtures.property("2")], trigger: .manual, now: Date(timeIntervalSince1970: 2_000)
        )
        XCTAssertEqual(snapshot.properties.count, 1, "Failing properties must remain visible")
        XCTAssertNil(snapshot.properties[0].coreHealth.lastSuccess)
        XCTAssertNil(snapshot.properties[0].realtimeHealth.lastSuccess)
        XCTAssertEqual(snapshot.properties[0].coreHealth.message, "Google Analytics is temporarily rate limited.")
        XCTAssertFalse(snapshot.hasCurrentCore(at: Date(timeIntervalSince1970: 2_000), maximumAge: 390))
    }
    func testRealtimeAndDailyFailuresDoNotDiscardSuccessfulReports() async throws {
        for failsCore in [true, false] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let cache = DashboardCache(directoryURL: directory)
            try await cache.save([TestAnalyticsFixtures.snapshot("1", activeUsers: 99)])
            let repository = AnalyticsRepository(
                oauthSession: TestOAuthSession(), adminClient: TestAdminClient(),
                refreshCoordinator: PropertyRefreshCoordinator(dataClient: PartialAnalyticsClient(failsCore: failsCore)), cache: cache
            )
            let now = Date(timeIntervalSince1970: 2_000)
            let combined = try await repository.refreshSelectedProperties([TestAnalyticsFixtures.property("1")], trigger: .manual, now: now)
            let snapshot = try XCTUnwrap(combined.properties.first)
            XCTAssertEqual(snapshot.coreHealth.verified, !failsCore)
            XCTAssertEqual(snapshot.realtimeHealth.verified, failsCore)
            XCTAssertEqual(snapshot.live.activeUsers, failsCore ? 7 : 99)
            XCTAssertEqual(snapshot.today.activeUsers, failsCore ? 99 : 7)
            XCTAssertEqual(combined.hasCurrentCore(at: now, maximumAge: 390), !failsCore)
            XCTAssertEqual(combined.hasCurrentRealtime(at: now, maximumAge: 390), failsCore)
        }
    }

    func testCachedDataMustBeRevalidatedOnStartup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DashboardCache(directoryURL: directory)
        try await cache.save([TestAnalyticsFixtures.snapshot("1", activeUsers: 7)])
        let repository = AnalyticsRepository(oauthSession: TestOAuthSession(), adminClient: TestAdminClient(),
            refreshCoordinator: PropertyRefreshCoordinator(dataClient: PartialAnalyticsClient(failsCore: false)), cache: cache)
        let cached = await repository.cachedSnapshot(resourceNames: ["properties/1"])
        XCTAssertEqual(cached?.properties.first?.freshness, .stale)
        XCTAssertFalse(cached?.hasCurrentCore(at: Date(timeIntervalSince1970: 1_000), maximumAge: 390) ?? true)
    }

    func testExpiredCoreAuthorizationPreservesSuccessfulRealtimeWhenTokenRefreshFails() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AnalyticsRepository(oauthSession: TestOAuthSession(failRefresh: true), adminClient: TestAdminClient(),
            refreshCoordinator: PropertyRefreshCoordinator(dataClient: ExpiredCoreClient()), cache: DashboardCache(directoryURL: directory))
        let now = Date(timeIntervalSince1970: 2_000)
        let snapshot = try await repository.refreshSelectedProperties([TestAnalyticsFixtures.property("1")], trigger: .manual, now: now)
        XCTAssertTrue(snapshot.hasCurrentRealtime(at: now, maximumAge: 390))
        XCTAssertFalse(snapshot.hasCurrentCore(at: now, maximumAge: 390))
        XCTAssertTrue(snapshot.properties[0].coreHealth.requiresReconnection == true)
        XCTAssertEqual(snapshot.live.activeUsers, 7)
    }

}

private actor TestOAuthSession: OAuthSessionProviding {
    let failRefresh: Bool
    let failSignOut: Bool
    init(failRefresh: Bool = false, failSignOut: Bool = false) {
        self.failRefresh = failRefresh
        self.failSignOut = failSignOut
    }
    func signIn() async throws -> GoogleOAuthToken {
        GoogleOAuthToken(
            accessToken: "access",
            refreshToken: "refresh",
            tokenType: "Bearer",
            scope: AppConfiguration.analyticsReadonlyScope,
            expiresAt: .distantFuture
        )
    }
    func validAccessToken() async throws -> String { "access" }
    func forceRefreshAccessToken() async throws -> String {
        if failRefresh { throw GoogleOAuthError.authorizationExpired }
        return "new-access"
    }
    func hasStoredAuthorization() async -> Bool { true }
    func signOut() async throws {
        if failSignOut { throw AnalyticsRepositoryError.requestFailed("Token deletion failed") }
    }
}

private struct TestAdminClient: AnalyticsAdminClientProtocol {
    func listProperties(accessToken: String) async throws -> [AnalyticsProperty] { [] }
}

private struct BehaviorAnalyticsDataClient: AnalyticsDataClientProtocol {
    let failingPropertyID: String

    func fetchRealtime(property: AnalyticsProperty, accessToken: String) async throws -> RealtimeTotals {
        if property.id == failingPropertyID { throw GoogleAPIError.rateLimited(retryAfter: nil) }
        return RealtimeTotals(activeUsers: Int(property.id) ?? 0, views: 0, eventCount: 0, keyEvents: 0)
    }

    func fetchCore(property: AnalyticsProperty, now: Date, accessToken: String) async throws -> PropertyCoreReport {
        if property.id == failingPropertyID { throw GoogleAPIError.rateLimited(retryAfter: nil) }
        return TestAnalyticsFixtures.core(activeUsers: Int(property.id) ?? 0)
    }
}

private struct PartialAnalyticsClient: AnalyticsDataClientProtocol {
    let failsCore: Bool
    func fetchRealtime(property: AnalyticsProperty, accessToken: String) async throws -> RealtimeTotals {
        if !failsCore { throw GoogleAPIError.server(statusCode: 503) }
        return RealtimeTotals(activeUsers: 7, views: 1, eventCount: 1, keyEvents: 0)
    }
    func fetchCore(property: AnalyticsProperty, now: Date, accessToken: String) async throws -> PropertyCoreReport {
        if failsCore { throw GoogleAPIError.server(statusCode: 503) }
        return TestAnalyticsFixtures.core(activeUsers: 7)
    }
}

private struct ExpiredCoreClient: AnalyticsDataClientProtocol {
    func fetchRealtime(property: AnalyticsProperty, accessToken: String) async throws -> RealtimeTotals {
        RealtimeTotals(activeUsers: 7, views: 1, eventCount: 1, keyEvents: 0)
    }
    func fetchCore(property: AnalyticsProperty, now: Date, accessToken: String) async throws -> PropertyCoreReport {
        throw GoogleAPIError.authorizationExpired
    }
}
