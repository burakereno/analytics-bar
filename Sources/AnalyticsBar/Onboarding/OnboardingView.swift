import SwiftUI

struct OnboardingView: View {
    let isConnecting: Bool
    let issue: DashboardModel.ConnectionIssue?
    let connect: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.orange.opacity(0.12))
                    .frame(width: 68, height: 68)
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 31, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 7) {
                Text("Your Analytics, at a glance")
                    .font(.system(size: 17, weight: .bold))
                Text("Connect your Google account to see live and daily metrics across multiple GA4 properties.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 290)
            }

            if let issue {
                Label(issue.message, systemImage: issue.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(issue.color)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .frame(maxWidth: 310)
                    .background(issue.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            Button(action: connect) {
                HStack(spacing: 8) {
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                    }
                    Text(isConnecting ? "Connecting…" : "Connect Google Analytics")
                }
                .frame(maxWidth: 255)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)
            .disabled(isConnecting)

            Text("OAuth tokens stay in your Mac’s Keychain. Analytics data is read-only.")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 8)
        }
        .padding(20)
    }
}

private extension DashboardModel.ConnectionIssue {
    var icon: String {
        switch self {
        case .cancelled: "xmark.circle"
        case .configuration: "wrench.and.screwdriver.fill"
        case .permission: "lock.trianglebadge.exclamationmark.fill"
        case .other: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .cancelled: .secondary
        case .configuration: .orange
        case .permission, .other: .red
        }
    }
}
