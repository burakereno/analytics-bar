import AppKit
import SwiftUI
import XCTest
@testable import AnalyticsBar

@MainActor
final class PopoverContentSizingTests: XCTestCase {
    func testEightPropertyDashboardHeightDoesNotDependOnViewport() async throws {
        try await assertStablePreferredHeight(startsInSettings: false)
    }

    func testSettingsHeightDoesNotDependOnViewport() async throws {
        try await assertStablePreferredHeight(startsInSettings: true)
    }

    private func assertStablePreferredHeight(
        startsInSettings: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        _ = NSApplication.shared
        let suiteName = "PopoverContentSizingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let snapshots = try XCTUnwrap(DashboardPreviewFixtures.snapshots(named: "eight"))
        let preferences = AppPreferences(defaults: defaults)
        preferences.selectedPropertyResourceNames = snapshots.map(\.property.resourceName)
        let scheduler = RefreshScheduler()
        defer { scheduler.stop() }
        let model = DashboardModel(
            repository: SizingFixtureRepository(snapshots: snapshots),
            preferences: preferences,
            scheduler: scheduler
        )
        await model.bootstrap()
        scheduler.stop()
        XCTAssertEqual(model.state, .loaded, file: file, line: line)

        let settings = SystemSettingsController(
            preferences: preferences,
            launchAtLoginPreference: LaunchAtLoginPreference(service: SizingLoginService()),
            dockIconController: DockIconController(applier: SizingDockApplier())
        )
        var reportedHeights: [CGFloat] = []
        let hostingController = NSHostingController(rootView: DashboardView(
            model: model,
            systemSettings: settings,
            updateChecker: UpdateChecker(),
            updateInstaller: UpdateInstaller(terminateApplication: {}),
            startsInSettings: startsInSettings,
            onPreferredHeightChange: { reportedHeights.append($0) }
        ))
        // Exercise the hosting layout without letting its intrinsic size resize
        // the parent. The parent supplies the viewport just as NSPopover does.
        hostingController.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: PopoverLayout.width, height: 270),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        defer {
            window.contentViewController = nil
            window.close()
        }

        var settledHeights: [CGFloat] = []
        let viewportHeights: [CGFloat] = [270, 650, 220]
        for viewportHeight in viewportHeights {
            window.setContentSize(NSSize(width: PopoverLayout.width, height: viewportHeight))
            hostingController.view.frame = NSRect(
                x: 0, y: 0, width: PopoverLayout.width, height: viewportHeight
            )
            // Geometry actions are delivered after layout. Use a fixed number
            // of turns so a regression cannot create an unbounded wait, and do
            // not resize the window from the geometry callback itself.
            for _ in 0..<6 {
                hostingController.view.needsLayout = true
                hostingController.view.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(20))
            }
            let preferredHeight = try XCTUnwrap(reportedHeights.last, file: file, line: line)
            settledHeights.append(preferredHeight)
            let countAfterLayout = reportedHeights.count
            try await Task.sleep(for: .milliseconds(40))
            XCTAssertEqual(reportedHeights.count, countAfterLayout,
                           "Content sizing must settle after layout", file: file, line: line)
        }

        let expectedHeight = try XCTUnwrap(settledHeights.first)
        XCTAssertGreaterThan(expectedHeight, 650,
                             "The fixture must overflow the viewport to exercise scrolling",
                             file: file, line: line)
        for height in settledHeights.dropFirst() {
            XCTAssertEqual(height, expectedHeight, accuracy: 1,
                           "Preferred height must measure content independently of the viewport",
                           file: file, line: line)
        }
        XCTAssertLessThan(reportedHeights.count, 20,
                          "A viewport change must not produce repeated sizing feedback",
                          file: file, line: line)
    }
}

private actor SizingFixtureRepository: AnalyticsRepositoryProtocol {
    let snapshots: [PropertyDashboardSnapshot]

    init(snapshots: [PropertyDashboardSnapshot]) {
        self.snapshots = snapshots
    }

    func hasStoredAuthorization() async -> Bool { true }
    func connect() async throws -> [AnalyticsProperty] { snapshots.map(\.property) }
    func availableProperties() async throws -> [AnalyticsProperty] { snapshots.map(\.property) }
    func refreshSelectedProperties(
        _ properties: [AnalyticsProperty],
        trigger: RefreshTrigger,
        now: Date
    ) async throws -> CombinedDashboardSnapshot {
        let names = Set(properties.map(\.resourceName))
        return DashboardAggregator.aggregate(snapshots.filter { names.contains($0.property.resourceName) })
    }
    func cachedSnapshot(resourceNames: [String]?) async -> CombinedDashboardSnapshot? {
        DashboardAggregator.aggregate(snapshots)
    }
    func disconnect() async throws {}
}

@MainActor
private final class SizingLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus = .disabled
    func register() throws { status = .enabled }
    func unregister() async throws { status = .disabled }
}

@MainActor
private final class SizingDockApplier: DockActivationPolicyApplying {
    func apply(_ policy: NSApplication.ActivationPolicy) -> Bool { true }
}
