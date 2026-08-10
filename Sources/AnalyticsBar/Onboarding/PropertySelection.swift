import Foundation

struct PropertySelection: Equatable, Sendable {
    let properties: [AnalyticsProperty]
    private(set) var selectedResourceNames: [String]

    init(properties: [AnalyticsProperty], selectedResourceNames: [String]) {
        self.properties = properties
        let validNames = Set(properties.map(\.resourceName))
        self.selectedResourceNames = properties
            .map(\.resourceName)
            .filter { validNames.contains($0) && selectedResourceNames.contains($0) }
    }

    mutating func toggle(_ resourceName: String) {
        guard properties.contains(where: { $0.resourceName == resourceName }) else { return }
        if selectedResourceNames.contains(resourceName) {
            selectedResourceNames.removeAll { $0 == resourceName }
        } else {
            selectedResourceNames.append(resourceName)
            normalizeOrder()
        }
    }

    mutating func selectAll(accountResourceName: String) {
        let names = properties
            .filter { $0.accountResourceName == accountResourceName }
            .map(\.resourceName)
        selectedResourceNames.append(contentsOf: names.filter { !selectedResourceNames.contains($0) })
        normalizeOrder()
    }

    mutating func deselectAll(accountResourceName: String) {
        let names = Set(
            properties
                .filter { $0.accountResourceName == accountResourceName }
                .map(\.resourceName)
        )
        selectedResourceNames.removeAll { names.contains($0) }
    }

    mutating func clearAll() {
        selectedResourceNames = []
    }

    func isSelected(_ resourceName: String) -> Bool {
        selectedResourceNames.contains(resourceName)
    }

    func filtered(query: String) -> [AnalyticsProperty] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return properties }
        return properties.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.accountDisplayName.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private mutating func normalizeOrder() {
        let selected = Set(selectedResourceNames)
        selectedResourceNames = properties.map(\.resourceName).filter(selected.contains)
    }
}
