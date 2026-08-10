import Foundation

enum GoogleAPIError: Error, Equatable, LocalizedError, Sendable {
    case invalidResponse
    case authorizationExpired
    case permissionDenied
    case rateLimited(retryAfter: TimeInterval?)
    case server(statusCode: Int)
    case http(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Google returned an unreadable response."
        case .authorizationExpired:
            return "Google authorization expired. Please reconnect."
        case .permissionDenied:
            return "This Google account cannot read the selected Analytics property."
        case let .rateLimited(retryAfter):
            if let retryAfter {
                return "Google Analytics is rate limited. Try again in \(Int(retryAfter)) seconds."
            }
            return "Google Analytics is temporarily rate limited."
        case let .server(statusCode):
            return "Google Analytics is temporarily unavailable (\(statusCode))."
        case let .http(statusCode):
            return "Google request failed (\(statusCode))."
        }
    }
}

enum GoogleHTTPStatusMapper {
    static func error(for response: HTTPURLResponse) -> GoogleAPIError? {
        guard !(200..<300).contains(response.statusCode) else { return nil }
        switch response.statusCode {
        case 401:
            return .authorizationExpired
        case 403:
            return .permissionDenied
        case 429:
            return .rateLimited(retryAfter: retryAfter(from: response))
        case 500...599:
            return .server(statusCode: response.statusCode)
        default:
            return .http(statusCode: response.statusCode)
        }
    }

    private static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(value)
    }
}
