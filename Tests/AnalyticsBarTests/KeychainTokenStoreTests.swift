import XCTest
@testable import AnalyticsBar

final class KeychainTokenStoreTests: XCTestCase {
    private var store: KeychainTokenStore!

    override func setUp() {
        super.setUp()
        store = KeychainTokenStore(
            service: "AnalyticsBarTests.\(UUID().uuidString)",
            account: "primary"
        )
    }

    override func tearDown() {
        try? store.delete()
        store = nil
        super.tearDown()
    }

    func testSaveReplaceLoadAndDelete() throws {
        let first = GoogleOAuthToken(
            accessToken: "access-one",
            refreshToken: "refresh-one",
            tokenType: "Bearer",
            scope: AppConfiguration.analyticsReadonlyScope,
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        )
        let second = GoogleOAuthToken(
            accessToken: "access-two",
            refreshToken: "refresh-one",
            tokenType: "Bearer",
            scope: AppConfiguration.analyticsReadonlyScope,
            expiresAt: Date(timeIntervalSince1970: 2_000_003_600)
        )

        XCTAssertNil(try store.load())
        try store.save(first)
        XCTAssertEqual(try store.load(), first)
        try store.save(second)
        XCTAssertEqual(try store.load(), second)
        try store.delete()
        XCTAssertNil(try store.load())
    }
}
