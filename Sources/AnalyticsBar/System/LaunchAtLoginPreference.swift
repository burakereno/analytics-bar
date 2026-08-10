import Combine
import ServiceManagement

enum LaunchAtLoginStatus: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() async throws
}

@MainActor
final class MainAppLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() async throws {
        try await SMAppService.mainApp.unregister()
    }
}

@MainActor
final class LaunchAtLoginPreference: ObservableObject {
    @Published private(set) var status: LaunchAtLoginStatus
    @Published private(set) var lastError: String?

    private let service: any LaunchAtLoginServicing

    init(service: (any LaunchAtLoginServicing)? = nil) {
        let resolvedService = service ?? MainAppLaunchAtLoginService()
        self.service = resolvedService
        status = resolvedService.status
    }

    func setEnabled(_ enabled: Bool) async {
        do {
            if enabled {
                try service.register()
            } else {
                try await service.unregister()
            }
            status = service.status
            lastError = nil
        } catch {
            status = service.status
            lastError = error.localizedDescription
        }
    }
}
