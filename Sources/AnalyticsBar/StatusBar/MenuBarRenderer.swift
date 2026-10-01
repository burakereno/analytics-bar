import AppKit

struct MenuBarTitle: Equatable, Sendable {
    let metric: MenuBarMetric
    let value: String?
    let accessibilityLabel: String
    var warning = false
}

enum MenuBarRenderer {
    static func title(
        snapshot: CombinedDashboardSnapshot?,
        metric: MenuBarMetric,
        now: Date = Date(),
        maximumAge: TimeInterval = 390,
        connectionError: String? = nil
    ) -> MenuBarTitle {
        let number: Int?
        let label: String
        let coreCurrent = snapshot?.hasCurrentCore(at: now, maximumAge: maximumAge) == true
        let liveCurrent = snapshot?.hasCurrentRealtime(at: now, maximumAge: maximumAge) == true
        let current: Bool
        switch metric {
        case .sessionsLast7Days:
            number = snapshot?.weeklySessions
            label = "sessions in the last 7 complete days"
            current = coreCurrent && number != nil
        case .realtimeActiveUsers:
            number = snapshot?.live.activeUsers
            label = "active users in the last 30 minutes"
            current = liveCurrent
        case .usersToday:
            number = snapshot?.today.activeUsers
            label = "users today"
            current = coreCurrent
        case .sessionsToday:
            number = snapshot?.today.sessions
            label = "sessions today"
            current = coreCurrent
        case .viewsToday:
            number = snapshot?.today.views
            label = "views today"
            current = coreCurrent
        case .iconOnly:
            number = nil
            label = "Google Analytics"
            current = coreCurrent && liveCurrent
        }

        let warning = !coreCurrent || !liveCurrent || connectionError != nil || !current
        let value = metric == .iconOnly ? nil : current && connectionError == nil
            ? number.map(DashboardPresentation.compactNumber) ?? "—" : "—"
        var accessibility = value.map { "\($0) \(label)" } ?? label
        if current, let snapshot {
            let successes = snapshot.properties.compactMap {
                metric == .realtimeActiveUsers ? $0.realtimeHealth.lastSuccess : $0.coreHealth.lastSuccess
            }
            if let last = successes.min() {
                accessibility += ". Last successful report: " + DashboardPresentation.age(last, relativeTo: now)
            }
        }
        if warning { accessibility += ". Data needs attention. " + (connectionError ?? "Open Analytics Bar to check report status.") }
        return MenuBarTitle(metric: metric, value: value, accessibilityLabel: accessibility, warning: warning)
    }

    @MainActor
    static func attributedTitle(for title: MenuBarTitle) -> NSAttributedString {
        NSAttributedString(
            string: title.value ?? "",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)]
        )
    }

    @MainActor
    static func image(for title: MenuBarTitle) -> NSImage? {
        let symbol = NSImage(
            systemSymbolName: title.warning ? "exclamationmark.triangle" : "chart.xyaxis.line",
            accessibilityDescription: title.accessibilityLabel
        )
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = symbol?.withSymbolConfiguration(configuration) ?? symbol
        image?.isTemplate = true
        image?.accessibilityDescription = title.accessibilityLabel
        return image
    }
}
