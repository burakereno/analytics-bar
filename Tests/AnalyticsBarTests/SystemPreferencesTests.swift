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
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(dockApplier.policies, [.accessory, .regular])
        XCTAssertEqual(launchService.registerCount, 1)
        XCTAssertNil(controller.launchAtLoginError)
    }
}

@MainActor
private final class LaunchAtLoginServiceSpy: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus
    var nextError: Error?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if let nextError { throw nextError }
        status = .enabled
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

    func apply(_ policy: NSApplication.ActivationPolicy) -> Bool {
        policies.append(policy)
        return true
    }
}

private enum TestSystemPreferenceError: Error, LocalizedError {
    case failed
    var errorDescription: String? { "System preference failed" }
}
