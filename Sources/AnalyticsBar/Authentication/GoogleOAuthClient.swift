import Foundation

actor GoogleOAuthClient {
    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval
        let tokenType: String
        let scope: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
            case scope
        }
    }

    private struct OAuthErrorResponse: Decodable {
        let error: String
    }

    private let configuration: GoogleOAuthConfiguration
    private let tokenStore: any TokenStore
    private let httpClient: any HTTPClient
    private let authorizationCodeProvider: any AuthorizationCodeProviding
    private let now: @Sendable () -> Date
    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    init(
        configuration: GoogleOAuthConfiguration,
        tokenStore: any TokenStore,
        httpClient: any HTTPClient,
        authorizationCodeProvider: any AuthorizationCodeProviding = SystemAuthorizationCodeProvider(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.httpClient = httpClient
        self.authorizationCodeProvider = authorizationCodeProvider
        self.now = now
    }

    func signIn() async throws -> GoogleOAuthToken {
        let pkce = PKCE.generate()
        let state = UUID().uuidString
        let authorization = try await authorizationCodeProvider.authorizationCode(
            configuration: configuration,
            pkce: pkce,
            state: state
        )
        let response = try await tokenRequest(fields: [
            "code": authorization.code,
            "client_id": configuration.clientID,
            "client_secret": configuration.clientSecret,
            "code_verifier": pkce.verifier,
            "redirect_uri": authorization.redirectURI.absoluteString,
            "grant_type": "authorization_code"
        ])
        guard let refreshToken = response.refreshToken, !refreshToken.isEmpty else {
            throw GoogleOAuthError.invalidResponse
        }
        let token = makeToken(from: response, refreshToken: refreshToken)
        try tokenStore.save(token)
        return token
    }

    func validAccessToken() async throws -> String {
        guard let token = try tokenStore.load() else {
            throw GoogleOAuthError.authorizationExpired
        }
        guard token.isExpired(at: now()) else { return token.accessToken }
        return try await refreshAccessToken(using: token).accessToken
    }

    func forceRefreshAccessToken() async throws -> String {
        guard let token = try tokenStore.load() else {
            throw GoogleOAuthError.authorizationExpired
        }
        return try await refreshAccessToken(using: token).accessToken
    }

    func hasStoredAuthorization() -> Bool {
        (try? tokenStore.load()) != nil
    }

    func signOut() throws {
        try tokenStore.delete()
    }

    private func refreshAccessToken(using existing: GoogleOAuthToken) async throws -> GoogleOAuthToken {
        let response = try await tokenRequest(fields: [
            "client_id": configuration.clientID,
            "client_secret": configuration.clientSecret,
            "refresh_token": existing.refreshToken,
            "grant_type": "refresh_token"
        ])
        let token = makeToken(
            from: response,
            refreshToken: response.refreshToken ?? existing.refreshToken
        )
        try tokenStore.save(token)
        return token
    }

    private func tokenRequest(fields: [String: String]) async throws -> TokenResponse {
        var components = URLComponents()
        components.queryItems = fields
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 400,
               let oauthError = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data),
               oauthError.error == "invalid_grant" {
                throw GoogleOAuthError.authorizationExpired
            }
            throw GoogleOAuthError.httpStatus(response.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw GoogleOAuthError.invalidResponse
        }
        return decoded
    }

    private func makeToken(from response: TokenResponse, refreshToken: String) -> GoogleOAuthToken {
        GoogleOAuthToken(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            tokenType: response.tokenType,
            scope: response.scope ?? configuration.scope,
            expiresAt: now().addingTimeInterval(response.expiresIn)
        )
    }
}
