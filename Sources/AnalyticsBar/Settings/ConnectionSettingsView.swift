import SwiftUI

struct ConnectionSettingsView: View {
    @ObservedObject var model: DashboardModel
    let close: () -> Void
    @State private var confirmsDisconnect = false

    private var connectionLabel: String {
        switch model.state {
        case .disconnected: "Not connected"
        case .loading: "Connecting…"
        case .failed: "Needs attention"
        default: "Connected to Google Analytics"
        }
    }

    private var connectionColor: Color {
        switch model.state {
        case .disconnected: .secondary
        case .failed: .red
        default: .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SettingsRowLabel(
                    icon: "link.circle",
                    title: "Google Analytics",
                    subtitle: model.connectionIssue?.message ?? "Read-only GA4 access"
                )
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Circle().fill(connectionColor).frame(width: 6, height: 6)
                    Text(connectionLabel)
                        .lineLimit(1)
                }
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(connectionColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(connectionColor.opacity(0.10), in: Capsule())
            }
            .padding(.vertical, 3)

            SettingsRowDivider()

            HStack(spacing: 14) {
                Spacer()
                Button("Reconnect") {
                    close()
                    Task { await model.connect() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.orange)
                .disabled(model.isRefreshing)

                Button("Disconnect…", role: .destructive) {
                    confirmsDisconnect = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(model.state == .disconnected ? Color.secondary : Color.red)
                .disabled(model.state == .disconnected)
            }
            .padding(.vertical, 2)
        }
        .alert("Disconnect Google Analytics?", isPresented: $confirmsDisconnect) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                close()
                Task { await model.disconnect() }
            }
        } message: {
            Text("The OAuth token, cached Analytics snapshots, and selected properties will be removed from this Mac.")
        }
    }
}
