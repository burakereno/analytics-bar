import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject private var preferences: AppPreferences
    @ObservedObject private var systemSettings: SystemSettingsController
    @ObservedObject private var updateChecker: UpdateChecker
    @ObservedObject private var updateInstaller: UpdateInstaller
    let onPreferredHeightChange: (CGFloat) -> Void
    @State private var showingSettings = false
    @State private var headerHeight: CGFloat = 0
    @State private var dashboardContentHeight: CGFloat = 0
    @State private var settingsContentHeight: CGFloat = 0
    @State private var settingsFooterHeight: CGFloat = 0
    @State private var lastReportedHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        model: DashboardModel,
        systemSettings: SystemSettingsController,
        updateChecker: UpdateChecker,
        updateInstaller: UpdateInstaller,
        startsInSettings: Bool = false,
        onPreferredHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.model = model
        preferences = model.preferences
        self.systemSettings = systemSettings
        self.updateChecker = updateChecker
        self.updateInstaller = updateInstaller
        self.onPreferredHeightChange = onPreferredHeightChange
        _showingSettings = State(initialValue: startsInSettings)
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
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                headerHeight = height
                reportPreferredHeight()
            }

            Divider().opacity(0.45)

            ZStack {
                if showingSettings {
                    ScrollView {
                        SettingsView(
                            model: model,
                            preferences: preferences,
                            systemSettings: systemSettings,
                            updateChecker: updateChecker,
                            updateInstaller: updateInstaller,
                            close: { withAnimation(transitionAnimation) { showingSettings = false } }
                        )
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            settingsContentHeight = height
                            reportPreferredHeight()
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    ScrollView {
                        content
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.height
                            } action: { height in
                                dashboardContentHeight = height
                                reportPreferredHeight()
                            }
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if showingSettings {
                Divider().opacity(0.45)
                SettingsFooterView(
                    isRefreshing: model.isRefreshing,
                    refresh: { Task { await model.refresh(trigger: .manual) } }
                )
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    settingsFooterHeight = height
                    reportPreferredHeight()
                }
            }
        }
        .frame(width: PopoverLayout.width)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .onChange(of: showingSettings) { _, _ in reportPreferredHeight() }
    }

    private var transitionAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.24)
    }

    private func reportPreferredHeight() {
        let bodyHeight = showingSettings
            ? settingsContentHeight + settingsFooterHeight
            : dashboardContentHeight
        guard headerHeight > 0, bodyHeight > 0 else { return }
        let preferredHeight = PopoverLayout.preferredHeight(
            header: headerHeight,
            body: bodyHeight,
            dividerCount: showingSettings ? 2 : 1
        )
        guard abs(lastReportedHeight - preferredHeight) > 0.5 else { return }
        lastReportedHeight = preferredHeight
        onPreferredHeightChange(preferredHeight)
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

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text("Loading Analytics…")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
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
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(20)
    }
}
