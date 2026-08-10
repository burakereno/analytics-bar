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
        let table = try AnalyticsReportTable(response: response)
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
        let data = try await post(
            url: url,
            body: AnalyticsDataRequestFactory.coreBatch(),
            accessToken: accessToken
        )
        let response: AnalyticsBatchReportResponse = try decode(data)
        guard response.reports.count == 4 else { throw GoogleAPIError.invalidResponse }

        let hourly = try AnalyticsReportTable(response: response.reports[0])
        let trend = try AnalyticsReportTable(response: response.reports[1])
        let pages = try AnalyticsReportTable(response: response.reports[2])
        let sources = try AnalyticsReportTable(response: response.reports[3])
        let cutoffHour = completedHour(now: now, timeZoneIdentifier: property.timeZoneIdentifier)

        var today = MetricTotals.zero
        var yesterday = MetricTotals.zero
        if cutoffHour >= 0 {
            for row in hourly.rows {
                let dateHour = try hourly.dimension("dateHour", in: row)
                guard dateHour.count == 10,
                      let hour = Int(dateHour.suffix(2)),
                      hour <= cutoffHour else { continue }
                switch try hourly.dimension("dateRange", in: row) {
                case "date_range_0":
                    today = today + (try hourly.metricTotals(in: row))
                case "date_range_1":
                    yesterday = yesterday + (try hourly.metricTotals(in: row))
                default:
                    throw GoogleAPIError.invalidResponse
                }
            }
        }

        var sevenDay: [AnalyticsDay: MetricTotals] = [:]
        for row in trend.rows {
            let day = try AnalyticsDay(gaValue: trend.dimension("date", in: row))
            sevenDay[day] = (sevenDay[day] ?? .zero) + (try trend.metricTotals(in: row))
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
            )
        )
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
