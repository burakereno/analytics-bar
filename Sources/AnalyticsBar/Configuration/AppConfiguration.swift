import Foundation

enum AppConfiguration {
    static let appName = "Analytics Bar"
    static let executableName = "AnalyticsBar"
    static let bundleIdentifier = "com.burakerenoglu.AnalyticsBar"
    static let githubOwner = "burakereno"
    static let githubRepo = "analytics-bar"
    static let teamIdentifier = "66K3EFBVB6"
    static let dmgAssetName = "AnalyticsBar.dmg"
    static let manifestAssetName = "AnalyticsBar.dmg.update.json"
    static let analyticsReadonlyScope = "https://www.googleapis.com/auth/analytics.readonly"

    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
