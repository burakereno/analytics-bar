import Foundation
import XCTest
@testable import AnalyticsBar

final class AnalyticsDataClientTests: XCTestCase {
    func testRealtimeRequestAndHeaderDrivenResponse() async throws {
        let http = TestHTTPClient { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.absoluteString, "https://analyticsdata.googleapis.com/v1beta/properties/101:runRealtimeReport")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")

            let body = try XCTUnwrap(request.httpBody)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let metrics = try XCTUnwrap(object["metrics"] as? [[String: String]])
            XCTAssertEqual(metrics.compactMap { $0["name"] }, ["activeUsers", "screenPageViews", "eventCount", "keyEvents"])

            let json = """
            {
              "metricHeaders":[
                {"name":"keyEvents","type":"TYPE_FLOAT"},
                {"name":"eventCount","type":"TYPE_INTEGER"},
                {"name":"activeUsers","type":"TYPE_INTEGER"},
                {"name":"screenPageViews","type":"TYPE_INTEGER"}
              ],
              "rows":[{"metricValues":[{"value":"2.5"},{"value":"40"},{"value":"12"},{"value":"30"}]}],
              "rowCount":1
            }
            """
            return (Data(json.utf8), TestHTTPClient.response(url: url, status: 200))
        }
        let client = AnalyticsDataClient(httpClient: http, retryPolicy: .immediate)

        let totals = try await client.fetchRealtime(property: property, accessToken: "access")

        XCTAssertEqual(totals, RealtimeTotals(activeUsers: 12, views: 30, eventCount: 40, keyEvents: 2.5))
    }

    func testCoreBatchBuildsFourReportsAndUsesCompletedPropertyHour() async throws {
        let http = TestHTTPClient { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.absoluteString, "https://analyticsdata.googleapis.com/v1beta/properties/101:batchRunReports")
            let body = try XCTUnwrap(request.httpBody)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual((object["requests"] as? [Any])?.count, 4)

            let json = """
            {
              "reports":[
                {
                  "dimensionHeaders":[{"name":"dateRange"},{"name":"dateHour"}],
                  "metricHeaders":[
                    {"name":"activeUsers","type":"TYPE_INTEGER"},
                    {"name":"sessions","type":"TYPE_INTEGER"},
                    {"name":"screenPageViews","type":"TYPE_INTEGER"},
                    {"name":"eventCount","type":"TYPE_INTEGER"},
                    {"name":"keyEvents","type":"TYPE_FLOAT"},
                    {"name":"totalRevenue","type":"TYPE_CURRENCY"}
                  ],
                  "rows":[
                    {"dimensionValues":[{"value":"date_range_0"},{"value":"2026081014"}],"metricValues":[{"value":"5"},{"value":"6"},{"value":"7"},{"value":"8"},{"value":"9"},{"value":"10"}]},
                    {"dimensionValues":[{"value":"date_range_0"},{"value":"2026081015"}],"metricValues":[{"value":"50"},{"value":"60"},{"value":"70"},{"value":"80"},{"value":"90"},{"value":"100"}]},
                    {"dimensionValues":[{"value":"date_range_1"},{"value":"2026080914"}],"metricValues":[{"value":"2"},{"value":"3"},{"value":"4"},{"value":"5"},{"value":"6"},{"value":"7"}]},
                    {"dimensionValues":[{"value":"date_range_1"},{"value":"2026080915"}],"metricValues":[{"value":"20"},{"value":"30"},{"value":"40"},{"value":"50"},{"value":"60"},{"value":"70"}]}
                  ]
                },
                {
                  "dimensionHeaders":[{"name":"date"}],
                  "metricHeaders":[{"name":"activeUsers","type":"TYPE_INTEGER"},{"name":"sessions","type":"TYPE_INTEGER"},{"name":"screenPageViews","type":"TYPE_INTEGER"},{"name":"eventCount","type":"TYPE_INTEGER"},{"name":"keyEvents","type":"TYPE_FLOAT"},{"name":"totalRevenue","type":"TYPE_CURRENCY"}],
                  "rows":[{"dimensionValues":[{"value":"20260809"}],"metricValues":[{"value":"11"},{"value":"12"},{"value":"13"},{"value":"14"},{"value":"15"},{"value":"16"}]}]
                },
                {
                  "dimensionHeaders":[{"name":"unifiedPagePathScreen"}],
                  "metricHeaders":[{"name":"screenPageViews","type":"TYPE_INTEGER"}],
                  "rows":[{"dimensionValues":[{"value":"/pricing"}],"metricValues":[{"value":"842"}]}]
                },
                {
                  "dimensionHeaders":[{"name":"sessionPrimaryChannelGroup"}],
                  "metricHeaders":[{"name":"sessions","type":"TYPE_INTEGER"}],
                  "rows":[{"dimensionValues":[{"value":"Organic Search"}],"metricValues":[{"value":"713"}]}]
                }
              ]
            }
            """
            return (Data(json.utf8), TestHTTPClient.response(url: url, status: 200))
        }
        let client = AnalyticsDataClient(httpClient: http, retryPolicy: .immediate)
        let now = ISO8601DateFormatter().date(from: "2026-08-10T12:30:00Z")!

        let report = try await client.fetchCore(property: property, now: now, accessToken: "access")

        XCTAssertEqual(report.today.activeUsers, 5)
        XCTAssertEqual(report.today.sessions, 6)
        XCTAssertEqual(report.yesterdayThroughSameHour.activeUsers, 2)
        XCTAssertEqual(report.sevenDay[try AnalyticsDay(gaValue: "20260809")]?.sessions, 12)
        XCTAssertEqual(report.topPages, [RankedDimensionRow(label: "/pricing", value: 842)])
        XCTAssertEqual(report.topSources, [RankedDimensionRow(label: "Organic Search", value: 713)])
    }

    func testRetriesRateLimitThenSucceeds() async throws {
        let attempts = AttemptCounter()
        let http = TestHTTPClient { request in
            let attempt = attempts.increment()
            if attempt == 1 {
                return (
                    Data(),
                    TestHTTPClient.response(url: request.url!, status: 429, headers: ["Retry-After": "1"])
                )
            }
            let json = "{\"metricHeaders\":[{\"name\":\"activeUsers\"},{\"name\":\"screenPageViews\"},{\"name\":\"eventCount\"},{\"name\":\"keyEvents\"}],\"rows\":[{\"metricValues\":[{\"value\":\"1\"},{\"value\":\"2\"},{\"value\":\"3\"},{\"value\":\"4\"}]}]}"
            return (Data(json.utf8), TestHTTPClient.response(url: request.url!, status: 200))
        }
        let client = AnalyticsDataClient(httpClient: http, retryPolicy: .immediate)

        let totals = try await client.fetchRealtime(property: property, accessToken: "access")

        XCTAssertEqual(totals.activeUsers, 1)
        XCTAssertEqual(attempts.value, 2)
    }

    private var property: AnalyticsProperty {
        AnalyticsProperty(
            id: "101",
            resourceName: "properties/101",
            accountResourceName: "accounts/1",
            accountDisplayName: "Personal",
            displayName: "Blog",
            timeZoneIdentifier: "Europe/Istanbul",
            currencyCode: "TRY"
        )
    }
}

private final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0

    var value: Int { lock.withLock { attempts } }

    func increment() -> Int {
        lock.withLock {
            attempts += 1
            return attempts
        }
    }
}
