import AppKit
import Combine

@MainActor
protocol DockActivationPolicyApplying: AnyObject {
    func apply(_ policy: NSApplication.ActivationPolicy) -> Bool
}

@MainActor
final class AppKitDockActivationPolicyApplier: DockActivationPolicyApplying {
    func apply(_ policy: NSApplication.ActivationPolicy) -> Bool {
        NSApplication.shared.setActivationPolicy(policy)
    }
}

@MainActor
final class DockIconController: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var lastError: String?

    private let applier: any DockActivationPolicyApplying

    init(applier: (any DockActivationPolicyApplying)? = nil) {
        self.applier = applier ?? AppKitDockActivationPolicyApplier()
    }

    @discardableResult
    func setVisible(_ visible: Bool) -> Bool {
        let succeeded = applier.apply(visible ? .regular : .accessory)
        if succeeded {
            isVisible = visible
            lastError = nil
        } else {
            lastError = "macOS did not accept the Dock icon setting."
        }
        return succeeded
    }
}
