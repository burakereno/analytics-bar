import Combine
import Foundation
import OSLog

@MainActor
final class DashboardModel: ObservableObject {
    private static let logger = Logger(
        subsystem: AppConfiguration.bundleIdentifier,
        category: "dashboard"
    )

    enum ConnectionIssue: Equatable {
        case cancelled(String)
        case configuration(String)
        case permission(String)
        case other(String)

        init(error: Error) {
            let message = error.localizedDescription
            if error as? GoogleOAuthError == .cancelled {
                self = .cancelled(message)
            } else if error as? GoogleOAuthError == .configurationMissing {
                self = .configuration(message)
            } else if error as? GoogleAPIError == .permissionDenied {
                self = .permission(message)
            } else {
                self = .other(message)
            }
        }

        var message: String {
            switch self {
            case let .cancelled(message), let .configuration(message),
                 let .permission(message), let .other(message):
                message
            }
        }
    }

    enum State: Equatable {
        case disconnected
        case selectingProperties([AnalyticsProperty])
        case loading
        case loaded
        case noProperties
        case failed(message: String)
    }

    @Published private(set) var state: State = .disconnected
    @Published private(set) var snapshot: CombinedDashboardSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isDisconnecting = false
    @Published private(set) var lastManualError: String?
    @Published private(set) var connectionIssue: ConnectionIssue?
    @Published private(set) var availableProperties: [AnalyticsProperty] = []
    @Published private(set) var hasLoadedProperties = false

    @Published private(set) var connectionError: String?
    @Published private(set) var requiresReconnection = false
    @Published private(set) var presentationDate = Date()

    var maximumDataAge: TimeInterval { TimeInterval(preferences.backgroundRefreshInterval.rawValue) + 90 }

    var needsReconnection: Bool {
        requiresReconnection || snapshot?.properties.contains {
            $0.coreHealth.requiresReconnection == true || $0.realtimeHealth.requiresReconnection == true
        } == true
    }

    let preferences: AppPreferences
    private let repository: any AnalyticsRepositoryProtocol
    private let scheduler: RefreshScheduler
    private var cancellables = Set<AnyCancellable>()
    private var selectionRefreshTask: Task<Void, Never>?
    private var knownProperties: [String: AnalyticsProperty] = [:]

    var isChoosingProperties: Bool {
        if case .selectingProperties = state { return true }
        return false
    }

    var unavailableSelectedResourceNames: [String] {
        guard hasLoadedProperties else { return [] }
        return preferences.selectedPropertyResourceNames.filter { name in
            !availableProperties.contains { $0.resourceName == name }
        }
    }

    func propertyDisplayName(_ resourceName: String) -> String {
        knownProperties[resourceName]?.displayName ?? "Property \(resourceName.split(separator: "/").last ?? "")"
    }

    init(
        repository: any AnalyticsRepositoryProtocol,
        preferences: AppPreferences,
        scheduler: RefreshScheduler
    ) {
        self.repository = repository
        self.preferences = preferences
        self.scheduler = scheduler

        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.presentationDate = date }
            .store(in: &cancellables)

        scheduler.configure { [weak self] trigger in
            await self?.refresh(trigger: trigger)
        }
        scheduler.updateBackgroundInterval(preferences.backgroundRefreshInterval)

        preferences.$backgroundRefreshInterval
            .dropFirst()
            .sink { [weak scheduler] interval in
                scheduler?.updateBackgroundInterval(interval)
            }
            .store(in: &cancellables)
    }

    func bootstrap() async {
        let selectedNames = preferences.selectedPropertyResourceNames
        if let cached = await repository.cachedSnapshot(resourceNames: selectedNames) {
            rememberProperties(cached.properties.map(\.property))
            snapshot = cached.markedStale(message: "Saved data; waiting for a successful refresh.")
            state = .loaded
        }

        guard await repository.hasStoredAuthorization() else {
            requiresReconnection = true
            connectionError = "Google is not connected. Reconnect to fetch current data."
            if snapshot == nil { state = .disconnected }
            return
        }

        await refresh(trigger: .backgroundTimer, discoversProperties: true)
        // Discovery can fail temporarily. Keep retrying so recovery does not require relaunching.
        if !selectedNames.isEmpty { scheduler.start() }
    }

    func connect() async {
        guard !isRefreshing, !isDisconnecting else { return }
        let previousState = state
        let previousError = connectionError
        let previousRequiresReconnection = requiresReconnection
        selectionRefreshTask?.cancel()
        selectionRefreshTask = nil
        scheduler.stop()
        isRefreshing = true
        lastManualError = nil
        connectionIssue = nil
        connectionError = nil
        if snapshot == nil { state = .loading }
        defer { isRefreshing = false }

        do {
            availableProperties = try await repository.connect()
            hasLoadedProperties = true
            rememberProperties(availableProperties)
            requiresReconnection = false
            snapshot = snapshot?.markedStale(message: "Confirm your properties after reconnecting to Google.")
            state = availableProperties.isEmpty ? .noProperties : .selectingProperties(availableProperties)
        } catch {
            let issue = ConnectionIssue(error: error)
            connectionIssue = issue
            if case .cancelled = issue {
                state = previousState
                connectionError = previousError
                requiresReconnection = previousRequiresReconnection
                if previousState == .loaded { scheduler.start() }
            } else {
                connectionError = issue.message
                availableProperties = []
                hasLoadedProperties = false
                snapshot = snapshot?.markedStale(message: issue.message)
                state = snapshot == nil ? .failed(message: issue.message) : .loaded
                if snapshot != nil { scheduler.start() }
            }
        }
    }

    func confirmSelection(_ resourceNames: [String]) async {
        guard !isDisconnecting else { return }
        selectionRefreshTask?.cancel()
        selectionRefreshTask = nil
        let validNames = validSelection(resourceNames, preservingUnavailable: false)
        guard !validNames.isEmpty else {
            state = .selectingProperties(availableProperties)
            return
        }

        preferences.selectedPropertyResourceNames = validNames
        state = snapshot == nil ? .loading : .loaded
        invalidateSelection()
        await refresh(trigger: .manual)
        scheduler.start()
    }

    func updateSelection(_ resourceNames: [String]) {
        guard !isDisconnecting else { return }
        let validNames = validSelection(resourceNames)
        if validNames.isEmpty {
            guard resourceNames.isEmpty,
                  !preferences.selectedPropertyResourceNames.isEmpty,
                  unavailableSelectedResourceNames.count == preferences.selectedPropertyResourceNames.count else { return }
            selectionRefreshTask?.cancel()
            selectionRefreshTask = nil
            preferences.selectedPropertyResourceNames = []
            snapshot = nil
            connectionError = nil
            scheduler.stop()
            state = availableProperties.isEmpty ? .noProperties : .selectingProperties(availableProperties)
            return
        }

        preferences.selectedPropertyResourceNames = validNames
        state = snapshot == nil ? .loading : .loaded
        invalidateSelection()
        selectionRefreshTask?.cancel()
        selectionRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            await self.refresh(trigger: .manual)
            guard !Task.isCancelled else { return }
            self.scheduler.start()
            self.selectionRefreshTask = nil
        }
    }

    func showPropertySelection() {
        scheduler.stop()
        state = availableProperties.isEmpty ? .noProperties : .selectingProperties(availableProperties)
    }

    func checkConnection() async {
        await refresh(trigger: .manual, discoversProperties: true)
    }

    func refresh(trigger: RefreshTrigger, discoversProperties: Bool = false) async {
        while isRefreshing {
            guard trigger == .manual, !isDisconnecting else { return }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        guard !Task.isCancelled, !isDisconnecting, !isChoosingProperties else { return }
        guard discoversProperties || !preferences.selectedPropertyResourceNames.isEmpty else { return }
        isRefreshing = true
        presentationDate = Date()
        if trigger == .manual { lastManualError = nil }
        if snapshot == nil { state = .loading }
        defer { isRefreshing = false }
        let requestedNames = preferences.selectedPropertyResourceNames

        do {
            if discoversProperties || availableProperties.isEmpty {
                availableProperties = try await repository.availableProperties()
                hasLoadedProperties = true
                rememberProperties(availableProperties)
            }
            let properties = selectedProperties
            let missing = unavailableSelectedResourceNames
            guard !properties.isEmpty || !missing.isEmpty else {
                snapshot = nil
                state = availableProperties.isEmpty ? .noProperties : .selectingProperties(availableProperties)
                connectionError = nil
                requiresReconnection = false
                return
            }
            let updated = properties.isEmpty ? DashboardAggregator.aggregate([])
                : try await repository.refreshSelectedProperties(properties, trigger: trigger, now: Date())
            guard requestedNames == preferences.selectedPropertyResourceNames else { return }
            rememberProperties(updated.properties.map(\.property))
            let unavailable = missing.map { unavailableSnapshot($0) }
            let values = updated.properties + unavailable
            snapshot = DashboardAggregator.aggregate(requestedNames.compactMap { name in
                values.first { $0.property.resourceName == name }
            })
            presentationDate = Date()
            connectionError = missing.isEmpty ? nil : "Some selected properties are no longer accessible. Review your property selection."
            connectionIssue = nil
            requiresReconnection = false
            state = .loaded
        } catch {
            guard !Task.isCancelled, requestedNames == preferences.selectedPropertyResourceNames else { return }
            Self.logger.error("Analytics refresh failed: \(error.localizedDescription, privacy: .public)")
            connectionError = error.localizedDescription
            requiresReconnection = error as? AnalyticsRepositoryError == .authorizationExpired
                || error as? GoogleOAuthError == .authorizationExpired
                || error as? GoogleAPIError == .authorizationExpired
            if trigger == .manual { lastManualError = error.localizedDescription }
            if let existing = snapshot {
                snapshot = existing.markedStale(message: error.localizedDescription, attemptedAt: Date())
                state = .loaded
            } else if requiresReconnection {
                state = .disconnected
            } else {
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    func popoverDidOpen() {
        scheduler.setPopoverOpen(true)
        guard !preferences.selectedPropertyResourceNames.isEmpty else { return }
        Task { await refresh(trigger: .popoverOpened) }
    }

    func popoverDidClose() {
        scheduler.setPopoverOpen(false)
    }

    func disconnect() async {
        guard !isDisconnecting else { return }
        isDisconnecting = true
        defer { isDisconnecting = false }
        selectionRefreshTask?.cancel()
        selectionRefreshTask = nil
        scheduler.stop()
        while isRefreshing {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await repository.disconnect()
        } catch {
            let message = "Could not finish disconnecting: \(error.localizedDescription)"
            connectionError = message
            lastManualError = message
            requiresReconnection = !(await repository.hasStoredAuthorization())
            if requiresReconnection { snapshot = snapshot?.markedStale(message: message) }
            if !requiresReconnection, !isChoosingProperties { scheduler.start() }
            return
        }
        preferences.selectedPropertyResourceNames = []
        availableProperties = []
        hasLoadedProperties = false
        knownProperties = [:]
        snapshot = nil
        connectionError = nil
        requiresReconnection = false
        lastManualError = nil
        connectionIssue = nil
        state = .disconnected
    }

    private var selectedProperties: [AnalyticsProperty] {
        preferences.selectedPropertyResourceNames.compactMap { resourceName in
            availableProperties.first(where: { $0.resourceName == resourceName })
        }
    }

    private func invalidateSelection() {
        guard let snapshot else { return }
        let names = preferences.selectedPropertyResourceNames
        let retained = names.compactMap { name in snapshot.properties.first { $0.property.resourceName == name } }
        if retained.count == names.count {
            self.snapshot = DashboardAggregator.aggregate(retained)
                .markedStale(message: "Selection changed; waiting for current data.")
        } else {
            self.snapshot = nil
            state = .loading
        }
    }

    private func rememberProperties(_ properties: [AnalyticsProperty]) {
        for property in properties { knownProperties[property.resourceName] = property }
    }

    private func unavailableSnapshot(_ resourceName: String) -> PropertyDashboardSnapshot {
        let message = "This property is missing from Google's property list. Remove it in Settings or reload accounts & sites."
        if let saved = snapshot?.properties.first(where: { $0.property.resourceName == resourceName }) {
            return saved.markedStale(message: message)
        }
        let id = String(resourceName.split(separator: "/").last ?? "")
        let property = knownProperties[resourceName] ?? AnalyticsProperty(
            id: id, resourceName: resourceName, accountResourceName: "unavailable",
            accountDisplayName: "Unavailable", displayName: "Property \(id)",
            timeZoneIdentifier: "", currencyCode: ""
        )
        let health = ReportStatus(lastSuccess: nil, lastAttempt: nil, message: message, verified: false)
        return PropertyDashboardSnapshot(
            property: property, live: .zero, today: .zero, yesterdayThroughSameHour: .zero,
            sevenDay: [:], topPages: [], topSources: [], fetchedAt: .distantPast,
            freshness: .stale, refreshMessage: message, realtimeStatus: health, coreStatus: health
        )
    }

    private func validSelection(_ resourceNames: [String], preservingUnavailable: Bool = true) -> [String] {
        let uniqueNames = resourceNames.reduce(into: [String]()) { result, name in
            if !result.contains(name) { result.append(name) }
        }
        return uniqueNames.filter { name in
            availableProperties.contains(where: { $0.resourceName == name })
                || (preservingUnavailable && preferences.selectedPropertyResourceNames.contains(name))
        }
    }
}
