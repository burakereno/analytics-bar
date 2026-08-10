import Foundation

@MainActor
final class RefreshScheduler {
    typealias Tick = @MainActor @Sendable (RefreshTrigger) async -> Void

    private var task: Task<Void, Never>?
    private var tick: Tick?
    private var isPopoverOpen = false
    private var backgroundInterval: BackgroundRefreshInterval = .fiveMinutes

    nonisolated static func nextInterval(
        isPopoverOpen: Bool,
        background: BackgroundRefreshInterval
    ) -> TimeInterval {
        isPopoverOpen ? 60 : TimeInterval(background.rawValue)
    }

    func configure(tick: @escaping Tick) {
        self.tick = tick
    }

    func start() {
        reschedule()
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func setPopoverOpen(_ isOpen: Bool) {
        guard isPopoverOpen != isOpen else { return }
        isPopoverOpen = isOpen
        reschedule()
    }

    func updateBackgroundInterval(_ interval: BackgroundRefreshInterval) {
        guard backgroundInterval != interval else { return }
        backgroundInterval = interval
        if !isPopoverOpen { reschedule() }
    }

    private func reschedule() {
        task?.cancel()
        guard tick != nil else { return }

        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let seconds = Self.nextInterval(
                    isPopoverOpen: self.isPopoverOpen,
                    background: self.backgroundInterval
                )
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    return
                }
                guard !Task.isCancelled, let tick = self.tick else { return }
                await tick(self.isPopoverOpen ? .popoverTimer : .backgroundTimer)
            }
        }
    }
}
