import SwiftUI

struct ConnectionSettingsView: View {
    @ObservedObject var model: DashboardModel
    let close: () -> Void
    @State private var confirmsDisconnect = false

    private var connectionLabel: String {
        if model.isDisconnecting { return "Disconnecting…" }
        if model.isRefreshing { return "Checking…" }
        if model.needsReconnection { return "Reconnect required" }
        if model.connectionError != nil { return "Needs attention" }
        if let snapshot = model.snapshot,
           (!snapshot.hasCurrentCore(at: model.presentationDate, maximumAge: model.maximumDataAge)
            || !snapshot.hasCurrentRealtime(at: model.presentationDate, maximumAge: model.maximumDataAge)) {
            return "Reports need attention"
        }
        switch model.state {
        case .disconnected: return "Not connected"
        case .loading: return "Connecting…"
        case .failed: return "Needs attention"
        default: return "Connected"
        }
    }

    private var connectionColor: Color {
        connectionLabel == "Connected" ? .green : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SettingsRowLabel(
                    icon: "link.circle",
                    title: "Google Analytics",
                    subtitle: "Read-only GA4 access"
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
                Button("Reload accounts & sites") { Task { await model.checkConnection() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .disabled(model.isRefreshing || model.isDisconnecting || model.isChoosingProperties)
                    .help("Reload your Google accounts, site list and Analytics reports")
                Spacer()
                Button("Reconnect") {
                    close()
                    Task { await model.connect() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.orange)
                .disabled(model.isRefreshing || model.isDisconnecting)

                Button("Disconnect…", role: .destructive) {
                    confirmsDisconnect = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(model.state == .disconnected ? Color.secondary : Color.red)
                .disabled(model.state == .disconnected || model.isRefreshing || model.isDisconnecting)
            }
            .padding(.vertical, 2)

            if let error = model.connectionError ?? model.connectionIssue?.message {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
            if let snapshot = model.snapshot {
                SettingsRowDivider()
                ReportStatusSettingsView(model: model, snapshot: snapshot)
            }
        }
        .alert("Disconnect Google Analytics?", isPresented: $confirmsDisconnect) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                Task { await model.disconnect() }
            }
        } message: {
            Text("The OAuth token, cached Analytics snapshots, and selected properties will be removed from this Mac.")
        }
    }
}
