import SwiftUI

struct BreakdownCard: View {
    enum Breakdown: String, CaseIterable, Identifiable {
        case pages = "Top Pages"
        case sources = "Sources"
        var id: String { rawValue }
    }

    let snapshots: [PropertyDashboardSnapshot]
    @State private var propertyID: String
    @State private var breakdown: Breakdown = .pages

    init(snapshots: [PropertyDashboardSnapshot]) {
        self.snapshots = snapshots
        _propertyID = State(initialValue: snapshots.first?.id ?? "")
    }

    private var selected: PropertyDashboardSnapshot? {
        snapshots.first(where: { $0.id == propertyID }) ?? snapshots.first
    }

    private var rows: [RankedDimensionRow] {
        guard let selected else { return [] }
        return breakdown == .pages ? selected.topPages : selected.topSources
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Breakdown", selection: $breakdown) {
                ForEach(Breakdown.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(snapshots) { snapshot in
                        Button(snapshot.property.displayName) { propertyID = snapshot.id }
                            .buttonStyle(.plain)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(propertyID == snapshot.id ? .black : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(propertyID == snapshot.id ? Color.orange : Color.white.opacity(0.06), in: Capsule())
                    }
                }
            }

            if rows.isEmpty {
                Text("No ranking data today")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                ForEach(Array(rows.prefix(5).enumerated()), id: \.element.id) { index, row in
                    HStack {
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 14)
                        Text(row.label)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text(DashboardPresentation.compactDecimal(row.value))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .dashboardCard()
    }
}
