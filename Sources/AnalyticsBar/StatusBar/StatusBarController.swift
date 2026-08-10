import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentSize = NSSize(width: PopoverLayout.width, height: PopoverLayout.initialHeight)
        popover.contentViewController = NSHostingController(rootView: BootstrapView())

        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "chart.xyaxis.line", accessibilityDescription: AppConfiguration.appName)
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }

        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

private struct BootstrapView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.orange)

            Text(AppConfiguration.appName)
                .font(.system(size: 18, weight: .bold))

            Text("Connect Google Analytics to begin.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .frame(width: PopoverLayout.width, height: PopoverLayout.initialHeight)
        .preferredColorScheme(.dark)
    }
}
