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
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .noData:
            return "No Analytics data is available yet."
        case .authorizationExpired:
            return "Google authorization expired. Please reconnect."
        case let .requestFailed(message):
            return message
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
            do {
                token = try await oauthSession.forceRefreshAccessToken()
                let retried = await refreshCoordinator.refresh(properties: properties, accessToken: token, now: now)
                outcomes = zip(retried, outcomes).map { $0.preservingSuccesses(from: $1) }
            } catch {
                // Keep any successful reports. Expired reports remain visible and request reconnection.
            }
        }

        let cached = try await cache.load()
        let snapshots = outcomes.map { outcome in
            makeSnapshot(outcome, cached: cached[outcome.property.resourceName], now: now)
        }
        var updatedCache = cached
        for snapshot in snapshots { updatedCache[snapshot.property.resourceName] = snapshot }
        try await cache.save(updatedCache.values.sorted { $0.property.resourceName < $1.property.resourceName })
        return DashboardAggregator.aggregate(snapshots)
    }

    private func makeSnapshot(_ outcome: PropertyRefreshOutcome, cached: PropertyDashboardSnapshot?, now: Date) -> PropertyDashboardSnapshot {
        var live = cached?.live ?? .zero
        var report = PropertyCoreReport(
            today: cached?.today ?? .zero,
            yesterdayThroughSameHour: cached?.yesterdayThroughSameHour ?? .zero,
            sevenDay: cached?.sevenDay ?? [:], topPages: cached?.topPages ?? [], topSources: cached?.topSources ?? [],
            todayThroughSameHour: cached?.todayThroughSameHour,
            weeklySessions: cached?.weeklySessions, previousWeekSessions: cached?.previousWeekSessions
        )
        let unknown = ReportStatus(lastSuccess: nil, lastAttempt: nil, message: nil, verified: false)
        let liveStatus: ReportStatus
        let coreStatus: ReportStatus
        switch outcome.realtime {
        case let .success(value):
            live = value
            liveStatus = .success(at: now)
        case let .failure(error):
            liveStatus = (cached?.realtimeHealth ?? unknown).invalidated(
                message: error.message, attemptedAt: now, requiresReconnection: error == .authorizationExpired
            )
        }
        switch outcome.core {
        case let .success(value):
            report = value
            coreStatus = .success(at: now)
        case let .failure(error):
            coreStatus = (cached?.coreHealth ?? unknown).invalidated(
                message: error.message, attemptedAt: now, requiresReconnection: error == .authorizationExpired
            )
        }
        return PropertyDashboardSnapshot(
            property: outcome.property, live: live, today: report.today,
            yesterdayThroughSameHour: report.yesterdayThroughSameHour, sevenDay: report.sevenDay,
            topPages: report.topPages, topSources: report.topSources,
            fetchedAt: [liveStatus.lastSuccess, coreStatus.lastSuccess].compactMap { $0 }.min() ?? .distantPast,
            freshness: outcome.failures.isEmpty ? .live : .stale,
            refreshMessage: outcome.failures.map(\.message).joined(separator: " · ").nilIfEmpty,
            realtimeStatus: liveStatus, coreStatus: coreStatus,
            todayThroughSameHour: report.todayThroughSameHour,
            weeklySessions: report.weeklySessions, previousWeekSessions: report.previousWeekSessions
        )
    }

    func cachedSnapshot(resourceNames: [String]? = nil) async -> CombinedDashboardSnapshot? {
        guard let values = try? await cache.load(), !values.isEmpty else { return nil }
        let names = resourceNames ?? Array(values.keys).sorted()
        let snapshots = names.compactMap { values[$0]?.markedStale(message: "Saved data; waiting for a successful refresh.") }
        guard !snapshots.isEmpty else { return nil }
        return DashboardAggregator.aggregate(snapshots)
    }

    func disconnect() async throws {
        var failures: [String] = []
        do { try await oauthSession.signOut() }
        catch { failures.append("Google authorization: \(error.localizedDescription)") }
        do { try await cache.clear() }
        catch { failures.append("Saved reports: \(error.localizedDescription)") }
        if !failures.isEmpty { throw AnalyticsRepositoryError.requestFailed(failures.joined(separator: " · ")) }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
