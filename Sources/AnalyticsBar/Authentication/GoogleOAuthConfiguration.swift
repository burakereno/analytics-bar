import Foundation

struct GoogleOAuthConfiguration: Equatable, Sendable {
    let clientID: String
    let clientSecret: String
    let scope: String

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
        let clientID = nonempty(bundle.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String)
            ?? nonempty(environment["GOOGLE_OAUTH_CLIENT_ID"])
        let clientSecret = nonempty(bundle.object(forInfoDictionaryKey: "GoogleOAuthClientSecret") as? String)
            ?? nonempty(environment["GOOGLE_OAUTH_CLIENT_SECRET"])

        guard let clientID, let clientSecret else {
            throw GoogleOAuthError.configurationMissing
        }

        return GoogleOAuthConfiguration(
            clientID: clientID,
            clientSecret: clientSecret,
            scope: AppConfiguration.analyticsReadonlyScope
        )
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
