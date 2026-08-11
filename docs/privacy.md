# Privacy & Data Handling

Analytics Bar is a personal-use macOS menu bar client for Google Analytics 4.

## Google access

- The app requests only `https://www.googleapis.com/auth/analytics.readonly`.
- It reads account/property metadata and Analytics reports directly from Google APIs.
- It cannot edit Analytics configuration or data.

## Local storage

- OAuth access and refresh tokens are stored in macOS Keychain.
- Selected properties and display preferences are stored in `UserDefaults`.
- A local dashboard cache may contain report totals and rankings so one failed refresh does not erase previously loaded data.
- OAuth tokens and client secrets are not written to the dashboard cache.

## Network destinations

- Google OAuth and Google Analytics APIs for authentication and reports.
- GitHub Releases for update checks and signed DMG downloads.
- No app-owned analytics, telemetry, advertising, or proxy server is used.

## Multi-property totals

Combined user metrics are sums of each selected property. They are not cross-property unique-user counts, so the same person may appear in more than one property total.

## Release security

Production releases are Developer ID signed and Apple-notarized. In-app updates require the expected bundle identifier and Apple Team ID, a valid Developer ID signature, Gatekeeper approval, and a release-manifest SHA-256 match before installation.
