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
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionCard("STARTUP") {
                SettingsToggleRow(
                    icon: "power",
                    title: "Open at Login",
                    subtitle: "Open Analytics Bar when you log in",
                    isOn: $preferences.opensAtLogin
                )
                if let error = systemSettings.launchAtLoginError {
                    SettingsErrorText(message: error)
                }
            }

            SettingsSectionCard("CONNECTION") {
                ConnectionSettingsView(model: model, close: close)
            }

            SettingsSectionCard("PROPERTIES") {
                PropertySettingsView(model: model)
            }

            SettingsSectionCard("MENU BAR") {
                SettingsMenuRow(
                    icon: "menubar.rectangle",
                    title: "Display",
                    subtitle: "Choose the metric shown in the menu bar",
                    options: MenuBarMetric.allCases,
                    selection: $preferences.menuBarMetric,
                    optionTitle: { $0.title }
                )
            }

            SettingsSectionCard("REFRESH") {
                SettingsSegmentedRow(
                    icon: "arrow.clockwise",
                    title: "Background",
                    subtitle: "Every 60 seconds while this panel is open",
                    options: BackgroundRefreshInterval.allCases,
                    selection: $preferences.backgroundRefreshInterval,
                    optionTitle: { $0.shortTitle }
                )
            }

            SettingsSectionCard("DASHBOARD") {
                SettingsToggleRow(
                    icon: "turkishlirasign.circle",
                    title: "Revenue",
                    subtitle: "Show total revenue in the dashboard",
                    isOn: $preferences.showsRevenue
                )
            }

            SettingsSectionCard("DOCK") {
                SettingsToggleRow(
                    icon: "dock.rectangle",
                    title: "Dock Icon",
                    subtitle: "Show Analytics Bar in the Dock",
                    isOn: $preferences.showsDockIcon
                )
                if let error = systemSettings.dockIconError {
                    SettingsErrorText(message: error)
                }
            }

            SettingsSectionCard("ABOUT") {
                UpdateSettingsView(checker: updateChecker, installer: updateInstaller)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .tint(.orange)
        .accentColor(.orange)
    }
}

extension MenuBarMetric {
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

extension BackgroundRefreshInterval {
    var shortTitle: String {
        switch self {
        case .fiveMinutes: "5m"
        case .fifteenMinutes: "15m"
        case .thirtyMinutes: "30m"
        }
    }
}
