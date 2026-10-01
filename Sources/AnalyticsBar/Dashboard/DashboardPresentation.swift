import Foundation

enum DashboardPresentation {
    struct ReportSummary: Equatable {
        let currentCount: Int
        let totalCount: Int
        let oldestSuccess: Date?

        var isCurrent: Bool { totalCount > 0 && currentCount == totalCount }
        var status: String {
            if isCurrent { return "Up to date" }
            if currentCount > 0 { return "\(currentCount)/\(totalCount) up to date" }
            return "Unavailable"
        }
    }

    static func reportSummary(_ statuses: [ReportStatus], now: Date, maximumAge: TimeInterval) -> ReportSummary {
        let successes = statuses.compactMap(\.lastSuccess)
        return ReportSummary(
            currentCount: statuses.filter { $0.isCurrent(at: now, maximumAge: maximumAge) }.count,
            totalCount: statuses.count,
            oldestSuccess: successes.count == statuses.count ? successes.min() : nil
        )
    }

    static func age(_ date: Date, relativeTo now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3_600)h ago" }
        return "\(seconds / 86_400)d ago"
    }

    static func timestamp(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
    }

    static func weeklyChange(current: Int, previous: Int) -> String {
        if previous == 0 { return current == 0 ? "No change" : "New traffic" }
        return delta(current: current, previous: previous)
    }

    static func compactNumber(_ value: Int) -> String {
        compactDecimal(Decimal(value))
    }

    static func compactDecimal(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        let absolute = abs(number)
        let divisor: Double
        let suffix: String
        switch absolute {
        case 1_000_000...:
            divisor = 1_000_000
            suffix = "M"
        case 1_000...:
            divisor = 1_000
            suffix = "K"
        default:
            return integerString(Int(number.rounded()))
        }
        let compact = number / divisor
        let value = compact.rounded() == compact
            ? String(format: "%.0f", compact)
            : String(format: "%.1f", compact)
        return value + suffix
    }

    static func delta(current: Int, previous: Int) -> String {
        guard previous != 0 else { return "—" }
        let percent = Int((Double(current - previous) / Double(previous) * 100).rounded())
        if percent > 0 { return "+\(percent)%" }
        if percent < 0 { return "−\(abs(percent))%" }
        return "0%"
    }

    static func revenue(_ summary: RevenueSummary) -> String? {
        switch summary {
        case .none:
            return nil
        case let .single(currencyCode, amount):
            return currency(currencyCode, amount: amount)
        case let .mixed(values):
            return values.map { currency($0.currencyCode, amount: $0.amount) }.joined(separator: " · ")
        }
    }

    static func currency(_ code: String, amount: Decimal) -> String {
        "\(code)\u{00A0}\(decimalString(amount))"
    }

    private static func decimalString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0"
    }

    private static func integerString(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}
