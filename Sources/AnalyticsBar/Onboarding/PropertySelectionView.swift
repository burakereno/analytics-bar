import SwiftUI

struct PropertySelectionView: View {
    let properties: [AnalyticsProperty]
    let initiallySelected: [String]
    let confirm: ([String]) -> Void

    @State private var selection: PropertySelection
    @State private var query = ""

    init(
        properties: [AnalyticsProperty],
        initiallySelected: [String],
        confirm: @escaping ([String]) -> Void
    ) {
        self.properties = properties
        self.initiallySelected = initiallySelected
        self.confirm = confirm
        _selection = State(
            initialValue: PropertySelection(
                properties: properties,
                selectedResourceNames: initiallySelected
            )
        )
    }

    private var filteredProperties: [AnalyticsProperty] {
        selection.filtered(query: query)
    }

    private var accounts: [(name: String, resourceName: String)] {
        var seen = Set<String>()
        return properties.compactMap { property in
            guard seen.insert(property.accountResourceName).inserted else { return nil }
            return (property.accountDisplayName, property.accountResourceName)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Choose properties")
                    .font(.system(size: 17, weight: .bold))
                Text("Selected properties appear together and refresh independently.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            TextField("Search properties or accounts", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            LazyVStack(spacing: 10) {
                ForEach(accounts, id: \.resourceName) { account in
                    accountSection(account)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            Divider().opacity(0.5)
            HStack {
                Text("\(selection.selectedResourceNames.count) selected")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { selection.clearAll() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Button("Show \(selection.selectedResourceNames.count) Properties") {
                    confirm(selection.selectedResourceNames)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(selection.selectedResourceNames.isEmpty)
            }
            .padding(12)
        }
    }

    private func accountSection(_ account: (name: String, resourceName: String)) -> some View {
        let rows = filteredProperties.filter { $0.accountResourceName == account.resourceName }
        return Group {
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.name)
                                .font(.system(size: 11, weight: .bold))
                            Text("\(rows.count) properties")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("All") { selection.selectAll(accountResourceName: account.resourceName) }
                            .buttonStyle(.plain)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    .padding(10)

                    Divider().opacity(0.35)

                    ForEach(rows) { property in
                        Button {
                            selection.toggle(property.resourceName)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: selection.isSelected(property.resourceName) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selection.isSelected(property.resourceName) ? .orange : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(property.displayName)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text("Property \(property.id) · \(property.timeZoneIdentifier) · \(property.currencyCode)")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                }
            }
        }
    }
}
