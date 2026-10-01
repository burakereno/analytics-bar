import Foundation

protocol AnalyticsDataClientProtocol: Sendable {
    func fetchRealtime(
        property: AnalyticsProperty,
        accessToken: String
    ) async throws -> RealtimeTotals

    func fetchCore(
        property: AnalyticsProperty,
        now: Date,
        accessToken: String
    ) async throws -> PropertyCoreReport
}

struct AnalyticsRetryPolicy: Sendable {
    let maximumAttempts: Int
    let sleep: @Sendable (TimeInterval) async -> Void

    static let live = AnalyticsRetryPolicy(maximumAttempts: 3) { seconds in
        let duration = max(0, seconds)
        try? await Task.sleep(for: .seconds(duration))
    }

    static let immediate = AnalyticsRetryPolicy(maximumAttempts: 3) { _ in }
}

struct AnalyticsDataClient: AnalyticsDataClientProtocol, Sendable {
    private let httpClient: any HTTPClient
    private let retryPolicy: AnalyticsRetryPolicy
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        httpClient: any HTTPClient,
        retryPolicy: AnalyticsRetryPolicy = .live
    ) {
        self.httpClient = httpClient
        self.retryPolicy = retryPolicy
    }

    func fetchRealtime(
        property: AnalyticsProperty,
        accessToken: String
    ) async throws -> RealtimeTotals {
        let url = try endpoint(property: property, method: "runRealtimeReport")
        let data = try await post(
            url: url,
            body: AnalyticsDataRequestFactory.realtime(),
            accessToken: accessToken
        )
        let response: AnalyticsReportResponse = try decode(data)
        let rows = response.rows ?? []
        let realtimeKind = "analyticsData#runRealtimeReport"
        guard response.kind == nil || response.kind == realtimeKind,
              rows.count <= 1, (response.rowCount ?? rows.count) == rows.count else {
            throw GoogleAPIError.invalidResponse
        }
        // Google omits both rows and headers when realtime activity is absent.
        // Require the realtime resource kind before accepting this sparse response as zero.
        if rows.isEmpty, response.kind == realtimeKind, (response.metricHeaders ?? []).isEmpty {
            return .zero
        }
        let table = try AnalyticsReportTable(response: response)
        try table.requireHeaders(metrics: ["activeUsers", "screenPageViews", "eventCount", "keyEvents"])
        guard let row = table.rows.first else { return .zero }
        return RealtimeTotals(
            activeUsers: try table.integer("activeUsers", in: row),
            views: try table.integer("screenPageViews", in: row),
            eventCount: try table.integer("eventCount", in: row),
            keyEvents: try table.decimal("keyEvents", in: row)
        )
    }

    func fetchCore(
        property: AnalyticsProperty,
        now: Date,
        accessToken: String
    ) async throws -> PropertyCoreReport {
        let url = try endpoint(property: property, method: "batchRunReports")
        let cutoffHour = completedHour(now: now, timeZoneIdentifier: property.timeZoneIdentifier)
        let data = try await post(
            url: url,
            body: AnalyticsDataRequestFactory.coreBatch(completedHour: cutoffHour),
            accessToken: accessToken
        )
        let response: AnalyticsBatchReportResponse = try decode(data)
        guard response.reports.count == 5 else { throw GoogleAPIError.invalidResponse }

        let daily = try AnalyticsReportTable(response: response.reports[0])
        let trend = try AnalyticsReportTable(response: response.reports[1])
        let pages = try AnalyticsReportTable(response: response.reports[2])
        let sources = try AnalyticsReportTable(response: response.reports[3])
        let comparison = try AnalyticsReportTable(response: response.reports[4])
        try daily.requireHeaders(metrics: AnalyticsDataRequestFactory.coreMetrics, dimensions: ["dateRange"])
        try comparison.requireHeaders(metrics: AnalyticsDataRequestFactory.coreMetrics, dimensions: ["dateRange"])
        try trend.requireHeaders(metrics: AnalyticsDataRequestFactory.coreMetrics, dimensions: ["date"])
        try pages.requireHeaders(metrics: ["screenPageViews"], dimensions: ["unifiedPagePathScreen"])
        try sources.requireHeaders(metrics: ["sessions"], dimensions: ["sessionPrimaryChannelGroup"])

        let today = try totals(in: daily, dateRange: "date_range_0")
        let todayCompared = cutoffHour < 0 ? .zero : try totals(in: comparison, dateRange: "date_range_0")
        let yesterday = cutoffHour < 0 ? .zero : try totals(in: comparison, dateRange: "date_range_1")

        var reportedDays: [AnalyticsDay: MetricTotals] = [:]
        for row in trend.rows {
            let day = try AnalyticsDay(gaValue: trend.dimension("date", in: row))
            guard reportedDays[day] == nil else { throw GoogleAPIError.invalidResponse }
            reportedDays[day] = try trend.metricTotals(in: row)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: property.timeZoneIdentifier) ?? .gmt
        var sevenDay: [AnalyticsDay: MetricTotals] = [:]
        var previousWeekSessions = 0
        for offset in 1...14 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else {
                throw GoogleAPIError.invalidResponse
            }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let day = AnalyticsDay(year: parts.year!, month: parts.month!, day: parts.day!)
            let value = reportedDays[day] ?? .zero
            if offset <= 7 { sevenDay[day] = value }
            else { previousWeekSessions += value.sessions }
        }

        return PropertyCoreReport(
            today: today,
            yesterdayThroughSameHour: yesterday,
            sevenDay: sevenDay,
            topPages: try rankedRows(
                table: pages,
                dimension: "unifiedPagePathScreen",
                metric: "screenPageViews"
            ),
            topSources: try rankedRows(
                table: sources,
                dimension: "sessionPrimaryChannelGroup",
                metric: "sessions"
            ),
            todayThroughSameHour: todayCompared,
            weeklySessions: sevenDay.values.reduce(0) { $0 + $1.sessions },
            previousWeekSessions: previousWeekSessions
        )
    }

    private func totals(in table: AnalyticsReportTable, dateRange: String) throws -> MetricTotals {
        // The API aggregates users over the entire filtered period; never sum hourly distinct users.
        var result: MetricTotals?
        for row in table.rows {
            let range = try table.dimension("dateRange", in: row)
            guard ["date_range_0", "date_range_1"].contains(range) else { throw GoogleAPIError.invalidResponse }
            if range == dateRange {
                guard result == nil else { throw GoogleAPIError.invalidResponse }
                result = try table.metricTotals(in: row)
            }
        }
        return result ?? .zero
    }

    private func rankedRows(
        table: AnalyticsReportTable,
        dimension: String,
        metric: String
    ) throws -> [RankedDimensionRow] {
        try table.rows.map {
            RankedDimensionRow(
                label: try table.dimension(dimension, in: $0),
                value: try table.decimal(metric, in: $0)
            )
        }
    }

    private func completedHour(now: Date, timeZoneIdentifier: String) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        return (calendar.dateComponents([.hour], from: now).hour ?? 0) - 1
    }

    private func endpoint(property: AnalyticsProperty, method: String) throws -> URL {
        guard !property.id.isEmpty, property.id.allSatisfy(\.isNumber),
              let url = URL(
                string: "https://analyticsdata.googleapis.com/v1beta/properties/\(property.id):\(method)"
              ) else {
            throw GoogleAPIError.invalidResponse
        }
        return url
    }

    private func post<Body: Encodable>(
        url: URL,
        body: Body,
        accessToken: String
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("AnalyticsBar/0.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try encoder.encode(body)

        var attempt = 0
        while true {
            attempt += 1
            let (data, response) = try await httpClient.data(for: request)
            if let error = GoogleHTTPStatusMapper.error(for: response, data: data) {
                let retryDelay: TimeInterval?
                switch error {
                case let .rateLimited(retryAfter):
                    retryDelay = retryAfter ?? pow(2, Double(attempt - 1))
                case .server:
                    retryDelay = pow(2, Double(attempt - 1))
                default:
                    retryDelay = nil
                }
                if let retryDelay, attempt < retryPolicy.maximumAttempts {
                    await retryPolicy.sleep(retryDelay)
                    continue
                }
                throw error
            }
            return data
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GoogleAPIError.invalidResponse
        }
    }
}
