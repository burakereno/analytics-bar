import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var checker: UpdateChecker
    @ObservedObject var installer: UpdateInstaller

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Analytics Bar v\(AppConfiguration.marketingVersion)")
                Spacer()
                updateAction
            }

            if case let .failed(message) = checker.state {
                Text(message)
                    .font(.system(size: 8))
                    .foregroundStyle(.red)
            }
            if case let .failed(message) = installer.state {
                Text(message)
                    .font(.system(size: 8))
                    .foregroundStyle(.red)
            }

            Link(
                "Privacy",
                destination: URL(string: "https://github.com/burakereno/analytics-bar/blob/main/docs/privacy.md")!
            )
            .font(.system(size: 9, weight: .semibold))
        }
    }

    @ViewBuilder
    private var updateAction: some View {
        switch installer.state {
        case .downloadingManifest, .downloadingDMG, .verifying, .installing, .relaunching:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(installer.state.label)
            }
            .foregroundStyle(.secondary)
        default:
            switch checker.state {
            case .checking:
                ProgressView().controlSize(.mini)
            case .upToDate:
                Label("Up to date", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case let .available(release):
                Button("Install v\(release.version)") {
                    Task { try? await installer.install(release) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            case .idle, .failed:
                Button("Check for Updates") {
                    Task { await checker.checkManually() }
                }
            }
        }
    }
}

private extension UpdateInstaller.State {
    var label: String {
        switch self {
        case .downloadingManifest: "Checking manifest…"
        case .downloadingDMG: "Downloading…"
        case .verifying: "Verifying…"
        case .installing: "Installing…"
        case .relaunching: "Relaunching…"
        case .idle, .failed: ""
        }
    }
}
