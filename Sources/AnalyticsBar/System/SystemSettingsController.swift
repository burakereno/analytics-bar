import AppKit
import Combine

@MainActor
final class SystemSettingsController: ObservableObject {
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var dockIconError: String?

    private let launchAtLoginPreference: LaunchAtLoginPreference
    private let dockIconController: DockIconController
    private var cancellables = Set<AnyCancellable>()

    init(
        preferences: AppPreferences,
        launchAtLoginPreference: LaunchAtLoginPreference? = nil,
        dockIconController: DockIconController? = nil
    ) {
        let resolvedLaunchPreference = launchAtLoginPreference ?? LaunchAtLoginPreference()
        let resolvedDockController = dockIconController ?? DockIconController()
        self.launchAtLoginPreference = resolvedLaunchPreference
        self.dockIconController = resolvedDockController
        resolvedDockController.setVisible(preferences.showsDockIcon)
        dockIconError = resolvedDockController.lastError

        preferences.$showsDockIcon
            .dropFirst()
            .sink { [weak self] visible in
                guard let self else { return }
                self.dockIconController.setVisible(visible)
                self.dockIconError = self.dockIconController.lastError
            }
            .store(in: &cancellables)

        preferences.$opensAtLogin
            .dropFirst()
            .sink { [weak self] enabled in
                Task {
                    guard let self else { return }
                    await self.launchAtLoginPreference.setEnabled(enabled)
                    self.launchAtLoginError = self.launchAtLoginPreference.lastError
                }
            }
            .store(in: &cancellables)
    }
}
