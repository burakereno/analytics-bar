import Foundation

struct UpdateManifest: Codable, Equatable, Sendable {
    let version: String
    let asset: String
    let sha256: String
    let bundleIdentifier: String
    let teamIdentifier: String

    func validate(version expectedVersion: String) throws {
        guard version == expectedVersion else {
            throw UpdateError.invalidManifest("Release and manifest versions do not match.")
        }
        guard asset == AppConfiguration.dmgAssetName else {
            throw UpdateError.invalidManifest("The manifest names an unexpected installer asset.")
        }
        guard bundleIdentifier == AppConfiguration.bundleIdentifier else {
            throw UpdateError.invalidManifest("The manifest bundle identifier is not Analytics Bar.")
        }
        guard teamIdentifier == AppConfiguration.teamIdentifier else {
            throw UpdateError.invalidManifest("The manifest publisher does not match Analytics Bar.")
        }
        let lowercaseHex = CharacterSet(charactersIn: "0123456789abcdef")
        guard sha256.count == 64,
              sha256 == sha256.lowercased(),
              sha256.unicodeScalars.allSatisfy(lowercaseHex.contains) else {
            throw UpdateError.invalidManifest("The manifest checksum is invalid.")
        }
    }
}

enum UpdateError: Error, Equatable, LocalizedError, Sendable {
    case badResponse(String)
    case missingVersion
    case missingAsset
    case missingManifest
    case invalidDownloadURL
    case invalidManifest(String)
    case checksumMismatch
    case invalidInstaller(String)
    case publisherMismatch

    var errorDescription: String? {
        switch self {
        case let .badResponse(detail): detail
        case .missingVersion: "The latest release did not contain a valid vX.Y.Z tag."
        case .missingAsset: "The latest release does not contain AnalyticsBar.dmg."
        case .missingManifest: "The latest release does not contain the update manifest."
        case .invalidDownloadURL: "The update download URL is not trusted."
        case let .invalidManifest(detail): detail
        case .checksumMismatch: "The downloaded update checksum does not match its manifest."
        case let .invalidInstaller(detail): detail
        case .publisherMismatch: "The update is not signed by the Analytics Bar publisher."
        }
    }
}
