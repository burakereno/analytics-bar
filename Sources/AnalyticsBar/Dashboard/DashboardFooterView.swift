import AppKit
import SwiftUI

struct DashboardFooterView: View {
    let isRefreshing: Bool
    let canRefresh: Bool
    let refresh: () -> Void
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject var updateInstaller: UpdateInstaller

    var body: some View {
        HStack(spacing: 10) {
            Button(action: refresh) {
                HStack(spacing: 6) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 14, height: 14)
                    }

                    Text(isRefreshing ? "Refreshing" : "Refresh")
                }
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing || !canRefresh)
            .help("Refresh reports for the selected sites")
            .accessibilityLabel("Refresh")

            Spacer()

            updateStatus

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))
                }
                .buttonStyle(.plain)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
