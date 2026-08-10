import Foundation

actor DashboardCache {
    private struct Envelope: Codable, Sendable {
        let schemaVersion: Int
        let snapshots: [PropertyDashboardSnapshot]
    }

    private let directoryURL: URL
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let base = directoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("AnalyticsBar", isDirectory: true)
        self.directoryURL = base
        fileURL = base.appendingPathComponent("dashboard-cache-v1.json")
    }

    func load() throws -> [String: PropertyDashboardSnapshot] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: fileURL)
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.schemaVersion == 1 else {
                try? fileManager.removeItem(at: fileURL)
                return [:]
            }
            return Dictionary(
                envelope.snapshots.map { ($0.property.resourceName, $0) },
                uniquingKeysWith: { _, newest in newest }
            )
        } catch {
            try? fileManager.removeItem(at: fileURL)
            return [:]
        }
    }

    func save(_ snapshots: [PropertyDashboardSnapshot]) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let envelope = Envelope(schemaVersion: 1, snapshots: snapshots)
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: fileURL, options: [.atomic])
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}
