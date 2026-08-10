import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject private var preferences: AppPreferences
    @ObservedObject private var systemSettings: SystemSettingsController
    @ObservedObject private var updateChecker: UpdateChecker
    @ObservedObject private var updateInstaller: UpdateInstaller
    @State private var showingSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        model: DashboardModel,
        systemSettings: SystemSettingsController,
        updateChecker: UpdateChecker,
        updateInstaller: UpdateInstaller
    ) {
        self.model = model
        preferences = model.preferences
        self.systemSettings = systemSettings
        self.updateChecker = updateChecker
        self.updateInstaller = updateInstaller
    }

    private var propertyCount: Int {
        model.snapshot?.properties.count ?? preferences.selectedPropertyResourceNames.count
    }

    var body: some View {
        VStack(spacing: 0) {
            DashboardHeaderView(
                propertyCount: propertyCount,
                showingSettings: showingSettings,
                toggleSettings: { withAnimation(transitionAnimation) { showingSettings.toggle() } }
            )

            Divider().opacity(0.45)

            Group {
                if showingSettings {
                    SettingsView(
                        model: model,
                        preferences: preferences,
                        systemSettings: systemSettings,
                        updateChecker: updateChecker,
                        updateInstaller: updateInstaller,
                        close: { withAnimation(transitionAnimation) { showingSettings = false } }
                    )
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    content
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: PopoverLayout.width)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    private var transitionAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.24)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .disconnected:
            OnboardingView(
                isConnecting: model.isRefreshing,
                issue: model.connectionIssue,
                connect: { Task { await model.connect() } }
            )

        case let .selectingProperties(properties):
            PropertySelectionView(
                properties: properties,
                initiallySelected: preferences.selectedPropertyResourceNames,
                confirm: { names in Task { await model.confirmSelection(names) } }
            )

        case .loading:
            loadingView

        case .loaded:
            if let snapshot = model.snapshot {
                loadedDashboard(snapshot)
            } else {
                loadingView
            }

        case .noProperties:
            messageView(
                icon: "rectangle.stack.badge.questionmark",
                title: "No GA4 properties found",
                detail: "This Google account does not currently have access to a Google Analytics 4 property."
            )

        case let .failed(message):
            OnboardingView(
                isConnecting: model.isRefreshing,
                issue: model.connectionIssue ?? .other(message),
                connect: { Task { await model.connect() } }
            )
        }
    }

    private func loadedDashboard(_ snapshot: CombinedDashboardSnapshot) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let error = model.lastManualError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                HStack {
                    Text("ALL PROPERTIES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                LiveSummaryCard(snapshot: snapshot)

                ForEach(snapshot.properties) { property in
                    PropertySummaryCard(snapshot: property)
                }

                TodayMetricsCard(snapshot: snapshot, showsRevenue: preferences.showsRevenue)
                SevenDayTrendCard(snapshot: snapshot)
                BreakdownCard(snapshots: snapshot.properties)
                DashboardStatusView(snapshot: snapshot, isRefreshing: model.isRefreshing)
                DashboardFooterView(
                    isRefreshing: model.isRefreshing,
                    refresh: { Task { await model.refresh(trigger: .manual) } },
                    updateChecker: updateChecker,
                    updateInstaller: updateInstaller
                )
            }
            .padding(12)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text("Loading Analytics…")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageView(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text(title).font(.system(size: 15, weight: .bold))
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
