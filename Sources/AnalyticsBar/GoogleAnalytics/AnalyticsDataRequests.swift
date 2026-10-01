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
    struct Metric: Encodable, Sendable {
        let metricName: String
    }

    let metric: Metric
    let desc: Bool
}

struct AnalyticsRunReportRequest: Encodable, Sendable {
    struct HourFilter: Encodable, Sendable {
        struct Filter: Encodable, Sendable {
            struct InList: Encodable, Sendable { let values: [String] }
            let fieldName = "hour"
            let inListFilter: InList
        }
        let filter: Filter

        init(completedHour: Int) {
            // "24" matches no hour at midnight, before any hour has completed.
            let values = completedHour < 0 ? ["24"] : (0...min(23, completedHour)).map { String(format: "%02d", $0) }
            filter = Filter(inListFilter: Filter.InList(values: values))
        }
    }
    let dimensions: [AnalyticsNameRequest]?
    let metrics: [AnalyticsNameRequest]
    let dateRanges: [AnalyticsDateRangeRequest]
    let orderBys: [AnalyticsMetricOrderRequest]?
    let limit: String?
    let dimensionFilter: HourFilter?

    init(
        dimensions: [String] = [],
        metrics: [String],
        dateRanges: [AnalyticsDateRangeRequest],
        orderByMetric: String? = nil,
        limit: Int? = nil,
        completedHour: Int? = nil
    ) {
        self.dimensions = dimensions.isEmpty ? nil : dimensions.map(AnalyticsNameRequest.init)
        self.metrics = metrics.map(AnalyticsNameRequest.init)
        self.dateRanges = dateRanges
        if let orderByMetric {
            orderBys = [
                AnalyticsMetricOrderRequest(
                    metric: AnalyticsMetricOrderRequest.Metric(metricName: orderByMetric),
                    desc: true
                )
            ]
        } else {
            orderBys = nil
        }
        self.limit = limit.map(String.init)
        dimensionFilter = completedHour.map(HourFilter.init)
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

    static func coreBatch(completedHour: Int) -> AnalyticsBatchRunReportsRequest {
        AnalyticsBatchRunReportsRequest(
            requests: [
                AnalyticsRunReportRequest(
                    metrics: coreMetrics,
                    dateRanges: [
                        AnalyticsDateRangeRequest(startDate: "today", endDate: "today"),
                        AnalyticsDateRangeRequest(startDate: "yesterday", endDate: "yesterday")
                    ]
                ),
                AnalyticsRunReportRequest(
                    dimensions: ["date"],
                    metrics: coreMetrics,
                    dateRanges: [AnalyticsDateRangeRequest(startDate: "14daysAgo", endDate: "yesterday")]
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
                ),
                AnalyticsRunReportRequest(
                    metrics: coreMetrics,
                    dateRanges: [
                        AnalyticsDateRangeRequest(startDate: "today", endDate: "today"),
                        AnalyticsDateRangeRequest(startDate: "yesterday", endDate: "yesterday")
                    ],
                    completedHour: completedHour
                )
            ]
        )
    }
}
