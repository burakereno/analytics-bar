import XCTest
@testable import AnalyticsBar

final class OAuthCallbackParserTests: XCTestCase {
    func testAcceptsMatchingStateAndCode() throws {
        XCTAssertEqual(
            try OAuthCallbackParser.parse(
                target: "/oauth/callback?code=abc&state=expected",
                expectedState: "expected"
            ),
            "abc"
        )
    }

    func testRejectsWrongState() {
        XCTAssertThrowsError(
            try OAuthCallbackParser.parse(
                target: "/oauth/callback?code=abc&state=wrong",
                expectedState: "expected"
            )
        ) { error in
            XCTAssertEqual(error as? GoogleOAuthError, .stateMismatch)
        }
    }

    func testMapsAccessDeniedToCancellation() {
        XCTAssertThrowsError(
            try OAuthCallbackParser.parse(
                target: "/oauth/callback?error=access_denied&state=expected",
                expectedState: "expected"
            )
        ) { error in
            XCTAssertEqual(error as? GoogleOAuthError, .cancelled)
        }
    }
}
