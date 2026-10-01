import Foundation

/// A successful API response is distinct from both cached data and an unsuccessful attempt.
struct ReportStatus: Codable, Equatable, Sendable {
    let lastSuccess: Date?
    let lastAttempt: Date?
    let message: String?
    let verified: Bool
    var requiresReconnection: Bool? = nil

    static func success(at date: Date) -> Self {
        Self(lastSuccess: date, lastAttempt: date, message: nil, verified: true)
    }

    func invalidated(message: String, attemptedAt: Date? = nil, requiresReconnection: Bool = false) -> Self {
        Self(lastSuccess: lastSuccess, lastAttempt: attemptedAt ?? lastAttempt, message: message, verified: false, requiresReconnection: requiresReconnection)
    }

    func isCurrent(at date: Date, maximumAge: TimeInterval) -> Bool {
        guard verified, message == nil, let lastSuccess else { return false }
        let age = date.timeIntervalSince(lastSuccess)
        return age >= -60 && age <= maximumAge
    }
}
