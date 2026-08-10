# Agent Instructions

Analytics Bar is a native macOS 14+ menu bar app built with Swift Package Manager, AppKit, and SwiftUI.

## Required verification loop

After every implementation change:

```sh
pkill -x AnalyticsBar || true
swift test
swift build
```

For runtime UI changes, also run `./script/build_and_run.sh --verify` and inspect the menu bar popover.

## Product constraints

- The app intentionally runs as an accessory with no Dock icon by default.
- Google access is read-only and credentials stay in Keychain.
- Combined users across properties are property sums, not cross-property unique users.
- Never commit OAuth credentials, certificates, DMGs, or update manifests.
