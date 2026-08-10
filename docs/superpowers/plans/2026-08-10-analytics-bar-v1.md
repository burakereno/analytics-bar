# Analytics Bar v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a personal-use native macOS menu bar app that signs in to Google Analytics, displays simultaneous GA4 data for multiple selected properties, updates safely, and ships as a signed/notarized GitHub Release DMG.

**Architecture:** A Swift Package Manager executable owns an AppKit `NSStatusItem` and transient `NSPopover`, while SwiftUI renders onboarding, the multi-property dashboard, and settings. OAuth, Google Analytics Admin/Data REST clients, caching, aggregation, refresh scheduling, and updates are isolated behind protocols; multi-property requests run with bounded concurrency and retain per-property failures instead of failing the whole dashboard. Release and updater constants come from one `.github/release-contract.env` contract.

**Tech Stack:** Swift 5.9+, Swift Package Manager, macOS 14+, AppKit, SwiftUI, Charts, Foundation `URLSession`, Network framework, Security/Keychain, ServiceManagement, XCTest, GitHub Actions, Developer ID Application signing, Apple notarization.

## Global Constraints

- Product name: `Analytics Bar`.
- GitHub owner/repository: `burakereno/analytics-bar`.
- Bundle identifier: `com.burakerenoglu.AnalyticsBar`.
- Executable name: `AnalyticsBar`.
- Minimum OS: macOS 14.0.
- Distribution: personal use through signed and notarized GitHub Release DMGs.
- Apple Team ID: `66K3EFBVB6`.
- DMG asset: `AnalyticsBar.dmg`.
- Update manifest: `AnalyticsBar.dmg.update.json`.
- Google authorization scope: only `https://www.googleapis.com/auth/analytics.readonly`.
- Menu bar default metric: sum of last-30-minute `activeUsers` across selected properties.
- Multi-property active-user totals must be labeled as property sums, never cross-property unique users.
- Each property uses its own GA reporting time zone for “today” and same-time comparisons.
- Revenue is summed only when all selected properties use the same currency; mixed currencies remain separated.
- Popover-open realtime refresh: 60 seconds. Background refresh default: 5 minutes.
- One property failure must not discard successful or cached data from other properties.
- No analytics data, OAuth token, certificate, or signing secret may be sent to an app-owned server.
- OAuth tokens must be stored in macOS Keychain; dashboard cache may contain aggregate/report data but no tokens.
- Do not commit `.p12`, `.cer`, `.certSigningRequest`, `.keychain-db`, `.dmg`, OAuth credentials, or generated release artifacts.
- Automatic update/network failures remain silent; explicit manual checks show actionable errors.
- Production updates require exact bundle identifier, exact Team ID, strict signature, Gatekeeper assessment, manifest metadata, and DMG SHA-256 verification.

## Approved Product Behavior

### Menu bar

- Render a compact template icon plus the selected metric, defaulting to the property-summed last-30-minute active users.
- Offer `Active users`, `Users today`, `Sessions today`, `Views today`, and `Icon only` preferences.
- Render `--` before the first successful load.
- Preserve the last value when refresh fails and mark stale state in the popover rather than flashing an error in the menu bar.

### Dashboard

- Header: Analytics Bar title, selected property count, settings button.
- Combined Live card: property-summed active users, views, event count, and key events from the GA4 realtime API.
- Property strip/list: every selected property remains visible simultaneously with live active users and today’s users, sessions, views, and refresh state.
- Combined Today card: property sums for users, sessions, views, and key events; revenue only when currencies can be represented honestly.
- Seven-day chart: client-side sum by GA calendar day across selected property results.
- Top Pages / Sources: property selector chips inside the card; rankings are not merged across domains by default.
- Footer: last update, refresh, update/version status, and quit.
- Settings slide in from the right inside the same popover, matching Codex Monitor’s dark card-based presentation.

### Accuracy disclosures

- Display `Property total; users may overlap across properties` beside combined user totals.
- Display `Each property uses its Analytics reporting time zone` in the aggregate trend help text.
- When selected properties have multiple currency codes, show per-currency totals such as `USD 120 · TRY 2,500`; never convert currencies.
- Compare today against yesterday through the same completed property-local hour, not against the full previous day.

## File Map

```text
Package.swift
.gitignore
AGENTS.md
.env.local.example
.github/release-contract.env
.github/workflows/release.yml
scripts/build-app.sh
scripts/create-dmg.sh
scripts/install-update.sh
Sources/AnalyticsBar/
  AnalyticsBarApp.swift
  AppDelegate.swift
  AppEnvironment.swift
  Configuration/AppConfiguration.swift
  Domain/AnalyticsProperty.swift
  Domain/AnalyticsMetrics.swift
  Domain/DashboardSnapshot.swift
  Domain/DashboardAggregator.swift
  Authentication/GoogleOAuthConfiguration.swift
  Authentication/GoogleOAuthModels.swift
  Authentication/PKCE.swift
  Authentication/OAuthLoopbackServer.swift
  Authentication/GoogleOAuthClient.swift
  Authentication/KeychainTokenStore.swift
  Networking/HTTPClient.swift
  Networking/GoogleAPIError.swift
  GoogleAnalytics/AnalyticsAdminClient.swift
  GoogleAnalytics/AnalyticsDataRequests.swift
  GoogleAnalytics/AnalyticsDataResponses.swift
  GoogleAnalytics/AnalyticsDataClient.swift
  Repository/DashboardCache.swift
  Repository/PropertyRefreshCoordinator.swift
  Repository/AnalyticsRepository.swift
  Preferences/AppPreferences.swift
  Refresh/RefreshScheduler.swift
  Dashboard/DashboardModel.swift
  Dashboard/DashboardView.swift
  Dashboard/DashboardHeaderView.swift
  Dashboard/LiveSummaryCard.swift
  Dashboard/PropertySummaryCard.swift
  Dashboard/TodayMetricsCard.swift
  Dashboard/SevenDayTrendCard.swift
  Dashboard/BreakdownCard.swift
  Dashboard/DashboardStatusView.swift
  Dashboard/DashboardPresentation.swift
  Dashboard/DashboardPreviewFixtures.swift
  Onboarding/OnboardingView.swift
  Onboarding/PropertySelection.swift
  Onboarding/PropertySelectionView.swift
  Settings/SettingsView.swift
  Settings/ConnectionSettingsView.swift
  Settings/PropertySettingsView.swift
  StatusBar/StatusBarController.swift
  StatusBar/MenuBarRenderer.swift
  StatusBar/PopoverLayout.swift
  System/DockIconController.swift
  System/LaunchAtLoginPreference.swift
  Updates/UpdateManifest.swift
  Updates/UpdateChecker.swift
  Updates/UpdateInstaller.swift
  Resources/Assets.xcassets/
    AccentColor.colorset/Contents.json
    Contents.json
  Resources/AppIcon.icns
artwork/app-icon-2048.png
Tests/AnalyticsBarTests/
  AppConfigurationTests.swift
  DashboardAggregatorTests.swift
  AppPreferencesTests.swift
  PKCETests.swift
  OAuthCallbackParserTests.swift
  GoogleOAuthClientTests.swift
  KeychainTokenStoreTests.swift
  AnalyticsAdminClientTests.swift
  AnalyticsDataClientTests.swift
  DashboardCacheTests.swift
  PropertyRefreshCoordinatorTests.swift
  AnalyticsRepositoryTests.swift
  RefreshSchedulerTests.swift
  DashboardModelTests.swift
  PropertySelectionTests.swift
  DashboardPresentationTests.swift
  MenuBarRendererTests.swift
  SystemPreferencesTests.swift
  UpdateCheckerTests.swift
  UpdateSecurityTests.swift
docs/privacy.md
README.md
```

---

### Task 1: Scaffold a launchable native menu bar app

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `AGENTS.md`
- Create: `.env.local.example`
- Create: `Sources/AnalyticsBar/AnalyticsBarApp.swift`
- Create: `Sources/AnalyticsBar/AppDelegate.swift`
- Create: `Sources/AnalyticsBar/Configuration/AppConfiguration.swift`
- Create: `Sources/AnalyticsBar/StatusBar/StatusBarController.swift`
- Create: `Sources/AnalyticsBar/StatusBar/PopoverLayout.swift`
- Create: `Sources/AnalyticsBar/Resources/Assets.xcassets/Contents.json`
- Create: `Tests/AnalyticsBarTests/AppConfigurationTests.swift`

**Interfaces:**
- Consumes: none.
- Produces: `AppConfiguration`, `AnalyticsBarApp`, `AppDelegate`, `StatusBarController`, and a launchable menu bar executable used by every later task.

- [ ] **Step 1: Initialize the local repository**

Run: `git init -b main`

Expected: an empty local Git repository on branch `main`. Do not add a remote or create a GitHub repository in this task.

- [ ] **Step 2: Create the package and ignore contract**

Use this package declaration:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AnalyticsBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AnalyticsBar", targets: ["AnalyticsBar"])],
    targets: [
        .executableTarget(
            name: "AnalyticsBar",
            path: "Sources/AnalyticsBar",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AnalyticsBarTests",
            dependencies: ["AnalyticsBar"],
            path: "Tests/AnalyticsBarTests"
        )
    ]
)
```

`.gitignore` must contain:

```gitignore
.build/
.swiftpm/
.DS_Store
.env.local
*.p12
*.cer
*.certSigningRequest
*.keychain-db
*.dmg
*.update.json
DerivedData/
```

`.env.local.example` must contain names with empty values:

```dotenv
GOOGLE_OAUTH_CLIENT_ID=
GOOGLE_OAUTH_CLIENT_SECRET=
```

Create `Sources/AnalyticsBar/Resources/Assets.xcassets/Contents.json` with:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 3: Write the failing configuration test**

```swift
import XCTest
@testable import AnalyticsBar

final class AppConfigurationTests: XCTestCase {
    func testProductionIdentityIsStable() {
        XCTAssertEqual(AppConfiguration.appName, "Analytics Bar")
        XCTAssertEqual(AppConfiguration.bundleIdentifier, "com.burakerenoglu.AnalyticsBar")
        XCTAssertEqual(AppConfiguration.githubOwner, "burakereno")
        XCTAssertEqual(AppConfiguration.githubRepo, "analytics-bar")
        XCTAssertEqual(AppConfiguration.teamIdentifier, "66K3EFBVB6")
        XCTAssertEqual(AppConfiguration.dmgAssetName, "AnalyticsBar.dmg")
    }
}
```

- [ ] **Step 4: Run the focused test and confirm the expected failure**

Run: `swift test --filter AppConfigurationTests`

Expected: compilation fails because `AppConfiguration` does not exist.

- [ ] **Step 5: Add exact production constants and the first popover**

`AppConfiguration` must expose:

```swift
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
}
```

The app entry point must use `@NSApplicationDelegateAdaptor`, set activation policy to `.accessory`, retain `StatusBarController`, and expose no document windows. The initial controller must create a variable-length `NSStatusItem`, render the SF Symbol `chart.xyaxis.line`, and present a 380-point-wide transient `NSPopover` containing the title `Analytics Bar` and the text `Connect Google Analytics to begin.`.

- [ ] **Step 6: Add local verification instructions**

`AGENTS.md` must require this loop before the app-bundle scripts exist:

```sh
pkill -x AnalyticsBar || true
swift test
swift build
```

For changes that affect runtime UI, it must additionally require `swift run AnalyticsBar`, visual inspection, and terminating the process after inspection. Task 15 replaces this section with the app-bundle verification loop.

- [ ] **Step 7: Verify and commit**

Run: `swift test --filter AppConfigurationTests && swift build`

Expected: the test passes and the executable builds.

Commit:

```sh
git add Package.swift .gitignore AGENTS.md .env.local.example Sources Tests
git commit -m "feat: scaffold Analytics Bar menu app"
```

---

### Task 2: Define multi-property domain models and honest aggregation

**Files:**
- Create: `Sources/AnalyticsBar/Domain/AnalyticsProperty.swift`
- Create: `Sources/AnalyticsBar/Domain/AnalyticsMetrics.swift`
- Create: `Sources/AnalyticsBar/Domain/DashboardSnapshot.swift`
- Create: `Sources/AnalyticsBar/Domain/DashboardAggregator.swift`
- Create: `Tests/AnalyticsBarTests/DashboardAggregatorTests.swift`

**Interfaces:**
- Consumes: `AppConfiguration`.
- Produces: `AnalyticsProperty`, `AnalyticsDay`, `MetricTotals`, `RealtimeTotals`, `PropertyDashboardSnapshot`, `CombinedDashboardSnapshot`, `RevenueSummary`, and `DashboardAggregator.aggregate(_:)`.

- [ ] **Step 1: Write aggregation tests for overlapping users, currencies, day merging, and partial state**

Use fixtures for two properties whose metrics are 10/20 active users, 5/7 sessions, and USD 12/USD 8 revenue. Assert that aggregate active users equal 30 and `userCountingDisclosure` equals `Property total; users may overlap across properties`. Add a second fixture with TRY revenue and assert `RevenueSummary.mixed` contains separate USD and TRY values. Add daily points for `2026-08-09` and assert the combined point sums matching GA calendar keys.

The required public assertions are:

```swift
let combined = DashboardAggregator.aggregate([first, second])
XCTAssertEqual(combined.live.activeUsers, 30)
XCTAssertEqual(combined.today.sessions, 12)
XCTAssertEqual(
    combined.userCountingDisclosure,
    "Property total; users may overlap across properties"
)
XCTAssertEqual(combined.revenue, .single(currencyCode: "USD", amount: 20))
```

- [ ] **Step 2: Run the focused test and confirm missing domain types**

Run: `swift test --filter DashboardAggregatorTests`

Expected: compilation fails for missing `DashboardAggregator` and model types.

- [ ] **Step 3: Implement immutable Sendable domain values**

Use these signatures:

```swift
struct AnalyticsProperty: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let resourceName: String
    let accountResourceName: String
    let accountDisplayName: String
    let displayName: String
    let timeZoneIdentifier: String
    let currencyCode: String
}

struct AnalyticsDay: Codable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int
    init(gaValue: String) throws
    static func < (lhs: Self, rhs: Self) -> Bool
}

struct MetricTotals: Codable, Equatable, Sendable {
    var activeUsers: Int
    var sessions: Int
    var views: Int
    var eventCount: Int
    var keyEvents: Decimal
    var revenue: Decimal
    static let zero: Self
}

struct RealtimeTotals: Codable, Equatable, Sendable {
    var activeUsers: Int
    var views: Int
    var eventCount: Int
    var keyEvents: Decimal
    static let zero: Self
}

struct RankedDimensionRow: Codable, Equatable, Sendable {
    let label: String
    let value: Decimal
}

struct CurrencyAmount: Codable, Equatable, Sendable {
    let currencyCode: String
    let amount: Decimal
}

struct PropertyDashboardSnapshot: Codable, Identifiable, Equatable, Sendable {
    enum Freshness: String, Codable, Sendable { case live, stale }
    let id: String
    let property: AnalyticsProperty
    let live: RealtimeTotals
    let today: MetricTotals
    let yesterdayThroughSameHour: MetricTotals
    let sevenDay: [AnalyticsDay: MetricTotals]
    let topPages: [RankedDimensionRow]
    let topSources: [RankedDimensionRow]
    let fetchedAt: Date
    let freshness: Freshness
    let refreshMessage: String?
}

enum RevenueSummary: Equatable, Sendable {
    case none
    case single(currencyCode: String, amount: Decimal)
    case mixed([CurrencyAmount])
}

struct CombinedDashboardSnapshot: Equatable, Sendable {
    let properties: [PropertyDashboardSnapshot]
    let live: RealtimeTotals
    let today: MetricTotals
    let yesterdayThroughSameHour: MetricTotals
    let sevenDay: [AnalyticsDay: MetricTotals]
    let revenue: RevenueSummary
    let userCountingDisclosure: String
    let fetchedAt: Date
}
```

`DashboardAggregator.aggregate(_:)` must sum additive property metrics, merge `sevenDay` by `AnalyticsDay`, preserve input order in property rows, compute deltas with zero-denominator handling, and never claim user de-duplication.

- [ ] **Step 4: Verify all aggregation cases**

Run: `swift test --filter DashboardAggregatorTests`

Expected: all overlapping-user, currency, day, ordering, and zero-denominator assertions pass.

- [ ] **Step 5: Commit**

```sh
git add Sources/AnalyticsBar/Domain Tests/AnalyticsBarTests/DashboardAggregatorTests.swift
git commit -m "feat: model multi-property analytics totals"
```

---

### Task 3: Persist preferences and OAuth tokens in the correct stores

**Files:**
- Create: `Sources/AnalyticsBar/Preferences/AppPreferences.swift`
- Create: `Sources/AnalyticsBar/Authentication/GoogleOAuthModels.swift`
- Create: `Sources/AnalyticsBar/Authentication/KeychainTokenStore.swift`
- Create: `Tests/AnalyticsBarTests/AppPreferencesTests.swift`
- Create: `Tests/AnalyticsBarTests/KeychainTokenStoreTests.swift`

**Interfaces:**
- Consumes: `AnalyticsProperty` identifiers.
- Produces: `MenuBarMetric`, `BackgroundRefreshInterval`, `AppPreferences`, `GoogleOAuthToken`, `TokenStore`, and `KeychainTokenStore`.

- [ ] **Step 1: Write preference round-trip and default tests**

Required defaults and round-trip assertions:

```swift
XCTAssertEqual(preferences.menuBarMetric, .realtimeActiveUsers)
XCTAssertEqual(preferences.backgroundRefreshInterval, .fiveMinutes)
XCTAssertEqual(preferences.selectedPropertyResourceNames, [])
XCTAssertTrue(preferences.showsRevenue)

preferences.selectedPropertyResourceNames = ["properties/101", "properties/202"]
XCTAssertEqual(reloaded.selectedPropertyResourceNames, ["properties/101", "properties/202"])
```

Create each test with a unique `UserDefaults(suiteName:)` and remove the suite in `tearDown`.

- [ ] **Step 2: Write Keychain contract tests with an isolated service name**

Test saving, loading, replacement, deletion, and missing-token behavior through:

```swift
protocol TokenStore: Sendable {
    func load() throws -> GoogleOAuthToken?
    func save(_ token: GoogleOAuthToken) throws
    func delete() throws
}
```

Use a UUID-suffixed Keychain service in tests and delete it in `tearDown`.

- [ ] **Step 3: Run tests and confirm missing implementations**

Run: `swift test --filter 'AppPreferencesTests|KeychainTokenStoreTests'`

Expected: compilation fails for missing preferences and token store types.

- [ ] **Step 4: Implement UserDefaults preferences and generic-password Keychain storage**

Use these enums:

```swift
enum MenuBarMetric: String, Codable, CaseIterable, Sendable {
    case realtimeActiveUsers
    case usersToday
    case sessionsToday
    case viewsToday
    case iconOnly
}

enum BackgroundRefreshInterval: Int, Codable, CaseIterable, Sendable {
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
}
```

Encode the selected property list as JSON in UserDefaults so ordering is stable. Encode `GoogleOAuthToken` as JSON and store it as one `kSecClassGenericPassword` item under service `com.burakerenoglu.AnalyticsBar.google-oauth` and account `primary`. Map non-success Security status codes to an error that contains only the numeric OSStatus, never token bytes.

- [ ] **Step 5: Verify and commit**

Run: `swift test --filter 'AppPreferencesTests|KeychainTokenStoreTests'`

Expected: all persistence tests pass and repeated test runs leave no credential item.

```sh
git add Sources/AnalyticsBar/Preferences Sources/AnalyticsBar/Authentication/GoogleOAuthModels.swift Sources/AnalyticsBar/Authentication/KeychainTokenStore.swift Tests/AnalyticsBarTests
git commit -m "feat: store Analytics Bar preferences securely"
```

---

### Task 4: Implement Google desktop OAuth with PKCE and loopback callback

**Files:**
- Create: `Sources/AnalyticsBar/Authentication/GoogleOAuthConfiguration.swift`
- Create: `Sources/AnalyticsBar/Authentication/PKCE.swift`
- Create: `Sources/AnalyticsBar/Authentication/OAuthLoopbackServer.swift`
- Create: `Sources/AnalyticsBar/Authentication/GoogleOAuthClient.swift`
- Create: `Sources/AnalyticsBar/Networking/HTTPClient.swift`
- Create: `Sources/AnalyticsBar/Networking/GoogleAPIError.swift`
- Create: `Tests/AnalyticsBarTests/PKCETests.swift`
- Create: `Tests/AnalyticsBarTests/OAuthCallbackParserTests.swift`
- Create: `Tests/AnalyticsBarTests/GoogleOAuthClientTests.swift`

**Interfaces:**
- Consumes: `AppConfiguration.analyticsReadonlyScope`, `TokenStore`.
- Produces: `HTTPClient`, `URLSessionHTTPClient`, `GoogleOAuthConfiguration`, `PKCEPair`, `OAuthLoopbackServer`, and `GoogleOAuthClient.signIn()/validAccessToken()/signOut()`.

- [ ] **Step 1: Write PKCE and authorization URL tests**

Use the RFC 7636 verifier/challenge vector and assert SHA-256 base64url output. Assert the authorization URL contains exactly one scope, `response_type=code`, `access_type=offline`, `prompt=consent`, a random `state`, `code_challenge_method=S256`, and a `http://127.0.0.1:<random-port>/oauth/callback` redirect.

- [ ] **Step 2: Write callback parser tests**

Cover these exact outcomes:

```swift
XCTAssertEqual(
    try OAuthCallbackParser.parse(target: "/oauth/callback?code=abc&state=expected", expectedState: "expected"),
    "abc"
)
XCTAssertThrowsError(
    try OAuthCallbackParser.parse(target: "/oauth/callback?code=abc&state=wrong", expectedState: "expected")
)
XCTAssertThrowsError(
    try OAuthCallbackParser.parse(target: "/oauth/callback?error=access_denied&state=expected", expectedState: "expected")
)
```

- [ ] **Step 3: Write token exchange and refresh tests against a stub HTTP client**

Assert that code exchange sends `code`, `client_id`, `client_secret`, `code_verifier`, `redirect_uri`, and `grant_type=authorization_code` to `https://oauth2.googleapis.com/token`. Assert refresh sends `refresh_token` and preserves the stored refresh token when Google omits it from the refresh response. Assert HTTP 400 `invalid_grant` becomes `GoogleOAuthError.authorizationExpired`.

- [ ] **Step 4: Run focused tests and confirm missing OAuth types**

Run: `swift test --filter 'PKCETests|OAuthCallbackParserTests|GoogleOAuthClientTests'`

Expected: compilation fails for the OAuth client and parser types.

- [ ] **Step 5: Implement the OAuth boundary**

Use these public contracts:

```swift
protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct GoogleOAuthConfiguration: Sendable {
    let clientID: String
    let clientSecret: String
    let scope: String
    static func load(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self
}

actor GoogleOAuthClient {
    func signIn() async throws -> GoogleOAuthToken
    func validAccessToken(now: Date = Date()) async throws -> String
    func signOut() throws
}
```

`GoogleOAuthConfiguration.load` must read bundled Info.plist keys `GoogleOAuthClientID` and `GoogleOAuthClientSecret`, then fall back to `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET` environment values for `swift run`. Missing values must surface as a clear setup error without printing either value.

`OAuthLoopbackServer` must bind only to `127.0.0.1` on a random port, accept one HTTP GET, enforce path `/oauth/callback`, validate `state`, return a small success/cancel HTML response, stop the listener after one terminal result, and time out after 180 seconds.

- [ ] **Step 6: Verify and commit**

Run: `swift test --filter 'PKCETests|OAuthCallbackParserTests|GoogleOAuthClientTests'`

Expected: all PKCE, state, exchange, refresh, cancellation, and expiry cases pass.

```sh
git add Sources/AnalyticsBar/Authentication Sources/AnalyticsBar/Networking Tests/AnalyticsBarTests
git commit -m "feat: connect Google Analytics with secure OAuth"
```

---

### Task 5: Discover accounts and properties through the Admin API

**Files:**
- Create: `Sources/AnalyticsBar/GoogleAnalytics/AnalyticsAdminClient.swift`
- Create: `Tests/AnalyticsBarTests/AnalyticsAdminClientTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, OAuth access token.
- Produces: `AnalyticsAdminClient.listProperties(accessToken:) async throws -> [AnalyticsProperty]`.

- [ ] **Step 1: Write pagination and metadata enrichment tests**

Stub two `GET https://analyticsadmin.googleapis.com/v1alpha/accountSummaries` pages. The first includes `nextPageToken=next`; the second has no token. Stub `GET https://analyticsadmin.googleapis.com/v1beta/properties/101` and `/202` responses with `timeZone` and `currencyCode`. Assert account name, property name, numeric ID, time zone, currency, pagination, stable account/property sorting, and `Authorization: Bearer <token>`.

- [ ] **Step 2: Write error tests**

Assert 401 maps to `.authorizationExpired`, 403 to `.permissionDenied`, 429 to `.rateLimited(retryAfter:)`, malformed property resource names to `.invalidResponse`, and an empty result to an empty array rather than an exception.

- [ ] **Step 3: Run the tests and confirm the client is missing**

Run: `swift test --filter AnalyticsAdminClientTests`

Expected: compilation fails because `AnalyticsAdminClient` does not exist.

- [ ] **Step 4: Implement paginated account summary loading and bounded property metadata fetches**

Use `pageSize=200`, percent-encode `pageToken`, accept only `properties/<digits>` resource names, and fetch property metadata with at most four concurrent requests. Preserve account display names from account summaries and property reporting metadata from `properties.get`.

- [ ] **Step 5: Verify and commit**

Run: `swift test --filter AnalyticsAdminClientTests`

Expected: all pagination, sorting, metadata, empty-account, and error mapping tests pass.

```sh
git add Sources/AnalyticsBar/GoogleAnalytics/AnalyticsAdminClient.swift Tests/AnalyticsBarTests/AnalyticsAdminClientTests.swift
git commit -m "feat: discover Google Analytics properties"
```

---

### Task 6: Fetch realtime and core GA4 reports for one property

**Files:**
- Create: `Sources/AnalyticsBar/GoogleAnalytics/AnalyticsDataRequests.swift`
- Create: `Sources/AnalyticsBar/GoogleAnalytics/AnalyticsDataResponses.swift`
- Create: `Sources/AnalyticsBar/GoogleAnalytics/AnalyticsDataClient.swift`
- Create: `Tests/AnalyticsBarTests/AnalyticsDataClientTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `AnalyticsProperty`, OAuth access token, domain metric types.
- Produces: `AnalyticsDataClient.fetchRealtime(...)` and `AnalyticsDataClient.fetchCore(...)`.

- [ ] **Step 1: Write realtime request/response tests**

Assert a POST to `https://analyticsdata.googleapis.com/v1beta/properties/101:runRealtimeReport` with metrics in this exact order:

```json
{
  "metrics": [
    {"name":"activeUsers"},
    {"name":"screenPageViews"},
    {"name":"eventCount"},
    {"name":"keyEvents"}
  ],
  "minuteRanges": [{"name":"last30Minutes","startMinutesAgo":29,"endMinutesAgo":0}],
  "returnPropertyQuota": true
}
```

Assert header-based decoding succeeds even when response metric headers are reordered. No rows must produce `.zero`.

- [ ] **Step 2: Write the core batch request tests**

Assert one POST to `https://analyticsdata.googleapis.com/v1beta/properties/101:batchRunReports` containing four reports:

1. `dateHour`, two date ranges `today` and `yesterday`, and metrics `activeUsers`, `sessions`, `screenPageViews`, `eventCount`, `keyEvents`, `totalRevenue`.
2. `date`, date range `7daysAgo` through `today`, and the same metrics.
3. `unifiedPagePathScreen`, date range `today`, metric `screenPageViews`, descending metric order, limit 5.
4. `sessionPrimaryChannelGroup`, date range `today`, metric `sessions`, descending metric order, limit 5.

Assert only yesterday rows through the current completed hour in the property’s `timeZoneIdentifier` contribute to `yesterdayThroughSameHour`.

- [ ] **Step 3: Write numeric and HTTP failure tests**

Cover integer strings, decimal strings, empty values, unknown extra headers, 401, 403, 429 with `Retry-After`, 500, invalid JSON, and structurally valid responses with no rows. Retry 429 and 5xx at most twice with injected zero-delay retry policy in tests; do not retry 400, 401, or 403.

- [ ] **Step 4: Run tests and confirm missing data client types**

Run: `swift test --filter AnalyticsDataClientTests`

Expected: compilation fails for missing request, response, and client types.

- [ ] **Step 5: Implement header-driven decoding and exact request builders**

Use this protocol:

```swift
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
```

`PropertyCoreReport` must be a `Sendable`, `Equatable` value containing `today`, `yesterdayThroughSameHour`, `sevenDay`, `topPages`, and `topSources` using the domain types from Task 2.

Create a `ReportTable` that maps dimension and metric header names to indices before parsing rows. Parse numbers with an `en_US_POSIX` locale. Reject nonnumeric property IDs before URL construction. Return quota data only for diagnostic logging; never display or transmit it.

- [ ] **Step 6: Verify and commit**

Run: `swift test --filter AnalyticsDataClientTests`

Expected: realtime, four-report batch, time-zone cutoff, reordered headers, retries, empty data, and HTTP error tests pass.

```sh
git add Sources/AnalyticsBar/GoogleAnalytics Tests/AnalyticsBarTests/AnalyticsDataClientTests.swift
git commit -m "feat: load GA4 realtime and trend reports"
```

---

### Task 7: Coordinate simultaneous multi-property refresh with partial-failure recovery

**Files:**
- Create: `Sources/AnalyticsBar/Repository/DashboardCache.swift`
- Create: `Sources/AnalyticsBar/Repository/PropertyRefreshCoordinator.swift`
- Create: `Sources/AnalyticsBar/Repository/AnalyticsRepository.swift`
- Create: `Tests/AnalyticsBarTests/DashboardCacheTests.swift`
- Create: `Tests/AnalyticsBarTests/PropertyRefreshCoordinatorTests.swift`
- Create: `Tests/AnalyticsBarTests/AnalyticsRepositoryTests.swift`

**Interfaces:**
- Consumes: OAuth client, Admin client, Data client, AppPreferences, dashboard models.
- Produces: `AnalyticsRepository.connect()`, `availableProperties()`, `refreshSelectedProperties(trigger:)`, `cachedSnapshot()`, and `disconnect()`.

- [ ] **Step 1: Write cache tests**

Use an isolated temporary directory. Assert save/load round trip, atomic replacement, corrupt JSON removal, cache schema version rejection, and that encoded cache text contains no `access_token`, `refresh_token`, `client_secret`, or OAuth token values.

- [ ] **Step 2: Write concurrency tests**

Create an instrumented fake data client that records active calls. Refresh six properties and assert `maximumObservedConcurrency == 3`, output order matches preference order, and each property received one realtime and one core fetch.

- [ ] **Step 3: Write partial-failure and stale fallback tests**

For three properties, return success for A/C and a 429 for B while a cached B snapshot exists. Assert A/C are `.live`, B is `.stale` with `refreshMessage`, aggregate totals include cached B, and repository returns one combined snapshot rather than throwing. When every property fails and no cache exists, assert a terminal `.noData` error.

- [ ] **Step 4: Write authorization refresh tests**

Make all first requests return 401, then succeed after token refresh. Assert the OAuth client refreshes once for the refresh cycle and the property requests retry once with the new token. A second 401 must disconnect the session and require sign-in.

- [ ] **Step 5: Run tests and confirm repository types are missing**

Run: `swift test --filter 'DashboardCacheTests|PropertyRefreshCoordinatorTests|AnalyticsRepositoryTests'`

Expected: compilation fails for missing cache/coordinator/repository types.

- [ ] **Step 6: Implement the actor-isolated repository**

Use these contracts:

```swift
enum RefreshTrigger: Sendable { case popoverOpened, popoverTimer, backgroundTimer, manual }

actor AnalyticsRepository {
    func connect() async throws -> [AnalyticsProperty]
    func availableProperties() async throws -> [AnalyticsProperty]
    func refreshSelectedProperties(
        _ properties: [AnalyticsProperty],
        trigger: RefreshTrigger,
        now: Date = Date()
    ) async throws -> CombinedDashboardSnapshot
    func cachedSnapshot() async -> CombinedDashboardSnapshot?
    func disconnect() async throws
}
```

`PropertyRefreshCoordinator` must use a task group fed by a three-permit async semaphore. Each child returns a typed success/failure value, never throws out of the group. Cache successful property snapshots immediately after a completed refresh cycle using a unique temporary file followed by rename.

- [ ] **Step 7: Verify and commit**

Run: `swift test --filter 'DashboardCacheTests|PropertyRefreshCoordinatorTests|AnalyticsRepositoryTests'`

Expected: cache, concurrency ceiling, ordering, partial failure, stale data, and single token refresh tests pass.

```sh
git add Sources/AnalyticsBar/Repository Tests/AnalyticsBarTests
git commit -m "feat: refresh multiple Analytics properties safely"
```

---

### Task 8: Add refresh scheduling and dashboard state management

**Files:**
- Create: `Sources/AnalyticsBar/Refresh/RefreshScheduler.swift`
- Create: `Sources/AnalyticsBar/Dashboard/DashboardModel.swift`
- Create: `Sources/AnalyticsBar/AppEnvironment.swift`
- Create: `Tests/AnalyticsBarTests/RefreshSchedulerTests.swift`
- Create: `Tests/AnalyticsBarTests/DashboardModelTests.swift`
- Modify: `Sources/AnalyticsBar/AppDelegate.swift`
- Modify: `Sources/AnalyticsBar/StatusBar/StatusBarController.swift`

**Interfaces:**
- Consumes: repository, preferences, selected properties.
- Produces: `DashboardModel.State`, published snapshot/status/menu title, popover open/close hooks, and deterministic scheduler behavior.

- [ ] **Step 1: Write scheduler cadence tests with a manual clock**

Assert:

- opening the popover triggers an immediate refresh;
- while open, ticks occur every 60 seconds;
- after closing, ticks use the selected 300/900/1800-second background interval;
- changing the interval reschedules without duplicate tasks;
- stopping cancels all future ticks.

- [ ] **Step 2: Write model state tests**

Cover `.disconnected`, `.selectingProperties`, `.loading`, `.loaded`, `.noProperties`, and `.failed(message:)`. Assert cached data is published before a network refresh, manual refresh exposes errors, automatic refresh preserves the loaded state, and selecting zero properties returns to `.selectingProperties`.

- [ ] **Step 3: Run tests and confirm missing scheduler/model**

Run: `swift test --filter 'RefreshSchedulerTests|DashboardModelTests'`

Expected: compilation fails for missing scheduler and dashboard model types.

- [ ] **Step 4: Implement the main-actor model and environment composition**

Use:

```swift
@MainActor
final class DashboardModel: ObservableObject {
    enum State: Equatable {
        case disconnected
        case selectingProperties([AnalyticsProperty])
        case loading
        case loaded
        case noProperties
        case failed(message: String)
    }

    @Published private(set) var state: State
    @Published private(set) var snapshot: CombinedDashboardSnapshot?
    @Published private(set) var isRefreshing: Bool
    @Published private(set) var lastManualError: String?

    func connect() async
    func confirmSelection(_ resourceNames: [String]) async
    func refresh(trigger: RefreshTrigger) async
    func popoverDidOpen()
    func popoverDidClose()
    func disconnect() async
}
```

`AppEnvironment.live()` must construct one URLSession HTTP client, Keychain token store, OAuth client, Admin client, Data client, cache, repository, preferences, scheduler, and model. `AppDelegate` must retain the environment for the process lifetime.

- [ ] **Step 5: Verify and commit**

Run: `swift test --filter 'RefreshSchedulerTests|DashboardModelTests' && swift build`

Expected: state/cadence tests pass and dependency composition builds.

```sh
git add Sources/AnalyticsBar/Refresh Sources/AnalyticsBar/Dashboard/DashboardModel.swift Sources/AnalyticsBar/AppEnvironment.swift Sources/AnalyticsBar/AppDelegate.swift Sources/AnalyticsBar/StatusBar Tests/AnalyticsBarTests
git commit -m "feat: manage Analytics dashboard refresh state"
```

---

### Task 9: Build onboarding and multi-property selection

**Files:**
- Create: `Sources/AnalyticsBar/Onboarding/OnboardingView.swift`
- Create: `Sources/AnalyticsBar/Onboarding/PropertySelection.swift`
- Create: `Sources/AnalyticsBar/Onboarding/PropertySelectionView.swift`
- Create: `Sources/AnalyticsBar/Dashboard/DashboardView.swift`
- Modify: `Sources/AnalyticsBar/StatusBar/StatusBarController.swift`
- Create: `Tests/AnalyticsBarTests/PropertySelectionTests.swift`

**Interfaces:**
- Consumes: `DashboardModel.State`, property metadata, connect/selection actions.
- Produces: complete disconnected, sign-in, empty account, and multi-select flows.

- [ ] **Step 1: Write property selection reducer tests**

Extract a pure `PropertySelection` value and assert toggle, select-all-account, clear-all, search filtering, and preservation of selection order. Confirm unavailable/removed property IDs are dropped when account summaries refresh.

- [ ] **Step 2: Run the focused test and confirm missing selection type**

Run: `swift test --filter PropertySelectionTests`

Expected: compilation fails for missing `PropertySelection`.

- [ ] **Step 3: Implement onboarding views**

`OnboardingView` must show an original Analytics Bar icon, a concise local-processing privacy statement, and `Connect Google Analytics`. Disable the button while browser authorization is active. Display cancellation separately from configuration and permission errors.

`PropertySelectionView` must group properties by Analytics account, support search, account-level select all, individual checkboxes, show time zone/currency metadata, require at least one selected property, and use `Show N Properties` as the confirmation label.

Do not use the Google Analytics product logo as the app icon. The OAuth browser page supplies Google branding.

- [ ] **Step 4: Route the root view by model state**

`DashboardView` must switch exhaustively over all `DashboardModel.State` cases and render a progress state without destroying a cached snapshot. `StatusBarController` must host this view and call `popoverDidOpen/popoverDidClose` from popover lifecycle callbacks.

- [ ] **Step 5: Verify and commit**

Run: `swift test --filter PropertySelectionTests && swift build`

Expected: selection tests pass and the app compiles with every state represented.

```sh
git add Sources/AnalyticsBar/Onboarding Sources/AnalyticsBar/Dashboard/DashboardView.swift Sources/AnalyticsBar/StatusBar Tests/AnalyticsBarTests/PropertySelectionTests.swift
git commit -m "feat: add Analytics account onboarding"
```

---

### Task 10: Render the simultaneous multi-property dashboard

**Files:**
- Create: `Sources/AnalyticsBar/Dashboard/DashboardHeaderView.swift`
- Create: `Sources/AnalyticsBar/Dashboard/LiveSummaryCard.swift`
- Create: `Sources/AnalyticsBar/Dashboard/PropertySummaryCard.swift`
- Create: `Sources/AnalyticsBar/Dashboard/TodayMetricsCard.swift`
- Create: `Sources/AnalyticsBar/Dashboard/SevenDayTrendCard.swift`
- Create: `Sources/AnalyticsBar/Dashboard/BreakdownCard.swift`
- Create: `Sources/AnalyticsBar/Dashboard/DashboardStatusView.swift`
- Create: `Sources/AnalyticsBar/Dashboard/DashboardPresentation.swift`
- Create: `Sources/AnalyticsBar/Dashboard/DashboardPreviewFixtures.swift`
- Modify: `Sources/AnalyticsBar/StatusBar/PopoverLayout.swift`
- Modify: `Sources/AnalyticsBar/Dashboard/DashboardView.swift`
- Create: `Tests/AnalyticsBarTests/DashboardPresentationTests.swift`

**Interfaces:**
- Consumes: `CombinedDashboardSnapshot`, model refresh/settings actions.
- Produces: Codex Monitor-inspired dashboard with all selected properties visible simultaneously.

- [ ] **Step 1: Write presentation formatting tests**

Assert compact numbers (`999`, `1.2K`, `1.5M`), signed deltas, no divide-by-zero percentages, mixed-currency strings, stale labels, and sorted seven-day points. Assert the combined users subtitle exactly matches the overlap disclosure.

- [ ] **Step 2: Run the focused tests and confirm missing presenters**

Run: `swift test --filter DashboardPresentationTests`

Expected: compilation fails for missing dashboard presentation helpers.

- [ ] **Step 3: Implement the fixed visual system**

Use a 380-point popover width, dark appearance, 12-point horizontal content padding, 12-point vertical card spacing, 14-point card corner radius, one-pixel low-opacity borders, SF Pro system typography, orange accent, green live/success, red error, and secondary gray metadata. Honor Reduce Motion and Increased Contrast. Use native Swift Charts and SF Symbols only.

- [ ] **Step 4: Implement the card hierarchy**

Render in this order:

1. Header with `Analytics Bar`, `N Properties`, and settings gear.
2. Combined Live card with active users, views, event count, key events, and overlap disclosure.
3. A `LazyVStack` of `PropertySummaryCard` values for every selected property; never collapse the list behind a property switcher.
4. Combined Today metrics with same-hour yesterday deltas and honest revenue presentation.
5. Seven-day combined chart with a local `Users / Sessions / Views` segmented metric picker.
6. Breakdown card with property chips and `Top Pages / Sources` picker.
7. Dashboard status card with last refresh, stale property names, and per-property error details behind disclosure.
8. Footer with manual refresh, version/update area, and quit.

The settings transition must use a 0.24-second snappy move/opacity animation and the popover height must clamp to the current screen visible frame.

- [ ] **Step 5: Add deterministic debug fixtures**

`DashboardPreviewFixtures` must produce one-, three-, and eight-property `CombinedDashboardSnapshot` values. In debug builds only, `AppEnvironment` must read `ANALYTICS_BAR_FIXTURE=one|three|eight` and use an in-memory repository/model without OAuth or network access. Release builds must ignore this environment key.

- [ ] **Step 6: Verify and visually inspect**

Run the tests, then inspect each deterministic dataset:

```sh
swift test --filter DashboardPresentationTests
swift build
ANALYTICS_BAR_FIXTURE=one swift run AnalyticsBar
ANALYTICS_BAR_FIXTURE=three swift run AnalyticsBar
ANALYTICS_BAR_FIXTURE=eight swift run AnalyticsBar
```

Expected: tests pass; 1, 3, and 8-property dashboards scroll without clipped header/footer and every selected property is visible. Terminate `AnalyticsBar` between fixture launches.

- [ ] **Step 7: Commit**

```sh
git add Sources/AnalyticsBar/Dashboard Sources/AnalyticsBar/StatusBar/PopoverLayout.swift Tests/AnalyticsBarTests/DashboardPresentationTests.swift
git commit -m "feat: show simultaneous multi-property dashboard"
```

---

### Task 11: Render the configurable menu bar metric

**Files:**
- Create: `Sources/AnalyticsBar/StatusBar/MenuBarRenderer.swift`
- Create: `Tests/AnalyticsBarTests/MenuBarRendererTests.swift`
- Modify: `Sources/AnalyticsBar/StatusBar/StatusBarController.swift`
- Modify: `Sources/AnalyticsBar/Dashboard/DashboardModel.swift`

**Interfaces:**
- Consumes: combined dashboard snapshot and `MenuBarMetric` preference.
- Produces: `MenuBarTitle`, deterministic width calculation, and an AppKit template image.

- [ ] **Step 1: Write title derivation and width tests**

Assert default active-user sum, each today metric, icon-only mode, `--` before data, compact formatting, and stable width for values `9`, `99`, `1.2K`, and `1.5M`. Assert stale data retains its value.

- [ ] **Step 2: Run tests and confirm renderer is missing**

Run: `swift test --filter MenuBarRendererTests`

Expected: compilation fails for missing `MenuBarRenderer`.

- [ ] **Step 3: Implement AppKit rendering**

Use:

```swift
struct MenuBarTitle: Equatable, Sendable {
    let metric: MenuBarMetric
    let value: String?
    let accessibilityLabel: String
}

enum MenuBarRenderer {
    static func title(snapshot: CombinedDashboardSnapshot?, metric: MenuBarMetric) -> MenuBarTitle
    static func contentWidth(for title: MenuBarTitle) -> CGFloat
    @MainActor static func image(for title: MenuBarTitle) -> NSImage
}
```

Draw a template chart symbol and optional text into one `NSImage`; do not use separate `button.title` because spacing changes across macOS releases. Update on the main actor only when the derived title changes.

- [ ] **Step 4: Verify and commit**

Run: `swift test --filter MenuBarRendererTests && swift build`

Expected: title/width tests pass and the status item updates without recreating the item.

```sh
git add Sources/AnalyticsBar/StatusBar Sources/AnalyticsBar/Dashboard/DashboardModel.swift Tests/AnalyticsBarTests/MenuBarRendererTests.swift
git commit -m "feat: show live Analytics value in menu bar"
```

---

### Task 12: Add settings, login item, Dock behavior, and connection management

**Files:**
- Create: `Sources/AnalyticsBar/Settings/SettingsView.swift`
- Create: `Sources/AnalyticsBar/Settings/ConnectionSettingsView.swift`
- Create: `Sources/AnalyticsBar/Settings/PropertySettingsView.swift`
- Create: `Sources/AnalyticsBar/System/DockIconController.swift`
- Create: `Sources/AnalyticsBar/System/LaunchAtLoginPreference.swift`
- Create: `Tests/AnalyticsBarTests/SystemPreferencesTests.swift`
- Modify: `Sources/AnalyticsBar/Dashboard/DashboardView.swift`
- Modify: `Sources/AnalyticsBar/AppEnvironment.swift`

**Interfaces:**
- Consumes: preferences, property list, model connection actions.
- Produces: same-popover settings navigation and system preference controllers.

- [ ] **Step 1: Write system preference state tests**

Inject wrappers for `SMAppService.mainApp` and `NSApplication.setActivationPolicy`. Assert enabled/disabled state mapping, errors returned to UI, Dock value control disabled while Dock icon is off, and preference changes trigger menu title/scheduler updates exactly once.

- [ ] **Step 2: Run tests and confirm missing controllers**

Run: `swift test --filter SystemPreferencesTests`

Expected: compilation fails for missing system preference adapters.

- [ ] **Step 3: Implement settings sections**

Render these sections:

- `CONNECTION`: Google connection state, reconnect, disconnect with confirmation.
- `PROPERTIES`: account-grouped multi-selection and selected count; save only with at least one property.
- `MENU BAR`: metric picker with active-users default.
- `REFRESH`: background 5/15/30-minute picker and fixed `60 sec while open` explanation.
- `STARTUP`: open at login.
- `DOCK`: show Dock icon.
- `DASHBOARD`: revenue visibility.
- `ABOUT`: app name/version and privacy link; update controls are connected in Task 13.

Switch dashboard/settings inside the same popover with trailing/leading transitions. Disconnect must delete Keychain token, cached snapshots, selected property IDs, and return to `.disconnected`.

- [ ] **Step 4: Verify and commit**

Run: `swift test --filter SystemPreferencesTests && swift build`

Expected: preference adapter tests pass and all settings update the running app without relaunch.

```sh
git add Sources/AnalyticsBar/Settings Sources/AnalyticsBar/System Sources/AnalyticsBar/Dashboard/DashboardView.swift Sources/AnalyticsBar/AppEnvironment.swift Tests/AnalyticsBarTests/SystemPreferencesTests.swift
git commit -m "feat: add Analytics Bar settings"
```

---

### Task 13: Add secure GitHub Release update discovery

**Files:**
- Create: `.github/release-contract.env`
- Create: `Sources/AnalyticsBar/Updates/UpdateManifest.swift`
- Create: `Sources/AnalyticsBar/Updates/UpdateChecker.swift`
- Create: `Tests/AnalyticsBarTests/UpdateCheckerTests.swift`
- Modify: `Sources/AnalyticsBar/Settings/SettingsView.swift`
- Modify: `Sources/AnalyticsBar/Dashboard/DashboardView.swift`

**Interfaces:**
- Consumes: release contract constants and `HTTPClient`.
- Produces: `UpdateReleaseInfo`, `UpdateManifest`, `UpdateChecker.State`, automatic/manual checking, and validated DMG/manifest URLs.

- [ ] **Step 1: Create the release contract**

```dotenv
GITHUB_OWNER=burakereno
GITHUB_REPO=analytics-bar
APP_NAME=Analytics Bar
APP_BUNDLE_NAME=Analytics Bar.app
EXECUTABLE_NAME=AnalyticsBar
BUNDLE_IDENTIFIER=com.burakerenoglu.AnalyticsBar
TEAM_IDENTIFIER=66K3EFBVB6
DMG_ASSET_NAME=AnalyticsBar.dmg
MANIFEST_ASSET_NAME=AnalyticsBar.dmg.update.json
```

- [ ] **Step 2: Write update checker tests**

Cover:

- `HEAD /releases/latest` redirect to `/releases/tag/v1.2.3`;
- numeric comparison where `1.10.0 > 1.9.9`;
- DMG `HEAD` validation and companion manifest 2xx `GET` decoding;
- missing tag, DMG, or manifest;
- manifest version/asset/bundle/team mismatch;
- automatic network failure leaves stable state and `lastError == nil`;
- manual failure sets a useful error;
- available update always has both validated URLs.

- [ ] **Step 3: Run tests and confirm missing updater types**

Run: `swift test --filter UpdateCheckerTests`

Expected: compilation fails for missing updater and manifest types.

- [ ] **Step 4: Implement redirect-based discovery without GitHub API calls**

Use:

```swift
struct UpdateReleaseInfo: Equatable, Sendable {
    let tag: String
    let version: String
    let dmgURL: URL
    let manifestURL: URL
    let manifest: UpdateManifest
}

@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable { case idle, checking, upToDate, available(UpdateReleaseInfo), failed(String) }
    func checkAutomatically() async
    func checkManually() async
}
```

Discover only through `https://github.com/burakereno/analytics-bar/releases/latest`, follow the web redirect, build tag-specific asset URLs, validate the DMG with `HEAD`, fetch the manifest with a validated 2xx `GET`, decode it, and compare exact contract values. Set a descriptive `User-Agent` and 15-second request timeout. Never call `api.github.com` and never embed a GitHub token.

- [ ] **Step 5: Connect UI behavior and verify**

Run: `swift test --filter UpdateCheckerTests && swift build`

Expected: all redirect, semantic version, asset, manifest, and manual/automatic behavior tests pass. About/footer shows version normally, `Up to date` only after success, and update action only for a fully validated release.

- [ ] **Step 6: Commit**

```sh
git add .github/release-contract.env Sources/AnalyticsBar/Updates Sources/AnalyticsBar/Settings/SettingsView.swift Sources/AnalyticsBar/Dashboard/DashboardView.swift Tests/AnalyticsBarTests/UpdateCheckerTests.swift
git commit -m "feat: discover signed Analytics Bar updates"
```

---

### Task 14: Add verified DMG installation with rollback

**Files:**
- Create: `Sources/AnalyticsBar/Updates/UpdateInstaller.swift`
- Create: `scripts/install-update.sh`
- Create: `Tests/AnalyticsBarTests/UpdateSecurityTests.swift`
- Modify: `Sources/AnalyticsBar/Updates/UpdateChecker.swift`

**Interfaces:**
- Consumes: validated release info, manifest, current app URL.
- Produces: unique secure download directory, SHA-256 validation, verified helper execution, replacement, relaunch confirmation, and rollback.

- [ ] **Step 1: Write Swift trust-boundary tests**

Assert installation rejects:

- non-GitHub or wrong owner/repository URLs;
- HTTP failures for manifest or DMG callbacks;
- wrong SHA-256;
- wrong asset/version/bundle/team manifest values;
- unavailable current app path;
- missing helper resource.

Assert the helper receives paths and trust constants as process arguments, never interpolated shell source.

- [ ] **Step 2: Run tests and confirm installer is missing**

Run: `swift test --filter UpdateSecurityTests`

Expected: compilation fails for missing `UpdateInstaller`.

- [ ] **Step 3: Implement secure download and checksum validation**

`UpdateInstaller.install(_:)` must:

1. create a UUID-named mode-0700 directory beneath `FileManager.default.temporaryDirectory`;
2. download manifest and DMG with validated 2xx HTTP responses;
3. revalidate manifest metadata;
4. stream CryptoKit SHA-256 over the DMG and compare lowercase hex;
5. invoke bundled `install-update.sh` with DMG, target app, expected bundle ID, expected version, Team ID, executable name, and hash as separate arguments;
6. surface bounded progress states;
7. retain logs without token, OAuth configuration, or local secret values.

- [ ] **Step 4: Implement the replacement helper**

`scripts/install-update.sh` must use `set -euo pipefail`, quote every positional argument, create unique mount/staging/backup paths, and register one cleanup trap. In this exact order it must:

1. repeat SHA-256 comparison;
2. validate DMG strict signature and exact `TeamIdentifier=66K3EFBVB6`;
3. run `spctl --assess --type open --context context:primary-signature` on the DMG;
4. attach using an explicit unique mount point and `-nobrowse`;
5. locate exactly `Analytics Bar.app`;
6. verify bundle identifier, version, executable, strict/deep signature, exact Team ID, designated requirement, and Gatekeeper execute assessment;
7. copy with `ditto` to staging;
8. move the existing target to backup;
9. move staging into the target path;
10. launch the target with `open`;
11. poll for executable `AnalyticsBar` for at most 15 seconds;
12. on failure restore backup and reopen it;
13. delete backup only after launch confirmation;
14. detach and remove temporary paths through the cleanup trap.

Do not remove quarantine before assessment and do not use a fixed `/Volumes` path.

- [ ] **Step 5: Verify scripts and tests**

Run: `bash -n scripts/install-update.sh && swift test --filter UpdateSecurityTests`

Expected: shell syntax is valid and every URL/manifest/checksum/process-boundary test passes.

- [ ] **Step 6: Run the updater audit**

Run:

```sh
/Users/burakerenoglu/.codex/skills/macos-app-updater/scripts/audit-macos-updater.sh .
```

Expected: no critical findings.

- [ ] **Step 7: Commit**

```sh
git add Sources/AnalyticsBar/Updates scripts/install-update.sh Tests/AnalyticsBarTests/UpdateSecurityTests.swift
git commit -m "feat: install verified Analytics Bar updates"
```

---

### Task 15: Build, sign, notarize, and publish the app reproducibly

**Files:**
- Create: `scripts/build-app.sh`
- Create: `scripts/create-dmg.sh`
- Create: `.github/workflows/release.yml`
- Create: `Sources/AnalyticsBar/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create after icon approval: `artwork/app-icon-2048.png`
- Create after icon approval: `Sources/AnalyticsBar/Resources/AppIcon.icns`
- Modify: `.gitignore`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: release contract, Swift package, OAuth build credentials, Developer ID secrets.
- Produces: versioned `.app`, signed/notarized drag-to-Applications DMG, update manifest, Git tag, and GitHub Release.

- [ ] **Step 1: Stop for the original app-icon creative brief**

Use the `create-macos-app-icon` skill and ask the user to choose the visual route and primary metaphor before any image generation. Present the required approval brief, generate only after an explicit affirmative response, finalize a full-bleed centered `2048x2048` PNG to `artwork/app-icon-2048.png`, inspect its 128/64/32-pixel previews, then ask explicit permission to derive the shipping `.icns`. After permission, create a standard macOS iconset from the approved master with `sips`, compile it with `iconutil`, and save only the final `Sources/AnalyticsBar/Resources/AppIcon.icns` plus the 2048 master. Do not copy Google, Google Analytics, Apple, or Codex Monitor artwork.

- [ ] **Step 2: Implement the local app bundle builder**

`scripts/build-app.sh` must require or default:

- `APP_VERSION=0.1.0` for local builds;
- `APP_BUILD_NUMBER=1` for local builds;
- `BUNDLE_IDENTIFIER=com.burakerenoglu.AnalyticsBar`;
- OAuth client ID/secret from environment or `.env.local`, never command-line output.

It must run `swift build -c release`, create `.build/Analytics Bar.app/Contents/{MacOS,Resources}`, copy the executable, resource bundle, and `AppIcon.icns`, write an Info.plist with `CFBundleShortVersionString`, `CFBundleVersion`, `CFBundleIdentifier`, `CFBundleExecutable`, `CFBundleIconFile=AppIcon`, `LSUIElement=true`, `NSHighResolutionCapable=true`, and the two OAuth keys, then sign with hardened runtime when `CODESIGN_IDENTITY` is present or ad-hoc sign local debug output.

- [ ] **Step 3: Implement drag-to-Applications DMG creation**

`scripts/create-dmg.sh` must create a temporary staging folder containing `Analytics Bar.app` and an `Applications` symlink, generate `AnalyticsBar.dmg`, sign it with the supplied Developer ID identity, and remove staging through a cleanup trap.

- [ ] **Step 4: Implement the manual GitHub Actions release workflow**

The workflow must:

1. validate the standard six Apple signing/notarization secrets plus `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET` by name without printing values;
2. import `MACOS_CERTIFICATE_P12_BASE64` into a temporary keychain;
3. require exact Developer ID Team `66K3EFBVB6`;
4. choose `v0.1.0` when no release tag exists, otherwise increment patch;
5. build the app with tag version and Actions run number;
6. validate executable, version, bundle ID, hardened runtime, strict signature, and Team ID;
7. notarize/staple/assess the app;
8. create, sign, notarize, staple, and assess the DMG;
9. generate `AnalyticsBar.dmg.update.json` with exact version, asset, lowercase SHA-256, bundle ID, and Team ID;
10. create the tag only after all trust checks pass;
11. publish DMG and manifest in the same GitHub Release;
12. delete the temporary keychain in an always-run cleanup step.

- [ ] **Step 5: Treat the mentioned Desktop certificate files safely**

Do not copy or inspect `/Users/burakerenoglu/Desktop/CertificateSigningRequest.certSigningRequest` or `/Users/burakerenoglu/Desktop/Certificates.p12` during ordinary builds. The CSR is not needed for app signing. At release-secret setup, first check Keychain for `Developer ID Application: Burak ERENOGLU (66K3EFBVB6)`; if absent, stop and ask for explicit permission before importing the P12 through a hidden password prompt. Never place either file in the repository or Actions artifacts.

- [ ] **Step 6: Verify local packaging**

Run:

```sh
bash -n scripts/build-app.sh
bash -n scripts/create-dmg.sh
./scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 ".build/Analytics Bar.app"
open ".build/Analytics Bar.app"
```

Expected: scripts have valid syntax, the local app bundle verifies, launches as a menu bar accessory, and exposes no Dock icon by default.

- [ ] **Step 7: Run release readiness without dispatching a release**

Run:

```sh
/Users/burakerenoglu/.codex/skills/macos-developer-id-release/scripts/check_release_readiness.sh .
```

Expected before GitHub setup: any missing remote or secret names are reported as explicit blockers; no release is dispatched.

- [ ] **Step 8: Commit**

```sh
git add scripts/build-app.sh scripts/create-dmg.sh .github/workflows/release.yml Sources/AnalyticsBar/Resources artwork/app-icon-2048.png .gitignore AGENTS.md
git commit -m "build: add signed macOS release pipeline"
```

---

### Task 16: Document privacy, configure personal OAuth, and run final QA

**Files:**
- Create: `docs/privacy.md`
- Create: `README.md`
- Modify: `AGENTS.md`
- Test: all files under `Tests/AnalyticsBarTests/`

**Interfaces:**
- Consumes: completed app, Google Cloud Desktop OAuth credentials, local GA4 account.
- Produces: reproducible setup documentation and a verified v1 release candidate.

- [ ] **Step 1: Write privacy and setup documentation**

`docs/privacy.md` must state that Analytics Bar requests read-only Analytics access, stores the OAuth token in Keychain, caches report snapshots locally, has no app-owned backend or telemetry, and lets the user erase credentials/cache by disconnecting.

`README.md` must document:

- macOS 14+ requirement;
- simultaneous multi-property behavior and overlap disclosure;
- enabling Google Analytics Data API and Admin API;
- creating a Desktop OAuth client;
- setting the OAuth audience to `External` and publishing status to `In production` for personal ongoing use;
- local `.env.local` keys without values;
- `swift test`, local build, launch, and release readiness commands;
- signed/notarized GitHub Release installation.

- [ ] **Step 2: Stop for personal Google Cloud configuration authorization**

Present the exact Cloud Console checklist and ask the user either to complete it or explicitly authorize browser control. After that authorization, enable Google Analytics Data API and Google Analytics Admin API, create a Desktop OAuth client, request only `analytics.readonly`, set audience to `External`, and publish the consent screen `In production` so personal refresh tokens are not subject to Testing mode’s seven-day lifetime. The personal account may see the unverified-app warning once. Put local values only in ignored `.env.local`; put Actions values only in `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET` repository secrets.

- [ ] **Step 3: Run the automated suite**

Run:

```sh
swift test
./scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 ".build/Analytics Bar.app"
```

Expected: all tests pass, app builds, and signature verification succeeds.

- [ ] **Step 4: Run the local app verification loop**

Run:

```sh
pkill -x AnalyticsBar || true
./scripts/build-app.sh
open ".build/Analytics Bar.app"
```

Verify these scenarios against the personal GA account:

- first launch and browser OAuth;
- account/property discovery;
- select 1, 3, and all accessible properties;
- every selected property appears simultaneously;
- combined menu bar active-user total equals property-row sum;
- same-currency revenue sums and mixed currency does not;
- property-local today comparison;
- one property permission/API failure leaves other properties usable;
- offline launch shows cached stale data;
- manual refresh error is visible and background error is quiet;
- reconnect and disconnect remove the correct local state;
- login item and Dock preferences;
- VoiceOver labels, keyboard navigation, Reduce Motion, and Increased Contrast;
- popover on a short-height display remains scrollable with fixed header/footer.

- [ ] **Step 5: Run updater and release audits**

Run:

```sh
/Users/burakerenoglu/.codex/skills/macos-app-updater/scripts/audit-macos-updater.sh .
/Users/burakerenoglu/.codex/skills/macos-developer-id-release/scripts/check_release_readiness.sh .
```

Expected: updater has no critical findings; release readiness is green before any release dispatch.

- [ ] **Step 6: Commit the documentation and QA contract**

```sh
git add README.md docs/privacy.md AGENTS.md
git commit -m "docs: document Analytics Bar setup and privacy"
```

- [ ] **Step 7: Stop for release authorization**

Do not configure secrets, import the Desktop P12, create a GitHub repository, push commits, dispatch Actions, or publish a release without a separate explicit user request. When authorized, use the macOS Developer ID release skill, report secret names only, and verify both the GitHub Release DMG and companion update manifest.

---

## Definition of Done

- All selected GA4 properties are visible simultaneously in the popover.
- Default menu bar value is the property-summed last-30-minute active-user count.
- Combined user totals disclose possible cross-property overlap.
- Mixed-currency revenue is never numerically combined.
- OAuth uses browser authorization, PKCE, loopback state validation, read-only scope, and Keychain persistence.
- Account/property discovery is automatic and paginated.
- Each property refresh performs one realtime request plus one core batch request, with global concurrency limited to three properties.
- Per-property failures preserve successful/cached data and surface precise stale status.
- Popover open/background refresh cadence is 60 seconds/5 minutes by default.
- Codex Monitor-inspired dark native UI works for 1, 3, and many selected properties.
- Updater avoids GitHub REST API rate limits and validates redirect, assets, manifest, checksum, bundle, Team ID, signatures, Gatekeeper, rollback, and relaunch.
- Release pipeline produces a hardened, signed, notarized, stapled, assessed DMG plus update manifest.
- Desktop certificate files remain outside the repository and unused until separately authorized.
- `swift test`, local app build, signature verification, launch loop, updater audit, and release readiness all pass.
