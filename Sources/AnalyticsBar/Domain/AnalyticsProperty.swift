import Foundation

struct AnalyticsProperty: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let resourceName: String
    let accountResourceName: String
    let accountDisplayName: String
    let displayName: String
    let timeZoneIdentifier: String
    let currencyCode: String
}

enum AnalyticsDayError: Error, Equatable {
    case invalidValue(String)
}

struct AnalyticsDay: Codable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(gaValue: String) throws {
        guard gaValue.count == 8,
              let year = Int(gaValue.prefix(4)),
              let month = Int(gaValue.dropFirst(4).prefix(2)),
              let day = Int(gaValue.suffix(2)),
              (1...12).contains(month),
              (1...31).contains(day) else {
            throw AnalyticsDayError.invalidValue(gaValue)
        }
        self.init(year: year, month: month, day: day)
    }

    var gaValue: String {
        String(format: "%04d%02d%02d", year, month, day)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
