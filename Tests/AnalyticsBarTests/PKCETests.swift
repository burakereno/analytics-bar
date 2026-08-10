import XCTest
@testable import AnalyticsBar

final class PKCETests: XCTestCase {
    func testRFC7636ChallengeVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

        XCTAssertEqual(
            PKCE.challenge(for: verifier),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testGeneratedPairUsesURLSafeVerifier() {
        let pair = PKCE.generate()

        XCTAssertGreaterThanOrEqual(pair.verifier.count, 43)
        XCTAssertLessThanOrEqual(pair.verifier.count, 128)
        XCTAssertFalse(pair.verifier.contains("="))
        XCTAssertEqual(pair.challenge, PKCE.challenge(for: pair.verifier))
    }
}
