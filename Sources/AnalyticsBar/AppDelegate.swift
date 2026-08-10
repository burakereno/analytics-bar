import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment.live()
        self.environment = environment
        statusBarController = StatusBarController(
            model: environment.model,
            preferences: environment.preferences,
            systemSettings: environment.systemSettings,
            updateChecker: environment.updateChecker,
            updateInstaller: environment.updateInstaller
        )
        Task {
            await environment.model.bootstrap()
            if environment.checksForUpdatesAutomatically {
                await environment.updateChecker.checkAutomatically()
            }
        }
    }
}
