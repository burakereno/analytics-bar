import SwiftUI

struct DashboardHeaderView: View {
    let propertyCount: Int
    let showingSettings: Bool
    let toggleSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.orange)
            Text("Analytics Bar")
                .font(.system(size: 14, weight: .bold))
            if propertyCount > 0 {
                Text("\(propertyCount) Properties")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.12), in: Capsule())
            }
            Spacer()
            Button(action: toggleSettings) {
                Image(systemName: showingSettings ? "xmark.circle.fill" : "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(showingSettings ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(showingSettings ? "Close Settings" : "Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
