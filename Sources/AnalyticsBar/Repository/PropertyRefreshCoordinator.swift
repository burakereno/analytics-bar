import Foundation

enum PropertyRefreshFailure: Equatable, Sendable {
    case authorizationExpired
    case requestFailed(String)

    var message: String {
        switch self {
        case .authorizationExpired:
            return "Google authorization expired."
        case let .requestFailed(message):
            return message
        }
    }
}

enum PropertyRefreshOutcome: Sendable {
    case success(PropertyDashboardSnapshot)
    case failure(AnalyticsProperty, PropertyRefreshFailure)

    var property: AnalyticsProperty {
        switch self {
        case let .success(snapshot):
            return snapshot.property
        case let .failure(property, _):
            return property
        }
    }

    var isAuthorizationExpired: Bool {
        if case .failure(_, .authorizationExpired) = self { return true }
        return false
    }
}

struct PropertyRefreshCoordinator: Sendable {
    private struct IndexedOutcome: Sendable {
        let index: Int
        let outcome: PropertyRefreshOutcome
    }

    private let dataClient: any AnalyticsDataClientProtocol
    private let maximumConcurrency: Int

    init(
        dataClient: any AnalyticsDataClientProtocol,
        maximumConcurrency: Int = 3
    ) {
        self.dataClient = dataClient
        self.maximumConcurrency = max(1, maximumConcurrency)
    }

    func refresh(
        properties: [AnalyticsProperty],
        accessToken: String,
        now: Date
    ) async -> [PropertyRefreshOutcome] {
        var indexedOutcomes: [IndexedOutcome] = []

        for start in stride(from: 0, to: properties.count, by: maximumConcurrency) {
            let end = min(start + maximumConcurrency, properties.count)
            let batch = Array(properties[start..<end].enumerated()).map {
                (index: start + $0.offset, property: $0.element)
            }
            let values = await withTaskGroup(
                of: IndexedOutcome.self,
                returning: [IndexedOutcome].self
            ) { group in
                for item in batch {
                    group.addTask {
                        let outcome = await refresh(
                            property: item.property,
                            accessToken: accessToken,
                            now: now
                        )
                        return IndexedOutcome(index: item.index, outcome: outcome)
                    }
                }
                var results: [IndexedOutcome] = []
                for await value in group { results.append(value) }
                return results
            }
            indexedOutcomes.append(contentsOf: values)
        }

        return indexedOutcomes
            .sorted { $0.index < $1.index }
            .map(\.outcome)
    }

    private func refresh(
        property: AnalyticsProperty,
        accessToken: String,
        now: Date
    ) async -> PropertyRefreshOutcome {
        do {
            async let realtime = dataClient.fetchRealtime(property: property, accessToken: accessToken)
            async let core = dataClient.fetchCore(property: property, now: now, accessToken: accessToken)
            let (live, report) = try await (realtime, core)
            return .success(
                PropertyDashboardSnapshot(
                    property: property,
                    live: live,
                    today: report.today,
                    yesterdayThroughSameHour: report.yesterdayThroughSameHour,
                    sevenDay: report.sevenDay,
                    topPages: report.topPages,
                    topSources: report.topSources,
                    fetchedAt: now,
                    freshness: .live,
                    refreshMessage: nil
                )
            )
        } catch GoogleAPIError.authorizationExpired {
            return .failure(property, .authorizationExpired)
        } catch GoogleOAuthError.authorizationExpired {
            return .failure(property, .authorizationExpired)
        } catch {
            return .failure(property, .requestFailed(error.localizedDescription))
        }
    }
}
