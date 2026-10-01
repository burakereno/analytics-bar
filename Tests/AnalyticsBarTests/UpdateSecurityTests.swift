import CryptoKit
import Foundation
import XCTest
@testable import AnalyticsBar

@MainActor
final class UpdateSecurityTests: XCTestCase {
    func testHelperRequirementParsesAndRejectsAnotherSignedExecutable() throws {
        let requirement = try installerHelperRequirement()
        let signedExecutable = "/usr/bin/true"
        let baseline = try runCodesign(["--verify", "--strict", signedExecutable])
        XCTAssertEqual(baseline.status, 0, baseline.output)

        let verification = try runCodesign([
            "--verify", "--strict", "--verbose=2", "-R=" + requirement, signedExecutable
        ])

        // A parsed requirement that does not match exits 3. A syntax error must
        // not pass as successful rejection of an unrelated signed executable.
        XCTAssertEqual(verification.status, 3, verification.output)
        XCTAssertTrue(
            verification.output.contains("code failed to satisfy specified code requirement(s)"),
            verification.output
        )
    }

    func testRejectsUntrustedReleaseURLs() {
        let trusted = makeRelease()
        XCTAssertNoThrow(try UpdateTrustPolicy.validate(trusted))

        for url in [
            "https://example.com/burakereno/analytics-bar/releases/download/v1.2.3/AnalyticsBar.dmg",
            "https://github.com/other/analytics-bar/releases/download/v1.2.3/AnalyticsBar.dmg",
            "https://github.com/burakereno/other/releases/download/v1.2.3/AnalyticsBar.dmg"
        ] {
            let release = UpdateReleaseInfo(
                tag: trusted.tag,
                version: trusted.version,
                dmgURL: URL(string: url)!,
                manifestURL: trusted.manifestURL,
                manifest: trusted.manifest
            )
            XCTAssertThrowsError(try UpdateTrustPolicy.validate(release))
        }
    }

    func testVerifiedDownloadPassesSeparateHelperArguments() async throws {
        let context = try InstallerTestContext()
        defer { context.cleanup() }
        let runner = UpdateHelperRunnerSpy()
        var terminated = false
        let installer = UpdateInstaller(
            downloader: context.downloader,
            helperRunner: runner,
            helperURL: context.helperURL,
            currentAppURL: context.appURL,
            temporaryDirectory: context.directory,
            terminateApplication: { terminated = true }
        )

        try await installer.install(context.release)

        XCTAssertEqual(installer.state, .relaunching)
        XCTAssertTrue(terminated)
        XCTAssertEqual(runner.commands.count, 1)
        let command = try XCTUnwrap(runner.commands.first)
        XCTAssertEqual(command.executableURL, context.helperURL)
        XCTAssertEqual(command.arguments.count, 7)
        XCTAssertTrue(command.arguments[0].hasSuffix("AnalyticsBar.dmg"))
        XCTAssertEqual(command.arguments[1...], [
            context.appURL.path,
            "com.burakerenoglu.AnalyticsBar",
            "1.2.3",
            "66K3EFBVB6",
            "AnalyticsBar",
            context.release.manifest.sha256
        ])
    }

    func testRejectsHTTPFailuresChecksumAndManifestMismatch() async throws {
        for failure in InstallerFailure.allCases {
            let context = try InstallerTestContext(failure: failure)
            defer { context.cleanup() }
            let runner = UpdateHelperRunnerSpy()
            let installer = UpdateInstaller(
                downloader: context.downloader,
                helperRunner: runner,
                helperURL: context.helperURL,
                currentAppURL: context.appURL,
                temporaryDirectory: context.directory,
                terminateApplication: {}
            )

            do {
                try await installer.install(context.release)
                XCTFail("Expected \(failure) to fail")
            } catch {
                XCTAssertTrue(runner.commands.isEmpty)
                guard case .failed = installer.state else {
                    return XCTFail("Expected failed installer state")
                }
            }
        }
    }

    func testRejectsMissingCurrentAppAndHelper() async throws {
        let context = try InstallerTestContext()
        defer { context.cleanup() }

        for missingPath in [context.appURL, context.helperURL] {
            try FileManager.default.removeItem(at: missingPath)
            let installer = UpdateInstaller(
                downloader: context.downloader,
                helperRunner: UpdateHelperRunnerSpy(),
                helperURL: context.helperURL,
                currentAppURL: context.appURL,
                temporaryDirectory: context.directory,
                terminateApplication: {}
            )
            await XCTAssertThrowsErrorAsync { try await installer.install(context.release) }

            if missingPath == context.appURL {
                try FileManager.default.createDirectory(at: context.appURL, withIntermediateDirectories: true)
            }
        }
    }
}

private func installerHelperRequirement() throws -> String {
    let repositoryURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let helperURL = repositoryURL.appendingPathComponent("scripts/install-update.sh")
    let source = try String(contentsOf: helperURL, encoding: .utf8)
    let pattern = #"(?m)^\s+-R="(.*)"\s+\\$"#
    let expression = try NSRegularExpression(pattern: pattern)
    let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
    XCTAssertEqual(matches.count, 1, "Expected one app-signature requirement in the real helper")
    let match = try XCTUnwrap(matches.first)
    let range = try XCTUnwrap(Range(match.range(at: 1), in: source))
    let requirement = String(source[range])
        .replacingOccurrences(of: "$BUNDLE_ID", with: AppConfiguration.bundleIdentifier)
        .replacingOccurrences(of: "$TEAM_ID", with: AppConfiguration.teamIdentifier)
        .replacingOccurrences(of: #"\""#, with: "\"")
    XCTAssertFalse(requirement.contains("$"), "Unexpected unexpanded helper variable")
    return requirement
}

private func runCodesign(_ arguments: [String]) throws -> (status: Int32, output: String) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: output, as: UTF8.self))
}

private enum InstallerFailure: CaseIterable {
    case manifestHTTP
    case dmgHTTP
    case checksum
    case manifestMismatch
}

private final class InstallerTestContext {
    let directory: URL
    let appURL: URL
    let helperURL: URL
    let release: UpdateReleaseInfo
    let downloader: UpdateDownloaderStub

    init(failure: InstallerFailure? = nil) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsBarUpdaterTests-\(UUID().uuidString)", isDirectory: true)
        appURL = directory.appendingPathComponent("Analytics Bar.app", isDirectory: true)
        helperURL = directory.appendingPathComponent("install-update.sh")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        let helperFixture = UpdateSecurityContract.requiredHelperFragments.joined(separator: "\n")
        try Data(helperFixture.utf8).write(to: helperURL)

        let dmgData = Data("signed-dmg-fixture".utf8)
        let hash = SHA256.hash(data: dmgData).map { String(format: "%02x", $0) }.joined()
        let releaseManifest = UpdateManifest(
            version: "1.2.3",
            asset: "AnalyticsBar.dmg",
            sha256: failure == .checksum ? String(repeating: "b", count: 64) : hash,
            bundleIdentifier: "com.burakerenoglu.AnalyticsBar",
            teamIdentifier: "66K3EFBVB6"
        )
        release = makeRelease(manifest: releaseManifest)

        let downloadedManifest = UpdateManifest(
            version: failure == .manifestMismatch ? "9.9.9" : releaseManifest.version,
            asset: releaseManifest.asset,
            sha256: releaseManifest.sha256,
            bundleIdentifier: releaseManifest.bundleIdentifier,
            teamIdentifier: releaseManifest.teamIdentifier
        )
        downloader = try UpdateDownloaderStub(
            directory: directory,
            manifestData: JSONEncoder().encode(downloadedManifest),
            dmgData: dmgData,
            manifestStatus: failure == .manifestHTTP ? 500 : 200,
            dmgStatus: failure == .dmgHTTP ? 404 : 200
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class UpdateDownloaderStub: UpdateDownloading, @unchecked Sendable {
    let manifestURL: URL
    let dmgURL: URL
    let manifestStatus: Int
    let dmgStatus: Int

    init(
        directory: URL,
        manifestData: Data,
        dmgData: Data,
        manifestStatus: Int,
        dmgStatus: Int
    ) throws {
        manifestURL = directory.appendingPathComponent("downloaded-manifest.json")
        dmgURL = directory.appendingPathComponent("downloaded.dmg")
        try manifestData.write(to: manifestURL)
        try dmgData.write(to: dmgURL)
        self.manifestStatus = manifestStatus
        self.dmgStatus = dmgStatus
    }

    func download(for request: URLRequest) async throws -> UpdateDownloadResult {
        let isManifest = request.url?.lastPathComponent.hasSuffix(".json") == true
        let localURL = isManifest ? manifestURL : dmgURL
        let status = isManifest ? manifestStatus : dmgStatus
        return UpdateDownloadResult(
            temporaryURL: localURL,
            response: TestHTTPClient.response(url: request.url!, status: status)
        )
    }
}

@MainActor
private final class UpdateHelperRunnerSpy: UpdateHelperRunning {
    private(set) var commands: [UpdateHelperCommand] = []
    func launch(_ command: UpdateHelperCommand) throws { commands.append(command) }
}

private func makeRelease(manifest: UpdateManifest? = nil) -> UpdateReleaseInfo {
    let manifest = manifest ?? UpdateManifest(
        version: "1.2.3",
        asset: "AnalyticsBar.dmg",
        sha256: String(repeating: "a", count: 64),
        bundleIdentifier: "com.burakerenoglu.AnalyticsBar",
        teamIdentifier: "66K3EFBVB6"
    )
    return UpdateReleaseInfo(
        tag: "v1.2.3",
        version: "1.2.3",
        dmgURL: URL(string: "https://github.com/burakereno/analytics-bar/releases/download/v1.2.3/AnalyticsBar.dmg")!,
        manifestURL: URL(string: "https://github.com/burakereno/analytics-bar/releases/download/v1.2.3/AnalyticsBar.dmg.update.json")!,
        manifest: manifest
    )
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
