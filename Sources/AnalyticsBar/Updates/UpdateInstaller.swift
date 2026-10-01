import AppKit
import Combine
import CryptoKit
import Foundation

struct UpdateDownloadResult: Sendable {
    let temporaryURL: URL
    let response: HTTPURLResponse
}

protocol UpdateDownloading: Sendable {
    func download(for request: URLRequest) async throws -> UpdateDownloadResult
}

final class URLSessionUpdateDownloader: UpdateDownloading, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func download(for request: URLRequest) async throws -> UpdateDownloadResult {
        let (url, response) = try await session.download(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw UpdateError.badResponse("The update server returned an unreadable response.")
        }
        return UpdateDownloadResult(temporaryURL: url, response: response)
    }
}

struct UpdateHelperCommand: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
}

@MainActor
protocol UpdateHelperRunning: AnyObject {
    func launch(_ command: UpdateHelperCommand) throws
}

@MainActor
final class ProcessUpdateHelperRunner: UpdateHelperRunning {
    func launch(_ command: UpdateHelperCommand) throws {
        let logDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/AnalyticsBar", isDirectory: true)
        try FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let logURL = logDirectory.appendingPathComponent("update.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let logHandle = try FileHandle(forWritingTo: logURL)
        try logHandle.seekToEnd()

        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.terminationHandler = { _ in try? logHandle.close() }
        try process.run()
    }
}

enum UpdateTrustPolicy {
    static func validate(_ release: UpdateReleaseInfo) throws {
        guard release.tag == "v\(release.version)" else { throw UpdateError.invalidDownloadURL }
        try release.manifest.validate(version: release.version)
        guard isExpected(
            release.dmgURL,
            tag: release.tag,
            asset: AppConfiguration.dmgAssetName
        ), isExpected(
            release.manifestURL,
            tag: release.tag,
            asset: AppConfiguration.manifestAssetName
        ) else {
            throw UpdateError.invalidDownloadURL
        }
    }

    private static func isExpected(_ url: URL, tag: String, asset: String) -> Bool {
        guard url.scheme == "https", url.host == "github.com", url.port == nil,
              url.query == nil, url.fragment == nil else { return false }
        let parts = url.path.split(separator: "/").map(String.init)
        return parts == [
            AppConfiguration.githubOwner,
            AppConfiguration.githubRepo,
            "releases",
            "download",
            tag,
            asset
        ]
    }
}

@MainActor
final class UpdateInstaller: ObservableObject {
    enum State: Equatable {
        case idle
        case downloadingManifest
        case downloadingDMG
        case verifying
        case installing
        case relaunching
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    var isBusy: Bool {
        switch state {
        case .idle, .failed: false
        default: true
        }
    }

    private let downloader: any UpdateDownloading
    private let helperRunner: any UpdateHelperRunning
    private let helperURL: URL?
    private let currentAppURL: URL
    private let temporaryDirectory: URL
    private let terminateApplication: @MainActor () -> Void
    private let fileManager: FileManager

    init(
        downloader: (any UpdateDownloading)? = nil,
        helperRunner: (any UpdateHelperRunning)? = nil,
        helperURL: URL? = Bundle.main.resourceURL?.appendingPathComponent("install-update.sh"),
        currentAppURL: URL = Bundle.main.bundleURL,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default,
        terminateApplication: @escaping @MainActor () -> Void = {
            NSApplication.shared.terminate(nil)
        }
    ) {
        self.downloader = downloader ?? URLSessionUpdateDownloader()
        self.helperRunner = helperRunner ?? ProcessUpdateHelperRunner()
        self.helperURL = helperURL
        self.currentAppURL = currentAppURL
        self.temporaryDirectory = temporaryDirectory
        self.fileManager = fileManager
        self.terminateApplication = terminateApplication
    }

    func install(_ release: UpdateReleaseInfo) async throws {
        var workDirectory: URL?
        var helperLaunched = false
        do {
            try UpdateTrustPolicy.validate(release)
            try validateLocalResources()

            let directory = temporaryDirectory.appendingPathComponent(
                "AnalyticsBar-Update-\(UUID().uuidString)",
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            workDirectory = directory

            state = .downloadingManifest
            let downloadedManifest = try await downloader.download(
                for: request(url: release.manifestURL)
            )
            guard (200..<300).contains(downloadedManifest.response.statusCode) else {
                throw UpdateError.badResponse(
                    "The update manifest download failed (\(downloadedManifest.response.statusCode))."
                )
            }
            let manifestData = try Data(contentsOf: downloadedManifest.temporaryURL)
            let manifest = try JSONDecoder().decode(UpdateManifest.self, from: manifestData)
            try manifest.validate(version: release.version)
            guard manifest == release.manifest else {
                throw UpdateError.invalidManifest("The update manifest changed during download.")
            }

            state = .downloadingDMG
            let downloadedDMG = try await downloader.download(for: request(url: release.dmgURL))
            guard (200..<300).contains(downloadedDMG.response.statusCode) else {
                throw UpdateError.badResponse(
                    "The update installer download failed (\(downloadedDMG.response.statusCode))."
                )
            }
            let dmgURL = directory.appendingPathComponent(AppConfiguration.dmgAssetName)
            try fileManager.copyItem(at: downloadedDMG.temporaryURL, to: dmgURL)

            state = .verifying
            let checksum = try Self.sha256(at: dmgURL)
            guard checksum == manifest.sha256 else { throw UpdateError.checksumMismatch }

            guard let helperURL else {
                throw UpdateError.invalidInstaller("The bundled update helper is missing.")
            }
            let command = UpdateHelperCommand(
                executableURL: helperURL,
                arguments: [
                    dmgURL.path,
                    currentAppURL.path,
                    AppConfiguration.bundleIdentifier,
                    release.version,
                    AppConfiguration.teamIdentifier,
                    AppConfiguration.executableName,
                    manifest.sha256
                ]
            )
            state = .installing
            try helperRunner.launch(command)
            helperLaunched = true
            state = .relaunching
            terminateApplication()
        } catch {
            if let workDirectory, !helperLaunched {
                try? fileManager.removeItem(at: workDirectory)
            }
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    nonisolated static func sha256(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func validateLocalResources() throws {
        guard currentAppURL.pathExtension == "app",
              fileManager.fileExists(atPath: currentAppURL.path) else {
            throw UpdateError.invalidInstaller("Analytics Bar is not running from an app bundle.")
        }
        guard let helperURL, fileManager.fileExists(atPath: helperURL.path) else {
            throw UpdateError.invalidInstaller("The bundled update helper is missing.")
        }
        try UpdateSecurityContract.validateHelper(at: helperURL)
    }

    private func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 120
        request.setValue("AnalyticsBar-Updater", forHTTPHeaderField: "User-Agent")
        return request
    }
}
