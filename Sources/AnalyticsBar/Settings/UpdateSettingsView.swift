import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var checker: UpdateChecker
    @ObservedObject var installer: UpdateInstaller

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SettingsRowLabel(
                    icon: "chart.xyaxis.line",
                    title: "Analytics Bar",
                    subtitle: "Version \(AppConfiguration.marketingVersion)"
                )
                Spacer(minLength: 8)
                updateAction
            }
            .padding(.vertical, 3)

            SettingsRowDivider()

            Text("A lightweight, read-only Google Analytics dashboard for your menu bar.")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if case let .failed(message) = checker.state {
                SettingsErrorText(message: message)
            }
            if case let .failed(message) = installer.state {
                SettingsErrorText(message: message)
            }

            Link(
                "Privacy",
                destination: URL(string: "https://github.com/burakereno/analytics-bar/blob/main/docs/privacy.md")!
            )
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.orange)
            .padding(.top, 7)
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
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(.secondary)
        default:
            switch checker.state {
            case .checking:
                ProgressView().controlSize(.mini)
            case .upToDate:
                Label("Up to date", systemImage: "checkmark.circle")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            case let .available(release):
                Button("Install v\(release.version)") {
                    Task { try? await installer.install(release) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.orange, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            case .idle, .failed:
                Button("Check for Updates") {
                    Task { await checker.checkManually() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
