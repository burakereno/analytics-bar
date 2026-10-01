import Combine
import Foundation

struct UpdateReleaseInfo: Equatable, Sendable {
    let tag: String
    let version: String
    let dmgURL: URL
    let manifestURL: URL
    let manifest: UpdateManifest
}

@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateReleaseInfo)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastError: String?

    private let httpClient: any HTTPClient
    private let currentVersion: String
    private var isChecking = false
    private let latestReleaseURL = URL(
        string: "https://github.com/\(AppConfiguration.githubOwner)/\(AppConfiguration.githubRepo)/releases/latest"
    )!

    init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        currentVersion: String = AppConfiguration.marketingVersion
    ) {
        self.httpClient = httpClient
        self.currentVersion = currentVersion
    }

    func checkAutomatically() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let stableState = state
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            state = Self.isVersion(release.version, newerThan: currentVersion)
                ? .available(release)
                : .upToDate
            lastError = nil
        } catch {
            state = stableState
            lastError = nil
        }
    }

    func checkManually() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        state = .checking
        lastError = nil
        do {
            let release = try await fetchLatestRelease()
            state = Self.isVersion(release.version, newerThan: currentVersion)
                ? .available(release)
                : .upToDate
        } catch {
            let message = error.localizedDescription
            lastError = message
            state = .failed(message)
        }
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        guard let candidate = SemanticVersion(candidate),
              let current = SemanticVersion(current) else { return false }
        return candidate > current
    }

    private func fetchLatestRelease() async throws -> UpdateReleaseInfo {
        let (_, latestResponse) = try await httpClient.data(for: request(url: latestReleaseURL, method: "HEAD"))
        guard (200..<400).contains(latestResponse.statusCode) else {
            throw UpdateError.badResponse("GitHub returned \(latestResponse.statusCode) for the latest release.")
        }
        guard let finalURL = latestResponse.url,
              let tag = releaseTag(from: finalURL),
              tag.hasPrefix("v") else {
            throw UpdateError.missingVersion
        }
        let version = String(tag.dropFirst())
        guard SemanticVersion(version) != nil else { throw UpdateError.missingVersion }

        let baseURL = URL(
            string: "https://github.com/\(AppConfiguration.githubOwner)/\(AppConfiguration.githubRepo)/releases/download/\(tag)/"
        )!
        let dmgURL = baseURL.appendingPathComponent(AppConfiguration.dmgAssetName)
        let manifestURL = baseURL.appendingPathComponent(AppConfiguration.manifestAssetName)

        let (_, dmgResponse) = try await httpClient.data(for: request(url: dmgURL, method: "HEAD"))
        guard (200..<300).contains(dmgResponse.statusCode) else { throw UpdateError.missingAsset }

        let (manifestData, manifestResponse) = try await httpClient.data(
            for: request(url: manifestURL, method: "GET")
        )
        guard (200..<300).contains(manifestResponse.statusCode) else {
            throw UpdateError.missingManifest
        }
        guard let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: manifestData) else {
            throw UpdateError.invalidManifest("The update manifest could not be decoded.")
        }
        try manifest.validate(version: version)

        return UpdateReleaseInfo(
            tag: tag,
            version: version,
            dmgURL: dmgURL,
            manifestURL: manifestURL,
            manifest: manifest
        )
    }

    private func request(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("AnalyticsBar-Updater", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func releaseTag(from url: URL) -> String? {
        guard url.scheme == "https", url.host == "github.com" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 5,
              parts[0] == AppConfiguration.githubOwner,
              parts[1] == AppConfiguration.githubRepo,
              parts[2] == "releases",
              parts[3] == "tag" else { return nil }
        return parts[4]
    }
}

private struct SemanticVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]), major >= 0,
              let minor = Int(parts[1]), minor >= 0,
              let patch = Int(parts[2]), patch >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
