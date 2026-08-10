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
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Circle().fill(connectionColor).frame(width: 7, height: 7)
                Text(connectionLabel)
                Spacer()
            }

            if let issue = model.connectionIssue {
                Text(issue.message)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Reconnect") {
                    close()
                    Task { await model.connect() }
                }
                .disabled(model.isRefreshing)

                Button("Disconnect…", role: .destructive) {
                    confirmsDisconnect = true
                }
                .disabled(model.state == .disconnected)
            }
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
