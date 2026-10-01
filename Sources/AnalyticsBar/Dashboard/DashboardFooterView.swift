import AppKit
import SwiftUI

struct DashboardFooterView: View {
    let isRefreshing: Bool
    let refresh: () -> Void
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject var updateInstaller: UpdateInstaller

    var body: some View {
        HStack(spacing: 10) {
            Button(action: refresh) {
                if isRefreshing {
                    ProgressView().controlSize(.mini)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)

            Spacer()

            updateStatus

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateInstaller.state {
        case .downloadingManifest, .downloadingDMG, .verifying, .installing, .relaunching:
            ProgressView().controlSize(.mini)
        default:
            switch updateChecker.state {
            case .checking:
                ProgressView().controlSize(.mini)
            case .upToDate:
                Button("v\(AppConfiguration.marketingVersion) · Up to date") {
                    Task { await updateChecker.checkManually() }
                }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Check for Updates")
            case let .available(release):
                Button("Update v\(release.version)") {
                    Task { try? await updateInstaller.install(release) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
            case .idle, .failed:
                Button("v\(AppConfiguration.marketingVersion)") {
                    Task { await updateChecker.checkManually() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Check for Updates")
            }
        }
    }
}
