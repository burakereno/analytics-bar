import AppKit

struct MenuBarTitle: Equatable, Sendable {
    let metric: MenuBarMetric
    let value: String?
    let accessibilityLabel: String
}

enum MenuBarRenderer {
    static func title(
        snapshot: CombinedDashboardSnapshot?,
        metric: MenuBarMetric
    ) -> MenuBarTitle {
        let number: Int?
        let label: String
        switch metric {
        case .realtimeActiveUsers:
            number = snapshot?.live.activeUsers
            label = "active users in the last 30 minutes"
        case .usersToday:
            number = snapshot?.today.activeUsers
            label = "users today"
        case .sessionsToday:
            number = snapshot?.today.sessions
            label = "sessions today"
        case .viewsToday:
            number = snapshot?.today.views
            label = "views today"
        case .iconOnly:
            number = nil
            label = "Google Analytics"
        }

        let value = metric == .iconOnly ? nil : number.map(DashboardPresentation.compactNumber) ?? "--"
        let accessibility = value.map { "\($0) \(label)" } ?? label
        return MenuBarTitle(metric: metric, value: value, accessibilityLabel: accessibility)
    }

    static func contentWidth(for title: MenuBarTitle) -> CGFloat {
        let iconWidth: CGFloat = 15
        let padding: CGFloat = 8
        guard let value = title.value else { return iconWidth + padding }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        ]
        let textWidth = ceil((value as NSString).size(withAttributes: attributes).width)
        return padding + iconWidth + 4 + textWidth
    }

    @MainActor
    static func image(for title: MenuBarTitle) -> NSImage {
        let width = contentWidth(for: title)
        let height: CGFloat = 18
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        let symbol = NSImage(systemSymbolName: "chart.xyaxis.line", accessibilityDescription: title.accessibilityLabel)
        symbol?.isTemplate = true
        symbol?.draw(in: NSRect(x: 4, y: 2, width: 14, height: 14))

        if let value = title.value {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
            (value as NSString).draw(at: NSPoint(x: 22, y: 2), withAttributes: attributes)
        }

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = title.accessibilityLabel
        return image
    }
}
