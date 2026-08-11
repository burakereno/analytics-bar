import Foundation

@MainActor
struct AppEnvironment {
    let model: DashboardModel
    let preferences: AppPreferences
    let systemSettings: SystemSettingsController
    let updateChecker: UpdateChecker
    let updateInstaller: UpdateInstaller
    let checksForUpdatesAutomatically: Bool

    static func live(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppEnvironment {
#if DEBUG
        let fixtureSnapshots = environment["ANALYTICS_BAR_FIXTURE"]
            .flatMap(DashboardPreviewFixtures.snapshots(named:))
        let preferences: AppPreferences
        if let fixtureSnapshots {
            let suiteName = "com.burakerenoglu.AnalyticsBar.VisualPreview"
            let previewDefaults = UserDefaults(suiteName: suiteName)!
            previewDefaults.removePersistentDomain(forName: suiteName)
            preferences = AppPreferences(defaults: previewDefaults)
            preferences.selectedPropertyResourceNames = fixtureSnapshots.map(\.property.resourceName)
            preferences.showsDockIcon = environment["ANALYTICS_BAR_SETTINGS_PREVIEW"] == "1"
        } else {
            preferences = AppPreferences()
        }
#else
        let preferences = AppPreferences()
#endif
        let scheduler = RefreshScheduler()
        let systemSettings = SystemSettingsController(preferences: preferences)
        let updateInstaller = UpdateInstaller()

#if DEBUG
        if let fixtureSnapshots {
            let repository = FixtureAnalyticsRepository(snapshots: fixtureSnapshots)
            let updateChecker = UpdateChecker()
            return AppEnvironment(
                model: DashboardModel(
                    repository: repository,
                    preferences: preferences,
                    scheduler: scheduler
                ),
                preferences: preferences,
                systemSettings: systemSettings,
                updateChecker: updateChecker,
                updateInstaller: updateInstaller,
                checksForUpdatesAutomatically: false
            )
        }
#endif

        do {
            let configuration = try GoogleOAuthConfiguration.load(
                bundle: bundle,
                environment: environment
            )
            let httpClient = URLSessionHTTPClient()
            let updateChecker = UpdateChecker(httpClient: httpClient)
            let oauthClient = GoogleOAuthClient(
                configuration: configuration,
                tokenStore: KeychainTokenStore(),
                httpClient: httpClient
            )
            let dataClient = AnalyticsDataClient(httpClient: httpClient)
            let repository = AnalyticsRepository(
                oauthSession: oauthClient,
                adminClient: AnalyticsAdminClient(httpClient: httpClient),
                refreshCoordinator: PropertyRefreshCoordinator(dataClient: dataClient),
                cache: DashboardCache()
            )
            return AppEnvironment(
                model: DashboardModel(
                    repository: repository,
                    preferences: preferences,
                    scheduler: scheduler
                ),
                preferences: preferences,
                systemSettings: systemSettings,
                updateChecker: updateChecker,
                updateInstaller: updateInstaller,
                checksForUpdatesAutomatically: true
            )
        } catch {
            let updateChecker = UpdateChecker()
            return AppEnvironment(
                model: DashboardModel(
                    repository: UnavailableAnalyticsRepository(error: error),
                    preferences: preferences,
                    scheduler: scheduler
                ),
                preferences: preferences,
                systemSettings: systemSettings,
                updateChecker: updateChecker,
                updateInstaller: updateInstaller,
                checksForUpdatesAutomatically: true
            )
        }
    }
}

private actor UnavailableAnalyticsRepository: AnalyticsRepositoryProtocol {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func hasStoredAuthorization() async -> Bool { false }
    func connect() async throws -> [AnalyticsProperty] { throw error }
    func availableProperties() async throws -> [AnalyticsProperty] { throw error }
    func refreshSelectedProperties(
        _ properties: [AnalyticsProperty],
        trigger: RefreshTrigger,
        now: Date
    ) async throws -> CombinedDashboardSnapshot { throw error }
    func cachedSnapshot(resourceNames: [String]?) async -> CombinedDashboardSnapshot? { nil }
    func disconnect() async throws {}
}

#if DEBUG
private actor FixtureAnalyticsRepository: AnalyticsRepositoryProtocol {
    let snapshots: [PropertyDashboardSnapshot]

    init(snapshots: [PropertyDashboardSnapshot]) {
        self.snapshots = snapshots
    }

    func hasStoredAuthorization() async -> Bool { true }
    func connect() async throws -> [AnalyticsProperty] { snapshots.map(\.property) }
    func availableProperties() async throws -> [AnalyticsProperty] { snapshots.map(\.property) }
    func refreshSelectedProperties(
        _ properties: [AnalyticsProperty],
        trigger: RefreshTrigger,
        now: Date
    ) async throws -> CombinedDashboardSnapshot {
        DashboardAggregator.aggregate(
            properties.compactMap { property in snapshots.first { $0.property.id == property.id } }
        )
    }
    func cachedSnapshot(resourceNames: [String]?) async -> CombinedDashboardSnapshot? {
        DashboardAggregator.aggregate(snapshots)
    }
    func disconnect() async throws {}
}
#endif
