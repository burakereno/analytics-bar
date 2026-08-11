import SwiftUI

struct PropertySettingsView: View {
    private static let maximumVisiblePropertyRows = 6
    private static let propertyRowHeight: CGFloat = 34

    @ObservedObject var model: DashboardModel
    @State private var selection: PropertySelection
    @State private var expandedAccount: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: DashboardModel) {
        self.model = model
        _selection = State(
            initialValue: PropertySelection(
                properties: model.availableProperties,
                selectedResourceNames: model.preferences.selectedPropertyResourceNames
            )
        )
    }

    private var accounts: [(name: String, resourceName: String)] {
        var seen = Set<String>()
        return model.availableProperties.compactMap { property in
            guard seen.insert(property.accountResourceName).inserted else { return nil }
            return (property.accountDisplayName, property.accountResourceName)
        }
    }

    var body: some View {
        if model.availableProperties.isEmpty {
            SettingsRowLabel(
                icon: "chart.bar.xaxis",
                title: "No Properties",
                subtitle: "No GA4 properties are available for this connection"
            )
            .padding(.vertical, 3)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(accounts, id: \.resourceName) { account in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            toggleAccount(account.resourceName)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                                .rotationEffect(
                                    .degrees(expandedAccount == account.resourceName ? 90 : 0)
                                )
                                .animation(
                                    reduceMotion ? nil : .easeOut(duration: 0.16),
                                    value: expandedAccount
                                )
                                Image(systemName: "building.2")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                Text(account.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(accountSelectionSummary(account.resourceName))
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(account.name)
                        .accessibilityValue(accountSelectionSummary(account.resourceName))
                        .accessibilityHint(
                            expandedAccount == account.resourceName
                                ? "Collapse account properties"
                                : "Expand account properties"
                        )

                        if expandedAccount == account.resourceName {
                            let properties = properties(for: account.resourceName)
                            VStack(alignment: .leading, spacing: 0) {
                                if properties.count > 3 {
                                    bulkSelectionRow(
                                        accountResourceName: account.resourceName,
                                        properties: properties
                                    )
                                }

                                propertyList(properties)
                            }
                            .padding(.top, 1)
                        }
                    }
                    .clipped()
                }

                SettingsRowDivider()

                HStack {
                    Label(
                        "\(selection.selectedResourceNames.count) selected",
                        systemImage: "checkmark.circle.fill"
                    )
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Auto-save on")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
            .onAppear(perform: synchronizeSelection)
            .onChange(of: model.availableProperties.map(\.resourceName)) { _, _ in
                synchronizeSelection()
            }
            .onChange(of: model.preferences.selectedPropertyResourceNames) { _, _ in
                synchronizeSelection()
            }
        }
    }

    private func propertyBinding(_ resourceName: String) -> Binding<Bool> {
        Binding(
            get: { selection.isSelected(resourceName) },
            set: { isSelected in
                guard isSelected != selection.isSelected(resourceName) else { return }
                guard isSelected || selection.selectedResourceNames.count > 1 else { return }
                selection.toggle(resourceName)
                model.updateSelection(selection.selectedResourceNames)
            }
        )
    }

    private func toggleAccount(_ accountResourceName: String) {
        expandedAccount = expandedAccount == accountResourceName ? nil : accountResourceName
    }

    @ViewBuilder
    private func propertyList(_ properties: [AnalyticsProperty]) -> some View {
        if properties.count > Self.maximumVisiblePropertyRows {
            ScrollView {
                propertyRows(properties)
            }
            .frame(
                height: CGFloat(Self.maximumVisiblePropertyRows) * Self.propertyRowHeight
            )
            .scrollIndicators(.visible)
        } else {
            propertyRows(properties)
        }
    }

    private func propertyRows(_ properties: [AnalyticsProperty]) -> some View {
        ForEach(properties) { property in
            HStack(spacing: 9) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(property.displayName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                    Text(property.currencyCode)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: propertyBinding(property.resourceName))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.orange)
                    .accentColor(.orange)
                    .accessibilityLabel(property.displayName)
                    .accessibilityHint(
                        isOnlySelectedProperty(property.resourceName)
                            ? "At least one property must remain selected"
                            : "Changes save automatically"
                    )
                    .disabled(isOnlySelectedProperty(property.resourceName))
            }
            .frame(minHeight: Self.propertyRowHeight)
            .padding(.leading, 30)
        }
    }

    private func bulkSelectionRow(
        accountResourceName: String,
        properties: [AnalyticsProperty]
    ) -> some View {
        let allSelected = properties.allSatisfy { selection.isSelected($0.resourceName) }
        let canClear = selection.selectedResourceNames.count > properties.count

        return HStack {
            Text("\(properties.count) properties")
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
            Button(allSelected ? "None" : "All") {
                if allSelected {
                    selection.deselectAll(accountResourceName: accountResourceName)
                } else {
                    selection.selectAll(accountResourceName: accountResourceName)
                }
                model.updateSelection(selection.selectedResourceNames)
            }
            .buttonStyle(.plain)
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(.orange)
            .disabled(allSelected && !canClear)
            .accessibilityLabel(allSelected ? "Deselect account properties" : "Select all account properties")
        }
        .padding(.leading, 62)
        .padding(.vertical, 4)
    }

    private func isOnlySelectedProperty(_ resourceName: String) -> Bool {
        selection.isSelected(resourceName) && selection.selectedResourceNames.count == 1
    }

    private func accountSelectionSummary(_ accountResourceName: String) -> String {
        let properties = properties(for: accountResourceName)
        let selected = properties.filter { selection.isSelected($0.resourceName) }.count
        return "\(selected)/\(properties.count)"
    }

    private func properties(for accountResourceName: String) -> [AnalyticsProperty] {
        model.availableProperties.filter { $0.accountResourceName == accountResourceName }
    }

    private func synchronizeSelection() {
        selection = PropertySelection(
            properties: model.availableProperties,
            selectedResourceNames: model.preferences.selectedPropertyResourceNames
        )
    }
}
