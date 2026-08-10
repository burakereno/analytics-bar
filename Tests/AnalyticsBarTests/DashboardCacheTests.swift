import Foundation
import XCTest
@testable import AnalyticsBar

final class DashboardCacheTests: XCTestCase {
    func testRoundTripAndCorruptFileRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsBarCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DashboardCache(directoryURL: directory)
        let snapshot = TestAnalyticsFixtures.snapshot("101", activeUsers: 12)

        try await cache.save([snapshot])
        let loaded = try await cache.load()
        XCTAssertEqual(loaded, ["properties/101": snapshot])

        let fileURL = directory.appendingPathComponent("dashboard-cache-v1.json")
        try Data("not-json".utf8).write(to: fileURL)
        let recovered = try await cache.load()
        XCTAssertEqual(recovered, [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCacheContainsNoOAuthFields() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsBarCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DashboardCache(directoryURL: directory)

        try await cache.save([TestAnalyticsFixtures.snapshot("101", activeUsers: 3)])

        let data = try Data(contentsOf: directory.appendingPathComponent("dashboard-cache-v1.json"))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("access_token"))
        XCTAssertFalse(text.contains("refresh_token"))
        XCTAssertFalse(text.contains("client_secret"))
    }
}
