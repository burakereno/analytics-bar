import SwiftUI

struct DashboardStatusView: View {
    let snapshot: CombinedDashboardSnapshot
    let isRefreshing: Bool
    @State private var showsDetails = false

    private var staleNames: [String] {
        snapshot.properties.filter { $0.freshness == .stale }.map { $0.property.displayName }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                if isRefreshing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: staleNames.isEmpty ? "clock" : "exclamationmark.triangle")
                        .foregroundStyle(staleNames.isEmpty ? Color.secondary : Color.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if !staleNames.isEmpty {
                        Text("Cached: \(staleNames.joined(separator: ", "))")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            if !staleNames.isEmpty {
                DisclosureGroup("Refresh details", isExpanded: $showsDetails) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(snapshot.properties.filter { $0.refreshMessage != nil }) { property in
                            Text("\(property.property.displayName): \(property.refreshMessage ?? "Cached data")")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 5)
                }
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            }
        }
        .dashboardCard()
    }
}
