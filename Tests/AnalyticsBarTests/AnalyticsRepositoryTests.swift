import Foundation
import XCTest
@testable import AnalyticsBar

final class AnalyticsRepositoryTests: XCTestCase {
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

        do {
            _ = try await repository.refreshSelectedProperties(
                [TestAnalyticsFixtures.property("2")],
                trigger: .manual,
                now: Date(timeIntervalSince1970: 2_000)
            )
            XCTFail("Expected the property request failure")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Google Analytics is temporarily rate limited."
            )
        }
    }
}

private actor TestOAuthSession: OAuthSessionProviding {
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
    func forceRefreshAccessToken() async throws -> String { "new-access" }
    func hasStoredAuthorization() async -> Bool { true }
    func signOut() async throws {}
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
