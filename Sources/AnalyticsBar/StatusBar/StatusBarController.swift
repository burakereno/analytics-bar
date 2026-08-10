import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model: DashboardModel
    private let preferences: AppPreferences
    private var cancellables = Set<AnyCancellable>()

    init(
        model: DashboardModel,
        preferences: AppPreferences,
        systemSettings: SystemSettingsController,
        updateChecker: UpdateChecker,
        updateInstaller: UpdateInstaller
    ) {
        self.model = model
        self.preferences = preferences
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 800
        popover.contentSize = NSSize(
            width: PopoverLayout.width,
            height: PopoverLayout.clampedHeight(PopoverLayout.preferredHeight, visibleScreenHeight: visibleHeight)
        )
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(
                model: model,
                systemSettings: systemSettings,
                updateChecker: updateChecker,
                updateInstaller: updateInstaller
            )
        )

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])

        model.$snapshot
            .combineLatest(preferences.$menuBarMetric)
            .map { snapshot, metric in
                MenuBarRenderer.title(snapshot: snapshot, metric: metric)
            }
            .removeDuplicates()
            .sink { [weak self] title in
                self?.updateStatusItem(title: title)
            }
            .store(in: &cancellables)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }

        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidShow(_ notification: Notification) {
        model.popoverDidOpen()
    }

    func popoverDidClose(_ notification: Notification) {
        model.popoverDidClose()
    }

    private func updateStatusItem(title: MenuBarTitle) {
        statusItem.length = MenuBarRenderer.contentWidth(for: title)
        statusItem.button?.image = MenuBarRenderer.image(for: title)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = title.accessibilityLabel
    }
}
