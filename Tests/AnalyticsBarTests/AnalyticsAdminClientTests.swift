import Foundation
import XCTest
@testable import AnalyticsBar

final class AnalyticsAdminClientTests: XCTestCase {
    func testListsAllPagesAndEnrichesPropertyMetadata() async throws {
        let http = TestHTTPClient { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")

            if url.path == "/v1alpha/accountSummaries" {
                let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "pageToken" })?.value
                let json: String
                if token == "next" {
                    json = """
                    {"accountSummaries":[{"account":"accounts/2","displayName":"Work","propertySummaries":[{"property":"properties/202","displayName":"Shop"}]}]}
                    """
                } else {
                    json = """
                    {"accountSummaries":[{"account":"accounts/1","displayName":"Personal","propertySummaries":[{"property":"properties/101","displayName":"Blog"}]}],"nextPageToken":"next"}
                    """
                }
                return (Data(json.utf8), TestHTTPClient.response(url: url, status: 200))
            }

            switch url.path {
            case "/v1beta/properties/101":
                return (
                    Data("{\"name\":\"properties/101\",\"timeZone\":\"Europe/Istanbul\",\"currencyCode\":\"TRY\"}".utf8),
                    TestHTTPClient.response(url: url, status: 200)
                )
            case "/v1beta/properties/202":
                return (
                    Data("{\"name\":\"properties/202\",\"timeZone\":\"America/New_York\",\"currencyCode\":\"USD\"}".utf8),
                    TestHTTPClient.response(url: url, status: 200)
                )
            default:
                XCTFail("Unexpected URL: \(url)")
                return (Data(), TestHTTPClient.response(url: url, status: 404))
            }
        }
        let client = AnalyticsAdminClient(httpClient: http)

        let properties = try await client.listProperties(accessToken: "access")

        XCTAssertEqual(properties.map(\.resourceName), ["properties/101", "properties/202"])
        XCTAssertEqual(properties[0].accountDisplayName, "Personal")
        XCTAssertEqual(properties[0].timeZoneIdentifier, "Europe/Istanbul")
        XCTAssertEqual(properties[0].currencyCode, "TRY")
        XCTAssertEqual(properties[1].accountDisplayName, "Work")
        XCTAssertEqual(properties[1].timeZoneIdentifier, "America/New_York")
    }

    func testMapsUnauthorizedResponse() async throws {
        let http = TestHTTPClient { request in
            (Data(), TestHTTPClient.response(url: request.url!, status: 401))
        }
        let client = AnalyticsAdminClient(httpClient: http)

        do {
            _ = try await client.listProperties(accessToken: "expired")
            XCTFail("Expected authorization error")
        } catch {
            XCTAssertEqual(error as? GoogleAPIError, .authorizationExpired)
        }
    }
}
