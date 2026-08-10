import Foundation

enum RefreshTrigger: Sendable {
    case popoverOpened
    case popoverTimer
    case backgroundTimer
    case manual
}

enum AnalyticsRepositoryError: Error, Equatable, LocalizedError, Sendable {
    case noData
    case authorizationExpired

    var errorDescription: String? {
        switch self {
        case .noData:
            return "No Analytics data is available yet."
        case .authorizationExpired:
            return "Google authorization expired. Please reconnect."
        }
    }
}

protocol AnalyticsRepositoryProtocol: Sendable {
    func hasStoredAuthorization() async -> Bool
    func connect() async throws -> [AnalyticsProperty]
    func availableProperties() async throws -> [AnalyticsProperty]
    func refreshSelectedProperties(
        _ properties: [AnalyticsProperty],
        trigger: RefreshTrigger,
        now: Date
    ) async throws -> CombinedDashboardSnapshot
    func cachedSnapshot(resourceNames: [String]?) async -> CombinedDashboardSnapshot?
    func disconnect() async throws
}

actor AnalyticsRepository: AnalyticsRepositoryProtocol {
    private let oauthSession: any OAuthSessionProviding
    private let adminClient: any AnalyticsAdminClientProtocol
    private let refreshCoordinator: PropertyRefreshCoordinator
    private let cache: DashboardCache

    init(
        oauthSession: any OAuthSessionProviding,
        adminClient: any AnalyticsAdminClientProtocol,
        refreshCoordinator: PropertyRefreshCoordinator,
        cache: DashboardCache
    ) {
        self.oauthSession = oauthSession
        self.adminClient = adminClient
        self.refreshCoordinator = refreshCoordinator
        self.cache = cache
    }

    func hasStoredAuthorization() async -> Bool {
        await oauthSession.hasStoredAuthorization()
    }

    func connect() async throws -> [AnalyticsProperty] {
        let token = try await oauthSession.signIn()
        return try await adminClient.listProperties(accessToken: token.accessToken)
    }

    func availableProperties() async throws -> [AnalyticsProperty] {
        let token = try await oauthSession.validAccessToken()
        return try await adminClient.listProperties(accessToken: token)
    }

    func refreshSelectedProperties(
        _ properties: [AnalyticsProperty],
        trigger: RefreshTrigger,
        now: Date = Date()
    ) async throws -> CombinedDashboardSnapshot {
        guard !properties.isEmpty else { throw AnalyticsRepositoryError.noData }
        var token = try await oauthSession.validAccessToken()
        var outcomes = await refreshCoordinator.refresh(
            properties: properties,
            accessToken: token,
            now: now
        )

        if outcomes.contains(where: \.isAuthorizationExpired) {
            token = try await oauthSession.forceRefreshAccessToken()
            outcomes = await refreshCoordinator.refresh(
                properties: properties,
                accessToken: token,
                now: now
            )
            if outcomes.contains(where: \.isAuthorizationExpired) {
                throw AnalyticsRepositoryError.authorizationExpired
            }
        }

        let cached = try await cache.load()
        var snapshots: [PropertyDashboardSnapshot] = []
        for outcome in outcomes {
            switch outcome {
            case let .success(snapshot):
                snapshots.append(snapshot)
            case let .failure(property, failure):
                if let cachedSnapshot = cached[property.resourceName] {
                    snapshots.append(cachedSnapshot.markedStale(message: failure.message))
                }
            }
        }

        guard !snapshots.isEmpty else { throw AnalyticsRepositoryError.noData }
        try await cache.save(snapshots)
        return DashboardAggregator.aggregate(snapshots)
    }

    func cachedSnapshot(resourceNames: [String]? = nil) async -> CombinedDashboardSnapshot? {
        guard let values = try? await cache.load(), !values.isEmpty else { return nil }
        let names = resourceNames ?? Array(values.keys).sorted()
        let snapshots = names.compactMap { values[$0] }
        guard !snapshots.isEmpty else { return nil }
        return DashboardAggregator.aggregate(snapshots)
    }

    func disconnect() async throws {
        try await oauthSession.signOut()
        try await cache.clear()
    }
}
