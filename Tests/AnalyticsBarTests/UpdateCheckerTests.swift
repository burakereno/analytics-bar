import Foundation
import XCTest
@testable import AnalyticsBar

@MainActor
final class UpdateCheckerTests: XCTestCase {
    func testDiscoversRedirectAndValidatesDMGAndManifest() async {
        let client = updateHTTPClient(tag: "v1.2.3")
        let checker = UpdateChecker(httpClient: client, currentVersion: "1.0.0")

        await checker.checkManually()

        guard case let .available(release) = checker.state else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(release.tag, "v1.2.3")
        XCTAssertEqual(release.version, "1.2.3")
        XCTAssertEqual(release.dmgURL.lastPathComponent, "AnalyticsBar.dmg")
        XCTAssertEqual(release.manifestURL.lastPathComponent, "AnalyticsBar.dmg.update.json")
        XCTAssertEqual(client.requests.map(\.httpMethod), ["HEAD", "HEAD", "GET"])
        XCTAssertTrue(client.requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent") == "AnalyticsBar-Updater" })
    }

    func testSemanticVersionComparisonIsNumeric() {
        XCTAssertTrue(UpdateChecker.isVersion("1.10.0", newerThan: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isVersion("1.9.9", newerThan: "1.10.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.2.3", newerThan: "1.2.3"))
    }

    func testMissingTagDMGAndManifestFailUsefully() async {
        for failure in UpdateEndpointFailure.allCases {
            let checker = UpdateChecker(
                httpClient: updateHTTPClient(tag: "v1.2.3", failure: failure),
                currentVersion: "1.0.0"
            )
            await checker.checkManually()
            guard case let .failed(message) = checker.state else {
                return XCTFail("Expected \(failure) to fail")
            }
            XCTAssertFalse(message.isEmpty)
            XCTAssertEqual(checker.lastError, message)
        }
    }

    func testRejectsEveryManifestContractMismatch() async {
        let invalidManifests: [UpdateManifest] = [
            makeManifest(version: "9.9.9"),
            makeManifest(asset: "Other.dmg"),
            makeManifest(bundleIdentifier: "com.example.Other"),
            makeManifest(teamIdentifier: "OTHERTEAM")
        ]

        for invalid in invalidManifests {
            let checker = UpdateChecker(
                httpClient: updateHTTPClient(tag: "v1.2.3", manifest: invalid),
                currentVersion: "1.0.0"
            )
            await checker.checkManually()
            guard case .failed = checker.state else {
                return XCTFail("Expected manifest mismatch to fail")
            }
        }
    }

    func testAutomaticFailurePreservesStableStateAndManualFailureReportsError() async {
        let checker = UpdateChecker(
            httpClient: updateHTTPClient(tag: "v1.2.3", failure: .network),
            currentVersion: "1.0.0"
        )

        await checker.checkAutomatically()
        XCTAssertEqual(checker.state, .idle)
        XCTAssertNil(checker.lastError)

        await checker.checkManually()
        guard case .failed = checker.state else { return XCTFail("Expected manual failure") }
        XCTAssertNotNil(checker.lastError)
    }

    func testSuccessfulCheckReportsUpToDateForCurrentVersion() async {
        let checker = UpdateChecker(
            httpClient: updateHTTPClient(tag: "v1.2.3"),
            currentVersion: "1.2.3"
        )
        await checker.checkManually()
        XCTAssertEqual(checker.state, .upToDate)
        XCTAssertNil(checker.lastError)
    }

    func testCheckingAgainAfterUpToDateFindsNewRelease() async {
        let server = MutableReleaseServer()
        let checker = UpdateChecker(httpClient: server, currentVersion: "1.2.3")
        await checker.checkManually()
        XCTAssertEqual(checker.state, .upToDate)
        await server.setVersion("1.2.4")
        await checker.checkManually()
        guard case let .available(release) = checker.state else { return XCTFail("Expected new release") }
        XCTAssertEqual(release.version, "1.2.4")
    }

    func testOverlappingAutomaticAndManualChecksShareOneRequestSequence() async {
        let server = MutableReleaseServer(delay: true)
        let checker = UpdateChecker(httpClient: server, currentVersion: "1.2.3")
        let automatic = Task { await checker.checkAutomatically() }
        while checker.state != .checking { await Task.yield() }
        await checker.checkManually()
        await automatic.value
        let count = await server.requestCount
        XCTAssertEqual(count, 3)
        XCTAssertEqual(checker.state, .upToDate)
    }
}

private actor MutableReleaseServer: HTTPClient {
    private var version = "1.2.3"
    private let delay: Bool
    private(set) var requestCount = 0
    init(delay: Bool = false) { self.delay = delay }
    func setVersion(_ value: String) { version = value }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        if request.url!.path.hasSuffix("/releases/latest") {
            if delay { try await Task.sleep(for: .milliseconds(50)) }
            let url = URL(string: "https://github.com/burakereno/analytics-bar/releases/tag/v\(version)")!
            return (Data(), TestHTTPClient.response(url: url, status: 200))
        }
        let data = request.url!.lastPathComponent.hasSuffix(".json")
            ? try JSONEncoder().encode(makeManifest(version: version)) : Data()
        return (data, TestHTTPClient.response(url: request.url!, status: 200))
    }
}

private enum UpdateEndpointFailure: CaseIterable {
    case missingTag
    case missingDMG
    case missingManifest
    case network
}

private enum UpdateTestError: Error {
    case offline
}

private func updateHTTPClient(
    tag: String,
    manifest: UpdateManifest? = nil,
    failure: UpdateEndpointFailure? = nil
) -> TestHTTPClient {
    TestHTTPClient { request in
        if failure == .network { throw UpdateTestError.offline }

        if request.url?.path.hasSuffix("/releases/latest") == true {
            let finalURL = failure == .missingTag
                ? URL(string: "https://github.com/burakereno/analytics-bar/releases/latest")!
                : URL(string: "https://github.com/burakereno/analytics-bar/releases/tag/\(tag)")!
            return (Data(), TestHTTPClient.response(url: finalURL, status: 200))
        }

        if request.url?.lastPathComponent == "AnalyticsBar.dmg" {
            let status = failure == .missingDMG ? 404 : 200
            return (Data(), TestHTTPClient.response(url: request.url!, status: status))
        }

        if request.url?.lastPathComponent == "AnalyticsBar.dmg.update.json" {
            let status = failure == .missingManifest ? 404 : 200
            let value = manifest ?? makeManifest()
            return (
                try JSONEncoder().encode(value),
                TestHTTPClient.response(url: request.url!, status: status)
            )
        }

        return (Data(), TestHTTPClient.response(url: request.url!, status: 404))
    }
}

private func makeManifest(
    version: String = "1.2.3",
    asset: String = "AnalyticsBar.dmg",
    bundleIdentifier: String = "com.burakerenoglu.AnalyticsBar",
    teamIdentifier: String = "66K3EFBVB6"
) -> UpdateManifest {
    UpdateManifest(
        version: version,
        asset: asset,
        sha256: String(repeating: "a", count: 64),
        bundleIdentifier: bundleIdentifier,
        teamIdentifier: teamIdentifier
    )
}
