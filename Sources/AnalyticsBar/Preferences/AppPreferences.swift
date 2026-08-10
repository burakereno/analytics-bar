import Combine
import Foundation

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
    case thirtyMinutes = 1_800
}

@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let menuBarMetric = "menuBarMetric"
        static let backgroundRefreshInterval = "backgroundRefreshInterval"
        static let selectedProperties = "selectedPropertyResourceNames"
        static let showsRevenue = "showsRevenue"
        static let opensAtLogin = "opensAtLogin"
        static let showsDockIcon = "showsDockIcon"
    }

    private let defaults: UserDefaults

    @Published var menuBarMetric: MenuBarMetric {
        didSet { defaults.set(menuBarMetric.rawValue, forKey: Key.menuBarMetric) }
    }

    @Published var backgroundRefreshInterval: BackgroundRefreshInterval {
        didSet { defaults.set(backgroundRefreshInterval.rawValue, forKey: Key.backgroundRefreshInterval) }
    }

    @Published var selectedPropertyResourceNames: [String] {
        didSet { persistSelectedProperties() }
    }

    @Published var showsRevenue: Bool {
        didSet { defaults.set(showsRevenue, forKey: Key.showsRevenue) }
    }

    @Published var opensAtLogin: Bool {
        didSet { defaults.set(opensAtLogin, forKey: Key.opensAtLogin) }
    }

    @Published var showsDockIcon: Bool {
        didSet { defaults.set(showsDockIcon, forKey: Key.showsDockIcon) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarMetric = MenuBarMetric(
            rawValue: defaults.string(forKey: Key.menuBarMetric) ?? ""
        ) ?? .realtimeActiveUsers
        backgroundRefreshInterval = BackgroundRefreshInterval(
            rawValue: defaults.integer(forKey: Key.backgroundRefreshInterval)
        ) ?? .fiveMinutes
        if let data = defaults.data(forKey: Key.selectedProperties),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            selectedPropertyResourceNames = decoded
        } else {
            selectedPropertyResourceNames = []
        }
        showsRevenue = defaults.object(forKey: Key.showsRevenue) as? Bool ?? true
        opensAtLogin = defaults.bool(forKey: Key.opensAtLogin)
        showsDockIcon = defaults.bool(forKey: Key.showsDockIcon)
    }

    private func persistSelectedProperties() {
        guard let data = try? JSONEncoder().encode(selectedPropertyResourceNames) else { return }
        defaults.set(data, forKey: Key.selectedProperties)
    }
}
