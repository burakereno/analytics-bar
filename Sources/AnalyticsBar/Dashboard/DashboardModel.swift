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
    @Published private(set) var lastManualError: String?
    @Published private(set) var connectionIssue: ConnectionIssue?
    @Published private(set) var availableProperties: [AnalyticsProperty] = []

    let preferences: AppPreferences
    private let repository: any AnalyticsRepositoryProtocol
    private let scheduler: RefreshScheduler
    private var cancellables = Set<AnyCancellable>()

    init(
        repository: any AnalyticsRepositoryProtocol,
        preferences: AppPreferences,
        scheduler: RefreshScheduler
    ) {
        self.repository = repository
        self.preferences = preferences
        self.scheduler = scheduler

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
        if let cached = await repository.cachedSnapshot(resourceNames: selectedNames.isEmpty ? nil : selectedNames) {
            snapshot = cached
            state = .loaded
        }

        guard await repository.hasStoredAuthorization() else {
            if snapshot == nil { state = .disconnected }
            return
        }

        do {
            availableProperties = try await repository.availableProperties()
            let selected = selectedProperties
            if selected.isEmpty {
                state = availableProperties.isEmpty ? .noProperties : .selectingProperties(availableProperties)
            } else {
                await refresh(trigger: .backgroundTimer)
                scheduler.start()
            }
        } catch {
            if snapshot == nil { state = .failed(message: error.localizedDescription) }
        }
    }

    func connect() async {
        isRefreshing = true
        lastManualError = nil
        connectionIssue = nil
        if snapshot == nil { state = .loading }
        defer { isRefreshing = false }

        do {
            availableProperties = try await repository.connect()
            state = availableProperties.isEmpty ? .noProperties : .selectingProperties(availableProperties)
        } catch {
            let issue = ConnectionIssue(error: error)
            connectionIssue = issue
            if case .cancelled = issue {
                state = .disconnected
            } else {
                state = .failed(message: issue.message)
            }
        }
    }

    func confirmSelection(_ resourceNames: [String]) async {
        let uniqueNames = resourceNames.reduce(into: [String]()) { result, name in
            if !result.contains(name) { result.append(name) }
        }
        let validNames = uniqueNames.filter { name in
            availableProperties.contains(where: { $0.resourceName == name })
        }
        guard !validNames.isEmpty else {
            state = .selectingProperties(availableProperties)
            return
        }

        preferences.selectedPropertyResourceNames = validNames
        await refresh(trigger: .manual)
        scheduler.start()
    }

    func showPropertySelection() {
        state = availableProperties.isEmpty ? .noProperties : .selectingProperties(availableProperties)
    }

    func refresh(trigger: RefreshTrigger) async {
        let properties = selectedProperties
        guard !properties.isEmpty, !isRefreshing else { return }

        isRefreshing = true
        if trigger == .manual { lastManualError = nil }
        if snapshot == nil { state = .loading }
        defer { isRefreshing = false }

        do {
            snapshot = try await repository.refreshSelectedProperties(
                properties,
                trigger: trigger,
                now: Date()
            )
            state = .loaded
        } catch {
            Self.logger.error("Analytics refresh failed: \(error.localizedDescription, privacy: .public)")
            if trigger == .manual { lastManualError = error.localizedDescription }
            if snapshot != nil {
                state = .loaded
            } else if error as? AnalyticsRepositoryError == .authorizationExpired {
                state = .disconnected
            } else {
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    func popoverDidOpen() {
        scheduler.setPopoverOpen(true)
        guard !selectedProperties.isEmpty else { return }
        Task { await refresh(trigger: .popoverOpened) }
    }

    func popoverDidClose() {
        scheduler.setPopoverOpen(false)
    }

    func disconnect() async {
        scheduler.stop()
        do { try await repository.disconnect() } catch {}
        preferences.selectedPropertyResourceNames = []
        availableProperties = []
        snapshot = nil
        lastManualError = nil
        connectionIssue = nil
        state = .disconnected
    }

    private var selectedProperties: [AnalyticsProperty] {
        preferences.selectedPropertyResourceNames.compactMap { resourceName in
            availableProperties.first(where: { $0.resourceName == resourceName })
        }
    }
}
