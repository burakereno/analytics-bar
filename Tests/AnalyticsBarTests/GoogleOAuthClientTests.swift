import Foundation
import XCTest
@testable import AnalyticsBar

final class GoogleOAuthClientTests: XCTestCase {
    func testSignInExchangesCodeAndStoresToken() async throws {
        let tokenStore = InMemoryTokenStore()
        let codeProvider = TestAuthorizationCodeProvider(
            result: OAuthAuthorizationCode(
                code: "authorization-code",
                redirectURI: URL(string: "http://127.0.0.1:54321/oauth/callback")!
            )
        )
        let clientURL = URL(string: "https://oauth2.googleapis.com/token")!
        let http = TestHTTPClient { request in
            let data = Data("""
            {"access_token":"access-one","refresh_token":"refresh-one","expires_in":3600,"token_type":"Bearer","scope":"https://www.googleapis.com/auth/analytics.readonly"}
            """.utf8)
            return (data, TestHTTPClient.response(url: clientURL, status: 200))
        }
        let client = GoogleOAuthClient(
            configuration: .test,
            tokenStore: tokenStore,
            httpClient: http,
            authorizationCodeProvider: codeProvider,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let token = try await client.signIn()

        XCTAssertEqual(token.accessToken, "access-one")
        XCTAssertEqual(token.refreshToken, "refresh-one")
        XCTAssertEqual(token.expiresAt, Date(timeIntervalSince1970: 4_600))
        XCTAssertEqual(try tokenStore.load(), token)

        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.url, clientURL)
        XCTAssertEqual(request.httpMethod, "POST")
        let fields = formFields(from: request)
        XCTAssertEqual(fields["code"], "authorization-code")
        XCTAssertEqual(fields["client_id"], "client-id")
        XCTAssertEqual(fields["client_secret"], "client-secret")
        XCTAssertEqual(fields["redirect_uri"], "http://127.0.0.1:54321/oauth/callback")
        XCTAssertEqual(fields["grant_type"], "authorization_code")
        XCTAssertNotNil(fields["code_verifier"])
    }

    func testExpiredTokenRefreshPreservesRefreshToken() async throws {
        let existing = GoogleOAuthToken(
            accessToken: "expired",
            refreshToken: "refresh-one",
            tokenType: "Bearer",
            scope: AppConfiguration.analyticsReadonlyScope,
            expiresAt: Date(timeIntervalSince1970: 1_001)
        )
        let tokenStore = InMemoryTokenStore(token: existing)
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        let http = TestHTTPClient { _ in
            let data = Data("""
            {"access_token":"access-two","expires_in":3600,"token_type":"Bearer","scope":"https://www.googleapis.com/auth/analytics.readonly"}
            """.utf8)
            return (data, TestHTTPClient.response(url: tokenURL, status: 200))
        }
        let client = GoogleOAuthClient(
            configuration: .test,
            tokenStore: tokenStore,
            httpClient: http,
            authorizationCodeProvider: TestAuthorizationCodeProvider(result: nil),
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        let accessToken = try await client.validAccessToken()
        XCTAssertEqual(accessToken, "access-two")
        XCTAssertEqual(try tokenStore.load()?.refreshToken, "refresh-one")
        XCTAssertEqual(formFields(from: try XCTUnwrap(http.requests.first))["grant_type"], "refresh_token")
    }

    func testInvalidGrantRequiresAuthorizationAgain() async throws {
        let existing = GoogleOAuthToken(
            accessToken: "expired",
            refreshToken: "refresh-one",
            tokenType: "Bearer",
            scope: AppConfiguration.analyticsReadonlyScope,
            expiresAt: .distantPast
        )
        let tokenStore = InMemoryTokenStore(token: existing)
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        let http = TestHTTPClient { _ in
            let data = Data("{\"error\":\"invalid_grant\"}".utf8)
            return (data, TestHTTPClient.response(url: tokenURL, status: 400))
        }
        let client = GoogleOAuthClient(
            configuration: .test,
            tokenStore: tokenStore,
            httpClient: http,
            authorizationCodeProvider: TestAuthorizationCodeProvider(result: nil)
        )

        do {
            _ = try await client.validAccessToken()
            XCTFail("Expected authorizationExpired")
        } catch {
            XCTAssertEqual(error as? GoogleOAuthError, .authorizationExpired)
        }
    }

    private func formFields(from request: URLRequest) -> [String: String] {
        let value = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        var components = URLComponents()
        components.query = value
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}

private struct TestAuthorizationCodeProvider: AuthorizationCodeProviding {
    let result: OAuthAuthorizationCode?

    func authorizationCode(
        configuration: GoogleOAuthConfiguration,
        pkce: PKCEPair,
        state: String
    ) async throws -> OAuthAuthorizationCode {
        guard let result else { throw GoogleOAuthError.cancelled }
        return result
    }
}

private extension GoogleOAuthConfiguration {
    static let test = GoogleOAuthConfiguration(
        clientID: "client-id",
        clientSecret: "client-secret",
        scope: AppConfiguration.analyticsReadonlyScope
    )
}
