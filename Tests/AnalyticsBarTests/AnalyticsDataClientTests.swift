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

    func testCoreUsesDistinctDailyUsersAndSeparateCompletedHourComparison() async throws {
        let http = TestHTTPClient { request in
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.absoluteString, "https://analyticsdata.googleapis.com/v1beta/properties/101:batchRunReports")
            let body = try XCTUnwrap(request.httpBody)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let requests = try XCTUnwrap(object["requests"] as? [[String: Any]])
            XCTAssertEqual(requests.count, 5)
            XCTAssertNil(requests[0]["dimensions"])
            XCTAssertNil(requests[0]["dimensionFilter"])
            XCTAssertNil(requests[4]["dimensions"])
            let expression = try XCTUnwrap(requests[4]["dimensionFilter"] as? [String: Any])
            let filter = try XCTUnwrap(expression["filter"] as? [String: Any])
            let list = try XCTUnwrap(filter["inListFilter"] as? [String: Any])
            XCTAssertEqual(filter["fieldName"] as? String, "hour")
            XCTAssertEqual(list["values"] as? [String], (0...14).map { String(format: "%02d", $0) })
            let ranges = try XCTUnwrap(requests[1]["dateRanges"] as? [[String: String]])
            XCTAssertEqual(ranges, [["startDate": "14daysAgo", "endDate": "yesterday"]])
            for (index, metricName) in [(2, "screenPageViews"), (3, "sessions")] {
                XCTAssertEqual(requests[index]["limit"] as? String, "5")
                let order = try XCTUnwrap(requests[index]["orderBys"] as? [[String: Any]])
                let metric = try XCTUnwrap(order.first?["metric"] as? [String: Any])
                XCTAssertEqual(metric["metricName"] as? String, metricName)
            }
            return (try Self.coreResponse(), TestHTTPClient.response(url: url, status: 200))
        }
        let client = AnalyticsDataClient(httpClient: http, retryPolicy: .immediate)
        let now = ISO8601DateFormatter().date(from: "2026-08-10T12:30:00Z")!
        let report = try await client.fetchCore(property: property, now: now, accessToken: "access")

        XCTAssertEqual(report.today.activeUsers, 9, "Use Google's daily distinct count, including the current hour")
        XCTAssertEqual(report.todayThroughSameHour?.activeUsers, 5)
        XCTAssertEqual(report.yesterdayThroughSameHour.activeUsers, 2)
        XCTAssertEqual(report.sevenDay.count, 7, "Include zero-traffic days")
        XCTAssertEqual(report.sevenDay[try AnalyticsDay(gaValue: "20260809")]?.sessions, 12)
        XCTAssertNil(report.sevenDay[try AnalyticsDay(gaValue: "20260802")])
        XCTAssertEqual(report.weeklySessions, 12)
        XCTAssertEqual(report.previousWeekSessions, 8)
        XCTAssertEqual(report.topPages, [RankedDimensionRow(label: "/pricing", value: 842)])
        XCTAssertEqual(report.topSources, [RankedDimensionRow(label: "Organic Search", value: 713)])
    }

    func testMidnightRetainsTodayButHasNoCompletedHourComparison() async throws {
        let http = TestHTTPClient { request in
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            let requests = try XCTUnwrap(object["requests"] as? [[String: Any]])
            let filter = try XCTUnwrap(requests[4]["dimensionFilter"] as? [String: Any])
            let inner = try XCTUnwrap(filter["filter"] as? [String: Any])
            let list = try XCTUnwrap(inner["inListFilter"] as? [String: Any])
            XCTAssertEqual(list["values"] as? [String], ["24"])
            return (try Self.coreResponse(), TestHTTPClient.response(url: request.url!, status: 200))
        }
        let now = ISO8601DateFormatter().date(from: "2026-08-10T21:30:00Z")!
        let report = try await AnalyticsDataClient(httpClient: http).fetchCore(property: property, now: now, accessToken: "access")
        XCTAssertEqual(report.today.activeUsers, 9)
        XCTAssertEqual(report.todayThroughSameHour, .zero)
        XCTAssertEqual(report.yesterdayThroughSameHour, .zero)
    }

    func testSuccessfulEmptyRealtimeIsZeroButMissingHeadersIsInvalid() async throws {
        let valid = TestHTTPClient { request in
            let data = try JSONSerialization.data(withJSONObject: ["metricHeaders":
                ["activeUsers", "screenPageViews", "eventCount", "keyEvents"].map { ["name": $0] }])
            return (data, TestHTTPClient.response(url: request.url!, status: 200))
        }
        let zero = try await AnalyticsDataClient(httpClient: valid).fetchRealtime(property: property, accessToken: "access")
        XCTAssertEqual(zero, .zero)
        let invalid = TestHTTPClient { request in
            (Data("{}".utf8), TestHTTPClient.response(url: request.url!, status: 200))
        }
        do {
            _ = try await AnalyticsDataClient(httpClient: invalid).fetchRealtime(property: property, accessToken: "access")
            XCTFail("Malformed responses must not masquerade as zero traffic")
        } catch { XCTAssertEqual(error as? GoogleAPIError, .invalidResponse) }
    }

    func testGoogleMetadataOnlyRealtimeResponseMeansNoActivity() async throws {
        // Observed from the live API: successful empty reports contain only kind and quota.
        for explicitEmptyRows in [false, true] {
            let http = TestHTTPClient { request in
                var payload: [String: Any] = [
                    "kind": "analyticsData#runRealtimeReport",
                    "propertyQuota": ["tokensPerHour": ["consumed": 1, "remaining": 39999]]
                ]
                if explicitEmptyRows { payload["rows"] = []; payload["rowCount"] = 0 }
                return (try JSONSerialization.data(withJSONObject: payload), TestHTTPClient.response(url: request.url!, status: 200))
            }
            let totals = try await AnalyticsDataClient(httpClient: http).fetchRealtime(property: property, accessToken: "access")
            XCTAssertEqual(totals, .zero)
        }
    }

    func testSparseRealtimeValidationRejectsWrongKindAndIncompletePopulatedReports() async throws {
        let payloads = [
            "{\"kind\":\"analyticsData#runReport\"}",
            "{\"kind\":\"analyticsData#runRealtimeReport\",\"rowCount\":1}",
            "{\"kind\":\"analyticsData#runRealtimeReport\",\"rows\":[{\"metricValues\":[{\"value\":\"1\"}]}]}",
            "{\"kind\":\"analyticsData#runRealtimeReport\",\"metricHeaders\":[{\"name\":\"activeUsers\"}]}",
            "{\"kind\":\"analyticsData#runRealtimeReport\",\"rows\":[{},{}]}"
        ]
        for payload in payloads {
            let http = TestHTTPClient { request in
                (Data(payload.utf8), TestHTTPClient.response(url: request.url!, status: 200))
            }
            do {
                _ = try await AnalyticsDataClient(httpClient: http).fetchRealtime(property: property, accessToken: "access")
                XCTFail("Incomplete or unrelated responses must not be accepted as zero traffic")
            } catch { XCTAssertEqual(error as? GoogleAPIError, .invalidResponse) }
        }
    }

    private static func coreResponse() throws -> Data {
        func report(_ dimensions: [String], _ metrics: [String], _ rows: [([String], [Int])]) -> [String: Any] {
            ["dimensionHeaders": dimensions.map { ["name": $0] },
             "metricHeaders": metrics.map { ["name": $0] },
             "rows": rows.map { row in
                 ["dimensionValues": row.0.map { ["value": $0] },
                  "metricValues": row.1.map { ["value": String($0)] }]
             }]
        }
        let metrics = AnalyticsDataRequestFactory.coreMetrics
        return try JSONSerialization.data(withJSONObject: ["reports": [
            report(["dateRange"], metrics, [(["date_range_0"], [9, 10, 11, 12, 1, 0])]),
            report(["date"], metrics, [(["20260809"], [11, 12, 13, 14, 1, 0]), (["20260802"], [7, 8, 9, 10, 0, 0])]),
            report(["unifiedPagePathScreen"], ["screenPageViews"], [(["/pricing"], [842])]),
            report(["sessionPrimaryChannelGroup"], ["sessions"], [(["Organic Search"], [713])]),
            report(["dateRange"], metrics, [(["date_range_0"], [5, 6, 7, 8, 1, 0]), (["date_range_1"], [2, 3, 4, 5, 0, 0])])
        ]])
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

    func testCoreBadRequestSurfacesGoogleMessage() async throws {
        let http = TestHTTPClient { request in
            let json = """
            {
              "error": {
                "code": 400,
                "message": "Metric totalRevenue is incompatible with dimension dateHour.",
                "status": "INVALID_ARGUMENT"
              }
            }
            """
            return (
                Data(json.utf8),
                TestHTTPClient.response(url: request.url!, status: 400)
            )
        }
        let client = AnalyticsDataClient(httpClient: http, retryPolicy: .immediate)

        do {
            _ = try await client.fetchCore(property: property, now: Date(), accessToken: "access")
            XCTFail("Expected the Google validation message")
        } catch {
            XCTAssertEqual(
                error as? GoogleAPIError,
                .badRequest("Metric totalRevenue is incompatible with dimension dateHour.")
            )
        }
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
