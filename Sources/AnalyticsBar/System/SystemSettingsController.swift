import AppKit
import Combine

@MainActor
final class SystemSettingsController: ObservableObject {
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var dockIconError: String?
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus
    @Published private(set) var isUpdatingLaunchAtLogin = false
    @Published private(set) var isUpdatingDockIcon = false

    private let preferences: AppPreferences
    private let launchAtLoginPreference: LaunchAtLoginPreference
    private let dockIconController: DockIconController
    private var cancellables = Set<AnyCancellable>()
    private var isSynchronizing = false
    private var desiredLaunchState: Bool?
    private var launchTask: Task<Void, Never>?

    var launchAtLoginSubtitle: String {
        switch launchAtLoginStatus {
        case .disabled: "Open Analytics Bar when you log in"
        case .enabled: "Enabled in macOS Login Items"
        case .requiresApproval: "Approval required in macOS Login Items"
        case .unavailable: "Login Items is unavailable for this app location"
        }
    }

    init(preferences: AppPreferences, launchAtLoginPreference: LaunchAtLoginPreference? = nil,
         dockIconController: DockIconController? = nil) {
        self.preferences = preferences
        let launch = launchAtLoginPreference ?? LaunchAtLoginPreference()
        let dock = dockIconController ?? DockIconController()
        self.launchAtLoginPreference = launch
        self.dockIconController = dock
        launchAtLoginStatus = launch.status
        preferences.opensAtLogin = launch.status.isRegistered
        dock.setVisible(preferences.showsDockIcon)
        dockIconError = dock.lastError
        preferences.showsDockIcon = dock.isVisible

        preferences.$showsDockIcon.dropFirst().sink { [weak self] visible in
            guard let self, !self.isSynchronizing else { return }
            self.isUpdatingDockIcon = true
            // Published emits before assignment; reconcile after the preference is assigned.
            Task { [weak self] in
                guard let self else { return }
                guard self.preferences.showsDockIcon == visible else {
                    self.isUpdatingDockIcon = false
                    return
                }
                self.dockIconController.setVisible(visible)
                self.dockIconError = self.dockIconController.lastError
                self.isUpdatingDockIcon = false
                self.reconcilePreferences()
            }
        }.store(in: &cancellables)

        preferences.$opensAtLogin.dropFirst().sink { [weak self] enabled in
            guard let self, !self.isSynchronizing else { return }
            self.desiredLaunchState = enabled
            self.isUpdatingLaunchAtLogin = true
            guard self.launchTask == nil else { return }
            self.launchTask = Task { [weak self] in
                guard let self else { return }
                while let desired = self.desiredLaunchState {
                    self.desiredLaunchState = nil
                    await self.launchAtLoginPreference.setEnabled(desired)
                    self.launchAtLoginStatus = self.launchAtLoginPreference.status
                    self.launchAtLoginError = self.launchAtLoginPreference.lastError
                }
                self.isUpdatingLaunchAtLogin = false
                self.reconcilePreferences()
                self.launchTask = nil
            }
        }.store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.synchronizeSystemSettings() }
            .store(in: &cancellables)
    }

    func synchronizeSystemSettings() {
        guard !isUpdatingLaunchAtLogin, !isUpdatingDockIcon else { return }
        launchAtLoginPreference.refreshStatus()
        launchAtLoginStatus = launchAtLoginPreference.status
        reconcilePreferences()
    }

    func openLoginItemSettings() { launchAtLoginPreference.openSystemSettings() }

    private func reconcilePreferences() {
        isSynchronizing = true
        defer { isSynchronizing = false }
        if !isUpdatingLaunchAtLogin {
            preferences.opensAtLogin = launchAtLoginStatus.isRegistered
        }
        if !isUpdatingDockIcon, preferences.showsDockIcon != dockIconController.isVisible {
            preferences.showsDockIcon = dockIconController.isVisible
        }
    }
}
