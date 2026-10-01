import SwiftUI

struct ReportStatusSettingsView: View {
    @ObservedObject var model: DashboardModel
    let snapshot: CombinedDashboardSnapshot
    @State private var showsDetails = false

    private var healthy: Bool {
        model.connectionError == nil && snapshot.hasCurrentCore(at: model.presentationDate, maximumAge: model.maximumDataAge)
            && snapshot.hasCurrentRealtime(at: model.presentationDate, maximumAge: model.maximumDataAge)
    }

    private var coreSummary: DashboardPresentation.ReportSummary {
        DashboardPresentation.reportSummary(snapshot.properties.map(\.coreHealth), now: model.presentationDate, maximumAge: model.maximumDataAge)
    }

    private var realtimeSummary: DashboardPresentation.ReportSummary {
        DashboardPresentation.reportSummary(snapshot.properties.map(\.realtimeHealth), now: model.presentationDate, maximumAge: model.maximumDataAge)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            summary("Daily & weekly", status: coreSummary)
            summary("Last 30 minutes", status: realtimeSummary)
            if model.connectionError == nil && !healthy && !model.isRefreshing {
                Text(coreSummary.isCurrent ? "The realtime report is unavailable. Weekly figures are current." : "Open report details to see which reports need attention.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            DisclosureGroup("Report details", isExpanded: $showsDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(snapshot.properties) { property in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(property.property.displayName).font(.system(size: 11, weight: .semibold))
                            report("Daily & weekly", status: property.coreHealth)
                            report("Realtime", status: property.realtimeHealth)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .font(.system(size: 11))
        }
    }

    private func summary(_ label: String, status: DashboardPresentation.ReportSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(status.status).foregroundStyle(status.isCurrent ? Color.green : Color.orange)
            }
            .font(.system(size: 11, weight: .medium))
            if let date = status.oldestSuccess {
                Text("\(status.isCurrent ? "Fetched" : "Last success"): \(DashboardPresentation.age(date, relativeTo: model.presentationDate)) · \(DashboardPresentation.timestamp(date))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("Not all properties have a successful report yet.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func report(_ label: String, status: ReportStatus) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            let current = status.isCurrent(at: model.presentationDate, maximumAge: model.maximumDataAge)
            Text("\(label): \(current ? "OK" : "Unavailable")")
                .foregroundStyle(current ? Color.green : Color.orange)
            Text("Last success: \(DashboardPresentation.timestamp(status.lastSuccess))")
            if let attempt = status.lastAttempt {
                Text("Last attempt: \(DashboardPresentation.timestamp(attempt))")
            }
            if let message = status.message { Text(message).foregroundStyle(.orange) }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
