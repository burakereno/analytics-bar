import Foundation
@testable import AnalyticsBar

final class TestHTTPClient: HTTPClient, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        lock.withLock { storedRequests }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { storedRequests.append(request) }
        return try await handler(request)
    }

    static func response(url: URL, status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
    }
}

final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: GoogleOAuthToken?

    init(token: GoogleOAuthToken? = nil) {
        self.token = token
    }

    func load() throws -> GoogleOAuthToken? {
        lock.withLock { token }
    }

    func save(_ token: GoogleOAuthToken) throws {
        lock.withLock { self.token = token }
    }

    func delete() throws {
        lock.withLock { token = nil }
    }
}
