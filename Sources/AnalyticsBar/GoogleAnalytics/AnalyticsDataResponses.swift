import Foundation

struct AnalyticsReportResponse: Decodable, Sendable {
    struct DimensionHeader: Decodable, Sendable { let name: String }
    struct MetricHeader: Decodable, Sendable { let name: String }
    struct Value: Decodable, Sendable { let value: String }
    struct Row: Decodable, Sendable {
        let dimensionValues: [Value]?
        let metricValues: [Value]?
    }

    let dimensionHeaders: [DimensionHeader]?
    let metricHeaders: [MetricHeader]?
    let rows: [Row]?
    let kind: String?
    let rowCount: Int?
}

struct AnalyticsBatchReportResponse: Decodable, Sendable {
    let reports: [AnalyticsReportResponse]
}

struct AnalyticsReportTable: Sendable {
    let response: AnalyticsReportResponse
    private let dimensionIndices: [String: Int]
    private let metricIndices: [String: Int]

    init(response: AnalyticsReportResponse) throws {
        self.response = response
        dimensionIndices = try Self.indices(for: (response.dimensionHeaders ?? []).map(\.name))
        metricIndices = try Self.indices(for: (response.metricHeaders ?? []).map(\.name))
    }

    var rows: [AnalyticsReportResponse.Row] { response.rows ?? [] }

    func requireHeaders(metrics: [String], dimensions: [String] = []) throws {
        guard metrics.allSatisfy({ metricIndices[$0] != nil }),
              dimensions.allSatisfy({ dimensionIndices[$0] != nil }) else {
            throw GoogleAPIError.invalidResponse
        }
    }

    func dimension(_ name: String, in row: AnalyticsReportResponse.Row) throws -> String {
        guard let index = dimensionIndices[name],
              let values = row.dimensionValues,
              values.indices.contains(index) else {
            throw GoogleAPIError.invalidResponse
        }
        return values[index].value
    }

    func decimal(_ name: String, in row: AnalyticsReportResponse.Row) throws -> Decimal {
        guard let index = metricIndices[name],
              let values = row.metricValues,
              values.indices.contains(index),
              let value = Decimal(
                string: values[index].value,
                locale: Locale(identifier: "en_US_POSIX")
              ) else {
            throw GoogleAPIError.invalidResponse
        }
        return value
    }

    func integer(_ name: String, in row: AnalyticsReportResponse.Row) throws -> Int {
        NSDecimalNumber(decimal: try decimal(name, in: row)).intValue
    }

    func metricTotals(in row: AnalyticsReportResponse.Row) throws -> MetricTotals {
        MetricTotals(
            activeUsers: try integer("activeUsers", in: row),
            sessions: try integer("sessions", in: row),
            views: try integer("screenPageViews", in: row),
            eventCount: try integer("eventCount", in: row),
            keyEvents: try decimal("keyEvents", in: row),
            revenue: try decimal("totalRevenue", in: row)
        )
    }

    private static func indices(for names: [String]) throws -> [String: Int] {
        let pairs = names.enumerated().map { ($0.element, $0.offset) }
        let result = Dictionary(pairs, uniquingKeysWith: { _, _ in -1 })
        guard !result.values.contains(-1) else { throw GoogleAPIError.invalidResponse }
        return result
    }
}
