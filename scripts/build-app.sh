#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTABLE_NAME="AnalyticsBar"
DISPLAY_NAME="Analytics Bar"
APP_DIR="$ROOT_DIR/.build/$DISPLAY_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
APP_ICON="$ROOT_DIR/Sources/AnalyticsBar/Resources/AppIcon.icns"
UPDATE_HELPER="$ROOT_DIR/scripts/install-update.sh"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-14.0}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.burakerenoglu.AnalyticsBar}"

cd "$ROOT_DIR"

if [[ -f "$ROOT_DIR/.env.local" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env.local"
  set +a
fi

REMOTE_LATEST_TAG="$(
  { git ls-remote --tags --refs origin 'v*' 2>/dev/null || true; } \
    | awk '{ sub("refs/tags/", "", $2); print $2 }' \
    | sort -Vr \
    | head -1
)"
LOCAL_LATEST_TAG="$(git tag -l 'v*' --sort=-v:refname | head -1)"
LATEST_TAG="${REMOTE_LATEST_TAG:-$LOCAL_LATEST_TAG}"
DEFAULT_APP_VERSION="${LATEST_TAG#v}"
if [[ -z "$LATEST_TAG" || "$DEFAULT_APP_VERSION" == "$LATEST_TAG" ]]; then
  DEFAULT_APP_VERSION="0.1.0"
fi

APP_VERSION="${APP_VERSION:-$DEFAULT_APP_VERSION}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-1}"

if [[ -n "${GOOGLE_OAUTH_CLIENT_ID:-}" || -n "${GOOGLE_OAUTH_CLIENT_SECRET:-}" ]]; then
  if [[ -z "${GOOGLE_OAUTH_CLIENT_ID:-}" || -z "${GOOGLE_OAUTH_CLIENT_SECRET:-}" ]]; then
    echo "Both Google OAuth client values must be provided together." >&2
    exit 1
  fi
fi

[[ -f "$APP_ICON" ]] || { echo "App icon not found: $APP_ICON" >&2; exit 1; }
[[ -f "$UPDATE_HELPER" ]] || { echo "Update helper not found: $UPDATE_HELPER" >&2; exit 1; }

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$APP_ICON" "$RESOURCES_DIR/AppIcon.icns"
cp "$UPDATE_HELPER" "$RESOURCES_DIR/install-update.sh"
chmod +x "$RESOURCES_DIR/install-update.sh"

cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_IDENTIFIER</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -n "${GOOGLE_OAUTH_CLIENT_ID:-}" ]]; then
  /usr/bin/plutil -insert GoogleOAuthClientID -string "$GOOGLE_OAUTH_CLIENT_ID" "$INFO_PLIST"
  /usr/bin/plutil -insert GoogleOAuthClientSecret -string "$GOOGLE_OAUTH_CLIENT_SECRET" "$INFO_PLIST"
fi

CODESIGN_ARGS=(--force --deep --options runtime --sign "$CODESIGN_IDENTITY")
if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
  CODESIGN_ARGS+=(--timestamp)
fi
/usr/bin/codesign "${CODESIGN_ARGS[@]}" "$APP_DIR" >/dev/null

echo "Built $APP_DIR"
