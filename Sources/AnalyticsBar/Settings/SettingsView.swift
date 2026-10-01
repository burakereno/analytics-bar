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
                    subtitle: systemSettings.launchAtLoginSubtitle,
                    isOn: $preferences.opensAtLogin,
                    isEnabled: !systemSettings.isUpdatingLaunchAtLogin && systemSettings.launchAtLoginStatus != .unavailable
                )
                if systemSettings.launchAtLoginStatus == .requiresApproval {
                    Button("Open macOS Settings") { systemSettings.openLoginItemSettings() }
                        .buttonStyle(.plain).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange).padding(.top, 6)
                }
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
                    title: "Panel closed",
                    subtitle: "Panel open: every 60 seconds",
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
                    isOn: $preferences.showsDockIcon,
                    isEnabled: !systemSettings.isUpdatingDockIcon
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
        .onAppear { systemSettings.synchronizeSystemSettings() }
    }
}

extension MenuBarMetric {
    var title: String {
        switch self {
        case .sessionsLast7Days: "Sessions · last 7 days"
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
