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
                    canRefresh: !model.isChoosingProperties
                        && !model.isDisconnecting
                        && !preferences.selectedPropertyResourceNames.isEmpty,
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
            LiveSummaryCard(snapshot: snapshot, now: model.presentationDate, maximumAge: model.maximumDataAge)
            WeeklySummaryCard(snapshot: snapshot, now: model.presentationDate, maximumAge: model.maximumDataAge)

            if !model.isRefreshing,
               model.connectionError != nil || model.needsReconnection
               || !snapshot.hasCurrentCore(at: model.presentationDate, maximumAge: model.maximumDataAge)
               || !snapshot.hasCurrentRealtime(at: model.presentationDate, maximumAge: model.maximumDataAge) {
                Button {
                    withAnimation(transitionAnimation) { showingSettings = true }
                } label: {
                    HStack(spacing: 6) {
                        Label(model.needsReconnection ? "Reconnect to Google" : "Reports need attention",
                              systemImage: "exclamationmark.triangle")
                        Spacer()
                        Text("Settings")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reports need attention. Open connection settings")
            }

            ForEach(snapshot.properties) { property in
                PropertySummaryCard(snapshot: property, now: model.presentationDate, maximumAge: model.maximumDataAge)
            }

            SevenDayTrendCard(snapshot: snapshot, now: model.presentationDate, maximumAge: model.maximumDataAge)
            TodayMetricsCard(snapshot: snapshot, showsRevenue: preferences.showsRevenue,
                             now: model.presentationDate, maximumAge: model.maximumDataAge)
            BreakdownCard(snapshots: snapshot.properties, now: model.presentationDate, maximumAge: model.maximumDataAge)
            DashboardFooterView(
                isRefreshing: model.isRefreshing,
                refresh: { Task { await model.refresh(trigger: .manual) } },
                updateChecker: updateChecker, updateInstaller: updateInstaller
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
