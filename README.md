# Analytics Bar

<p align="center">
  <img src="docs/icon.png" alt="Analytics Bar" width="340" height="340">
</p>

**A native macOS menu bar dashboard for Google Analytics 4.** Follow live and daily performance across multiple selected properties without keeping Analytics open in a browser.

<p align="center">
  <a href="https://github.com/burakereno/analytics-bar/releases/latest/download/AnalyticsBar.dmg">
    <img src="https://img.shields.io/badge/Download-AnalyticsBar.dmg-22c55e?style=for-the-badge&logo=apple&logoColor=white" alt="Download AnalyticsBar.dmg" height="48">
  </a>
  &nbsp;
  <a href="https://github.com/burakereno/analytics-bar/releases/latest">
    <img src="https://img.shields.io/github/v/release/burakereno/analytics-bar?style=for-the-badge&label=Latest&color=2563eb" alt="Latest release" height="48">
  </a>
</p>

<p align="center">
  <sub>macOS 14.0+ · Google Analytics read-only access · Developer ID signed and notarized</sub>
</p>

<p align="center">
  <img src="docs/screenshot-main.png" alt="Analytics Bar multi-property dashboard" width="390">
  <img src="docs/screenshot-settings.png" alt="Analytics Bar settings" width="390">
</p>

## Features

- **Multi-property dashboard** — monitor multiple GA4 properties at the same time
- **Live activity** — property-summed active users, views, events, and key events from the last 30 minutes
- **Today at a glance** — users, sessions, views, key events, honest currency-aware revenue, and same-hour comparison with yesterday
- **Seven-day trends** — switch between users, sessions, and views; hover any bar for its date and value
- **Property detail** — keep every selected property visible with its own live and daily metrics
- **Top pages and sources** — inspect rankings per property instead of merging unrelated domains
- **Configurable menu bar** — show live users, users today, sessions today, views today, or icon only
- **Native settings** — launch at login, Dock visibility, refresh cadence, revenue visibility, and automatic property selection changes
- **One-click in-app updates** — validates the release manifest, SHA-256, bundle identifier, Team ID, Developer ID signature, and Gatekeeper assessment
- **Read-only by design** — requests only the Google Analytics read-only scope and stores OAuth tokens in macOS Keychain

Combined user values are property sums. The same person may be counted by more than one property.

## Installation

### Download DMG

1. Go to the [latest release](../../releases/latest)
2. Download **`AnalyticsBar.dmg`**
3. Open the DMG and drag **Analytics Bar.app** to **Applications**
4. Launch Analytics Bar; it appears in the macOS menu bar

The release workflow signs the app and DMG with Developer ID, notarizes both with Apple, staples the notarization tickets, and publishes a matching update manifest.

## Build from Source

### Requirements

- macOS 14.0+
- Xcode 16.0+
- A Google Cloud project with **Google Analytics Admin API** and **Google Analytics Data API** enabled
- A Google OAuth 2.0 **Desktop app** client with access to your Google Analytics account

### Steps

```bash
git clone https://github.com/burakereno/analytics-bar.git
cd analytics-bar

./script/configure_oauth.sh
./scripts/build-app.sh
open ".build/Analytics Bar.app"
```

`configure_oauth.sh` stores the client configuration in the ignored, permission-restricted `.env.local` file. OAuth access and refresh tokens are stored separately in macOS Keychain.

## Privacy

Analytics Bar talks directly to Google Analytics and GitHub Releases. It does not use an app-owned server and does not upload Analytics data, OAuth tokens, or signing credentials. See [Privacy & Data Handling](docs/privacy.md) for details.

## Tech Stack

- **SwiftUI** — dashboard, settings, charts, and onboarding
- **AppKit** — menu bar status item, popover lifecycle, and dynamic sizing
- **Swift Package Manager** — build and test system
- **Google Analytics Admin & Data APIs** — property discovery, realtime, and daily reports
- **Security / Keychain** — local OAuth token storage
- **GitHub Actions** — Developer ID signing, Apple notarization, DMG packaging, and update manifests
