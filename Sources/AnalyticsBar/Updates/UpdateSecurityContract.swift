import Foundation

enum UpdateSecurityContract {
    static let requiredHelperFragments = [
        "CFBundleIdentifier",
        "CFBundleShortVersionString",
        "codesign --verify",
        "TeamIdentifier",
        "certificate leaf[subject.OU]",
        "spctl --assess",
        "hdiutil attach -readonly",
        "STAGED_APP",
        "BACKUP_APP",
        "restore_backup",
        "pgrep"
    ]

    static func validateHelper(at url: URL) throws {
        let source = try String(contentsOf: url, encoding: .utf8)
        let missing = requiredHelperFragments.filter { !source.contains($0) }
        guard missing.isEmpty else {
            throw UpdateError.invalidInstaller(
                "The update helper is missing required trust checks: \(missing.joined(separator: ", "))."
            )
        }
    }
}
