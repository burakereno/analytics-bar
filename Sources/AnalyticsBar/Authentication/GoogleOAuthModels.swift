import Foundation

struct GoogleOAuthToken: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let scope: String
    let expiresAt: Date

    func isExpired(at date: Date = Date(), tolerance: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(date) <= tolerance
    }
}

protocol TokenStore: Sendable {
    func load() throws -> GoogleOAuthToken?
    func save(_ token: GoogleOAuthToken) throws
    func delete() throws
}
