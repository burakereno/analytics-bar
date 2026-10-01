import Foundation

enum PropertyRefreshFailure: Error, Equatable, Sendable {
    case authorizationExpired
    case requestFailed(String)

    init(error: Error) {
        if error as? GoogleAPIError == .authorizationExpired || error as? GoogleOAuthError == .authorizationExpired {
            self = .authorizationExpired
        } else {
            self = .requestFailed(error.localizedDescription)
        }
    }

    var message: String {
        switch self {
        case .authorizationExpired:
            return "Google authorization expired."
        case let .requestFailed(message):
            return message
        }
    }
}

struct PropertyRefreshOutcome: Sendable {
    let property: AnalyticsProperty
    let realtime: Result<RealtimeTotals, PropertyRefreshFailure>
    let core: Result<PropertyCoreReport, PropertyRefreshFailure>

    var isAuthorizationExpired: Bool {
        failures.contains { $0 == .authorizationExpired }
    }

    var failures: [PropertyRefreshFailure] {
        var result: [PropertyRefreshFailure] = []
        if case let .failure(error) = realtime { result.append(error) }
        if case let .failure(error) = core { result.append(error) }
        return result
    }

    func preservingSuccesses(from previous: Self) -> Self {
        let live: Result<RealtimeTotals, PropertyRefreshFailure>
        let report: Result<PropertyCoreReport, PropertyRefreshFailure>
        if case .success = previous.realtime { live = previous.realtime } else { live = realtime }
        if case .success = previous.core { report = previous.core } else { report = core }
        return Self(property: property, realtime: live, core: report)
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
        async let realtime = fetchRealtime(property: property, accessToken: accessToken)
        async let core = fetchCore(property: property, accessToken: accessToken, now: now)
        return await PropertyRefreshOutcome(property: property, realtime: realtime, core: core)
    }

    private func fetchRealtime(property: AnalyticsProperty, accessToken: String) async -> Result<RealtimeTotals, PropertyRefreshFailure> {
        do { return .success(try await dataClient.fetchRealtime(property: property, accessToken: accessToken)) }
        catch { return .failure(PropertyRefreshFailure(error: error)) }
    }

    private func fetchCore(property: AnalyticsProperty, accessToken: String, now: Date) async -> Result<PropertyCoreReport, PropertyRefreshFailure> {
        do { return .success(try await dataClient.fetchCore(property: property, now: now, accessToken: accessToken)) }
        catch { return .failure(PropertyRefreshFailure(error: error)) }
    }
}
