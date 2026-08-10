import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var systemSettings: SystemSettingsController
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject var updateInstaller: UpdateInstaller
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsSection("CONNECTION") {
                    ConnectionSettingsView(model: model, close: close)
                }

                settingsSection("PROPERTIES") {
                    PropertySettingsView(model: model, close: close)
                }

                settingsSection("MENU BAR") {
                    Picker("Metric", selection: $preferences.menuBarMetric) {
                        ForEach(MenuBarMetric.allCases, id: \.self) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                }

                settingsSection("REFRESH") {
                    Picker("Background", selection: $preferences.backgroundRefreshInterval) {
                        ForEach(BackgroundRefreshInterval.allCases, id: \.self) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }
                    Text("Refreshes every 60 seconds while the popover is open.")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }

                settingsSection("DASHBOARD") {
                    Toggle("Show revenue", isOn: $preferences.showsRevenue)
                }

                settingsSection("STARTUP") {
                    Toggle("Open at login", isOn: $preferences.opensAtLogin)
                    if let error = systemSettings.launchAtLoginError {
                        Text(error)
                            .font(.system(size: 8))
                            .foregroundStyle(.red)
                    }
                }

                settingsSection("DOCK") {
                    Toggle("Show Dock icon", isOn: $preferences.showsDockIcon)
                    if let error = systemSettings.dockIconError {
                        Text(error)
                            .font(.system(size: 8))
                            .foregroundStyle(.red)
                    }
                }

                settingsSection("ABOUT") {
                    UpdateSettingsView(checker: updateChecker, installer: updateInstaller)
                }

                HStack {
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 10, content: content)
                .font(.system(size: 10, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                }
        }
    }
}

private extension MenuBarMetric {
    var title: String {
        switch self {
        case .realtimeActiveUsers: "Live active users"
        case .usersToday: "Users today"
        case .sessionsToday: "Sessions today"
        case .viewsToday: "Views today"
        case .iconOnly: "Icon only"
        }
    }
}

private extension BackgroundRefreshInterval {
    var title: String {
        switch self {
        case .fiveMinutes: "Every 5 minutes"
        case .fifteenMinutes: "Every 15 minutes"
        case .thirtyMinutes: "Every 30 minutes"
        }
    }
}
