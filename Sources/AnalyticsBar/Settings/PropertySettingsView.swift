import SwiftUI

struct PropertySettingsView: View {
    @ObservedObject var model: DashboardModel
    let close: () -> Void
    @State private var selection: PropertySelection

    init(model: DashboardModel, close: @escaping () -> Void) {
        self.model = model
        self.close = close
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
            Text("No properties are available for this connection.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(accounts, id: \.resourceName) { account in
                    DisclosureGroup(account.name) {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(
                                model.availableProperties.filter { $0.accountResourceName == account.resourceName }
                            ) { property in
                                Button {
                                    selection.toggle(property.resourceName)
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: selection.isSelected(property.resourceName) ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(selection.isSelected(property.resourceName) ? .orange : .secondary)
                                        Text(property.displayName)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(property.currencyCode)
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 7)
                    }
                }

                HStack {
                    Text("\(selection.selectedResourceNames.count) selected")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") {
                        let names = selection.selectedResourceNames
                        close()
                        Task { await model.confirmSelection(names) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(selection.selectedResourceNames.isEmpty)
                }
            }
        }
    }
}
