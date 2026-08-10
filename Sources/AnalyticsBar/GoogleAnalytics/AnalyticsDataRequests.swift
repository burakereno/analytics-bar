import Foundation

struct AnalyticsNameRequest: Encodable, Sendable {
    let name: String
}

struct AnalyticsDateRangeRequest: Encodable, Sendable {
    let startDate: String
    let endDate: String
}

struct AnalyticsMinuteRangeRequest: Encodable, Sendable {
    let name: String
    let startMinutesAgo: Int
    let endMinutesAgo: Int
}

struct AnalyticsMetricOrderRequest: Encodable, Sendable {
    let metric: AnalyticsNameRequest
    let desc: Bool
}

struct AnalyticsRunReportRequest: Encodable, Sendable {
    let dimensions: [AnalyticsNameRequest]?
    let metrics: [AnalyticsNameRequest]
    let dateRanges: [AnalyticsDateRangeRequest]
    let orderBys: [AnalyticsMetricOrderRequest]?
    let limit: String?

    init(
        dimensions: [String] = [],
        metrics: [String],
        dateRanges: [AnalyticsDateRangeRequest],
        orderByMetric: String? = nil,
        limit: Int? = nil
    ) {
        self.dimensions = dimensions.isEmpty ? nil : dimensions.map(AnalyticsNameRequest.init)
        self.metrics = metrics.map(AnalyticsNameRequest.init)
        self.dateRanges = dateRanges
        if let orderByMetric {
            orderBys = [
                AnalyticsMetricOrderRequest(
                    metric: AnalyticsNameRequest(name: orderByMetric),
                    desc: true
                )
            ]
        } else {
            orderBys = nil
        }
        self.limit = limit.map(String.init)
    }
}

struct AnalyticsBatchRunReportsRequest: Encodable, Sendable {
    let requests: [AnalyticsRunReportRequest]
}

struct AnalyticsRealtimeReportRequest: Encodable, Sendable {
    let metrics: [AnalyticsNameRequest]
    let minuteRanges: [AnalyticsMinuteRangeRequest]
    let returnPropertyQuota: Bool
}

enum AnalyticsDataRequestFactory {
    static let coreMetrics = [
        "activeUsers",
        "sessions",
        "screenPageViews",
        "eventCount",
        "keyEvents",
        "totalRevenue"
    ]

    static func realtime() -> AnalyticsRealtimeReportRequest {
        AnalyticsRealtimeReportRequest(
            metrics: ["activeUsers", "screenPageViews", "eventCount", "keyEvents"]
                .map(AnalyticsNameRequest.init),
            minuteRanges: [
                AnalyticsMinuteRangeRequest(
                    name: "last30Minutes",
                    startMinutesAgo: 29,
                    endMinutesAgo: 0
                )
            ],
            returnPropertyQuota: true
        )
    }

    static func coreBatch() -> AnalyticsBatchRunReportsRequest {
        AnalyticsBatchRunReportsRequest(
            requests: [
                AnalyticsRunReportRequest(
                    dimensions: ["dateHour"],
                    metrics: coreMetrics,
                    dateRanges: [
                        AnalyticsDateRangeRequest(startDate: "today", endDate: "today"),
                        AnalyticsDateRangeRequest(startDate: "yesterday", endDate: "yesterday")
                    ]
                ),
                AnalyticsRunReportRequest(
                    dimensions: ["date"],
                    metrics: coreMetrics,
                    dateRanges: [AnalyticsDateRangeRequest(startDate: "7daysAgo", endDate: "today")]
                ),
                AnalyticsRunReportRequest(
                    dimensions: ["unifiedPagePathScreen"],
                    metrics: ["screenPageViews"],
                    dateRanges: [AnalyticsDateRangeRequest(startDate: "today", endDate: "today")],
                    orderByMetric: "screenPageViews",
                    limit: 5
                ),
                AnalyticsRunReportRequest(
                    dimensions: ["sessionPrimaryChannelGroup"],
                    metrics: ["sessions"],
                    dateRanges: [AnalyticsDateRangeRequest(startDate: "today", endDate: "today")],
                    orderByMetric: "sessions",
                    limit: 5
                )
            ]
        )
    }
}
