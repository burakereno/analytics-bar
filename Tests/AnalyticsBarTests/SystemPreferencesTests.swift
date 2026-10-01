import AppKit
import XCTest
@testable import AnalyticsBar

@MainActor
final class SystemPreferencesTests: XCTestCase {
    func testLaunchAtLoginMapsStatusAndSurfacesErrors() async {
        let service = LaunchAtLoginServiceSpy(status: .disabled)
        let preference = LaunchAtLoginPreference(service: service)

        XCTAssertEqual(preference.status, .disabled)
        await preference.setEnabled(true)
        XCTAssertEqual(service.registerCount, 1)
        XCTAssertEqual(preference.status, .enabled)
        XCTAssertNil(preference.lastError)

        service.nextError = TestSystemPreferenceError.failed
        await preference.setEnabled(false)
        XCTAssertEqual(service.unregisterCount, 1)
        XCTAssertEqual(preference.lastError, "System preference failed")
    }

    func testDockControllerMapsVisibilityToActivationPolicy() {
        let applier = DockActivationPolicySpy()
        let controller = DockIconController(applier: applier)

        XCTAssertTrue(controller.setVisible(false))
        XCTAssertTrue(controller.setVisible(true))
        XCTAssertEqual(applier.policies, [.accessory, .regular])
        XCTAssertTrue(controller.isVisible)
    }

    func testPreferenceChangesApplySystemValuesExactlyOnce() async {
        let defaults = UserDefaults(suiteName: "SystemPreferencesTests.\(UUID().uuidString)")!
        let preferences = AppPreferences(defaults: defaults)
        let launchService = LaunchAtLoginServiceSpy(status: .disabled)
        let launchPreference = LaunchAtLoginPreference(service: launchService)
        let dockApplier = DockActivationPolicySpy()
        let dockController = DockIconController(applier: dockApplier)
        let controller = SystemSettingsController(
            preferences: preferences,
            launchAtLoginPreference: launchPreference,
            dockIconController: dockController
        )

        XCTAssertEqual(dockApplier.policies, [.accessory])

        preferences.showsDockIcon = true
        preferences.opensAtLogin = true
        while controller.isUpdatingLaunchAtLogin || controller.isUpdatingDockIcon { await Task.yield() }

        XCTAssertEqual(dockApplier.policies, [.accessory, .regular])
        XCTAssertEqual(launchService.registerCount, 1)
        XCTAssertNil(controller.launchAtLoginError)
    }

    func testStartupReconcilesSavedPreferenceWithActualLoginStatus() {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.opensAtLogin = true
        let service = LaunchAtLoginServiceSpy(status: .disabled)
        let controller = SystemSettingsController(preferences: preferences,
            launchAtLoginPreference: LaunchAtLoginPreference(service: service),
            dockIconController: DockIconController(applier: DockActivationPolicySpy()))
        XCTAssertFalse(preferences.opensAtLogin)
        XCTAssertEqual(controller.launchAtLoginStatus, .disabled)
        XCTAssertEqual(service.registerCount, 0)
        service.status = .enabled
        controller.synchronizeSystemSettings()
        XCTAssertTrue(preferences.opensAtLogin)
        XCTAssertEqual(controller.launchAtLoginStatus, .enabled)
    }

    func testFailedLoginAndDockChangesRollbackTheirSwitches() async {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = LaunchAtLoginServiceSpy(status: .disabled)
        let applier = DockActivationPolicySpy()
        let controller = SystemSettingsController(preferences: preferences,
            launchAtLoginPreference: LaunchAtLoginPreference(service: service),
            dockIconController: DockIconController(applier: applier))
        service.nextError = TestSystemPreferenceError.failed
        applier.succeeds = false
        preferences.opensAtLogin = true
        preferences.showsDockIcon = true
        while controller.isUpdatingLaunchAtLogin || controller.isUpdatingDockIcon { await Task.yield() }
        XCTAssertFalse(preferences.opensAtLogin)
        XCTAssertFalse(preferences.showsDockIcon)
        XCTAssertNotNil(controller.launchAtLoginError)
        XCTAssertNotNil(controller.dockIconError)
    }

    func testApprovalRequiredIsPublished() async {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = LaunchAtLoginServiceSpy(status: .disabled)
        service.registrationStatus = .requiresApproval
        let controller = SystemSettingsController(preferences: preferences,
            launchAtLoginPreference: LaunchAtLoginPreference(service: service),
            dockIconController: DockIconController(applier: DockActivationPolicySpy()))
        preferences.opensAtLogin = true
        while controller.isUpdatingLaunchAtLogin { await Task.yield() }
        XCTAssertEqual(controller.launchAtLoginStatus, .requiresApproval)
        XCTAssertTrue(controller.launchAtLoginSubtitle.contains("Approval required"))
        XCTAssertTrue(preferences.opensAtLogin)
        XCTAssertNil(controller.launchAtLoginError)
    }

    func testRapidLoginChangesApplyTheLastRequestedValue() async {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let service = LaunchAtLoginServiceSpy(status: .disabled)
        let controller = SystemSettingsController(preferences: preferences,
            launchAtLoginPreference: LaunchAtLoginPreference(service: service),
            dockIconController: DockIconController(applier: DockActivationPolicySpy()))
        preferences.opensAtLogin = true
        preferences.opensAtLogin = false
        while controller.isUpdatingLaunchAtLogin { await Task.yield() }
        XCTAssertEqual(service.status, .disabled)
        XCTAssertFalse(preferences.opensAtLogin)
        XCTAssertEqual(service.registerCount, 0)
        XCTAssertEqual(service.unregisterCount, 1)
    }
}

@MainActor
private final class LaunchAtLoginServiceSpy: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus
    var nextError: Error?
    var registrationStatus: LaunchAtLoginStatus = .enabled
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if let nextError { throw nextError }
        status = registrationStatus
    }

    func unregister() async throws {
        unregisterCount += 1
        if let nextError { throw nextError }
        status = .disabled
    }
}

@MainActor
private final class DockActivationPolicySpy: DockActivationPolicyApplying {
    private(set) var policies: [NSApplication.ActivationPolicy] = []
    var succeeds = true

    func apply(_ policy: NSApplication.ActivationPolicy) -> Bool {
        policies.append(policy)
        return succeeds
    }
}

private enum TestSystemPreferenceError: Error, LocalizedError {
    case failed
    var errorDescription: String? { "System preference failed" }
}
