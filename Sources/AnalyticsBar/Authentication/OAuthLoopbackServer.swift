import AppKit
import Foundation
import Network

enum GoogleOAuthError: Error, Equatable, LocalizedError, Sendable {
    case configurationMissing
    case cancelled
    case stateMismatch
    case invalidCallback
    case unableToOpenBrowser
    case listenerFailed
    case timeout
    case invalidResponse
    case authorizationExpired
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            return "Google OAuth client configuration is missing."
        case .cancelled:
            return "Google authorization was cancelled."
        case .stateMismatch:
            return "Google authorization state did not match."
        case .invalidCallback:
            return "Google authorization callback was invalid."
        case .unableToOpenBrowser:
            return "The Google authorization page could not be opened."
        case .listenerFailed:
            return "The local Google authorization callback could not start."
        case .timeout:
            return "Google authorization timed out."
        case .invalidResponse:
            return "Google returned an unreadable authorization response."
        case .authorizationExpired:
            return "Google authorization expired. Please reconnect."
        case let .httpStatus(status):
            return "Google authorization failed (\(status))."
        }
    }
}

enum OAuthCallbackParser {
    static func parse(target: String, expectedState: String) throws -> String {
        guard let components = URLComponents(string: "http://127.0.0.1\(target)"),
              components.path == "/oauth/callback" else {
            throw GoogleOAuthError.invalidCallback
        }
        let values = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        guard values["state"] == expectedState else {
            throw GoogleOAuthError.stateMismatch
        }
        if values["error"] == "access_denied" {
            throw GoogleOAuthError.cancelled
        }
        guard let code = values["code"], !code.isEmpty else {
            throw GoogleOAuthError.invalidCallback
        }
        return code
    }
}

struct OAuthAuthorizationCode: Equatable, Sendable {
    let code: String
    let redirectURI: URL
}

protocol AuthorizationCodeProviding: Sendable {
    func authorizationCode(
        configuration: GoogleOAuthConfiguration,
        pkce: PKCEPair,
        state: String
    ) async throws -> OAuthAuthorizationCode
}

struct SystemAuthorizationCodeProvider: AuthorizationCodeProviding {
    func authorizationCode(
        configuration: GoogleOAuthConfiguration,
        pkce: PKCEPair,
        state: String
    ) async throws -> OAuthAuthorizationCode {
        let server = OAuthLoopbackServer(expectedState: state)
        let redirectURI = try await server.start()
        let authorizationURL = try Self.authorizationURL(
            configuration: configuration,
            pkce: pkce,
            state: state,
            redirectURI: redirectURI
        )
        let didOpen = await MainActor.run { NSWorkspace.shared.open(authorizationURL) }
        guard didOpen else {
            await server.cancel()
            throw GoogleOAuthError.unableToOpenBrowser
        }
        let code = try await server.waitForCode()
        return OAuthAuthorizationCode(code: code, redirectURI: redirectURI)
    }

    static func authorizationURL(
        configuration: GoogleOAuthConfiguration,
        pkce: PKCEPair,
        state: String,
        redirectURI: URL
    ) throws -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components.url else { throw GoogleOAuthError.invalidResponse }
        return url
    }
}

private actor OAuthLoopbackServer {
    private let expectedState: String
    private let queue = DispatchQueue(label: "com.burakerenoglu.AnalyticsBar.oauth-loopback")
    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<URL, Error>?
    private var codeContinuation: CheckedContinuation<String, Error>?
    private var pendingResult: Result<String, Error>?
    private var completed = false

    init(expectedState: String) {
        self.expectedState = expectedState
    }

    func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: .any
        )
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak listener] state in
            Task { await self.handleState(state, listener: listener) }
        }
        listener.newConnectionHandler = { connection in
            Task { await self.accept(connection) }
        }
        listener.start(queue: queue)

        return try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
        }
    }

    func waitForCode() async throws -> String {
        if let pendingResult {
            self.pendingResult = nil
            return try pendingResult.get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            codeContinuation = continuation
            Task {
                try? await Task.sleep(for: .seconds(180))
                self.finish(.failure(GoogleOAuthError.timeout))
            }
        }
    }

    func cancel() {
        finish(.failure(GoogleOAuthError.cancelled))
    }

    private func handleState(_ state: NWListener.State, listener: NWListener?) {
        switch state {
        case .ready:
            guard let port = listener?.port,
                  let url = URL(string: "http://127.0.0.1:\(port.rawValue)/oauth/callback") else {
                startContinuation?.resume(throwing: GoogleOAuthError.listenerFailed)
                startContinuation = nil
                return
            }
            startContinuation?.resume(returning: url)
            startContinuation = nil
        case .failed:
            startContinuation?.resume(throwing: GoogleOAuthError.listenerFailed)
            startContinuation = nil
            finish(.failure(GoogleOAuthError.listenerFailed))
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, error in
            Task { await self.handle(data: data, error: error, connection: connection) }
        }
    }

    private func handle(data: Data?, error: NWError?, connection: NWConnection) {
        guard error == nil,
              let data,
              let request = String(data: data, encoding: .utf8),
              let firstLine = request.split(separator: "\r\n", maxSplits: 1).first else {
            sendResponse(success: false, connection: connection)
            return
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(success: false, connection: connection)
            return
        }

        do {
            let code = try OAuthCallbackParser.parse(
                target: String(parts[1]),
                expectedState: expectedState
            )
            sendResponse(success: true, connection: connection)
            finish(.success(code))
        } catch {
            sendResponse(success: false, connection: connection)
            finish(.failure(error))
        }
    }

    private func sendResponse(success: Bool, connection: NWConnection) {
        let message = success
            ? "Authorization complete. You can close this window and return to Analytics Bar."
            : "Authorization could not be completed. Return to Analytics Bar and try again."
        let body = "<html><body><h2>Analytics Bar</h2><p>\(message)</p></body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ result: Result<String, Error>) {
        guard !completed else { return }
        completed = true
        listener?.cancel()
        listener = nil
        if let continuation = codeContinuation {
            codeContinuation = nil
            continuation.resume(with: result)
        } else {
            pendingResult = result
        }
    }
}
