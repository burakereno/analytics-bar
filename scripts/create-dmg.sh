#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/.build/Analytics Bar.app}"
APP_BUNDLE_NAME="$(basename "$APP_PATH")"
APP_DISPLAY_NAME="${APP_BUNDLE_NAME%.app}"
OUTPUT_DMG="${2:-$ROOT_DIR/AnalyticsBar.dmg}"

# Analytics Bar DMG identity and layout.
VOLUME_NAME="${VOLUME_NAME:-Analytics Bar}"
DMG_TITLE="${DMG_TITLE:-Analytics Bar, built for}"
DMG_SUBTITLE="${DMG_SUBTITLE:-your GA4 at a glance}"
DMG_HINT="${DMG_HINT:-Drag Analytics Bar to Applications}"

WINDOW_WIDTH="${WINDOW_WIDTH:-760}"
WINDOW_HEIGHT="${WINDOW_HEIGHT:-610}"
BACKGROUND_WIDTH="${BACKGROUND_WIDTH:-$WINDOW_WIDTH}"
BACKGROUND_HEIGHT="${BACKGROUND_HEIGHT:-$WINDOW_HEIGHT}"
ICON_SIZE="${ICON_SIZE:-128}"
APP_X="${APP_X:-245}"
APP_Y="${APP_Y:-300}"
APPLICATIONS_X="${APPLICATIONS_X:-515}"
APPLICATIONS_Y="${APPLICATIONS_Y:-300}"

TITLE_Y="${TITLE_Y:-452}"
SUBTITLE_Y="${SUBTITLE_Y:-411}"
HINT_Y="${HINT_Y:-154}"
LABEL_CAPSULE_Y="${LABEL_CAPSULE_Y:-202}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ "$WINDOW_WIDTH" != "$BACKGROUND_WIDTH" || "$WINDOW_HEIGHT" != "$BACKGROUND_HEIGHT" ]]; then
  echo "Finder window and background dimensions must match." >&2
  exit 2
fi

WORK_DIR="$(mktemp -d)"
STAGING_DIR="$WORK_DIR/staging"
BACKGROUND_DIR="$STAGING_DIR/.background"
BACKGROUND_PATH="$BACKGROUND_DIR/background.png"
RW_DMG="$WORK_DIR/$VOLUME_NAME.rw.dmg"
MOUNT_DIR="$WORK_DIR/mount"
BACKGROUND_SCRIPT="$WORK_DIR/make-dmg-background.swift"
MOUNTED=0

cleanup() {
  if [[ "$MOUNTED" == "1" ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet -force >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$BACKGROUND_DIR" "$MOUNT_DIR" "$(dirname "$OUTPUT_DMG")"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

cat > "$BACKGROUND_SCRIPT" <<'SWIFT'
import AppKit
import Foundation

let args = CommandLine.arguments
let outputPath = args[1]
let width = CGFloat(Double(args[2]) ?? 760)
let height = CGFloat(Double(args[3]) ?? 610)
let title = args[4]
let subtitle = args[5]
let hint = args[6]
let titleY = CGFloat(Double(args[7]) ?? 452)
let subtitleY = CGFloat(Double(args[8]) ?? 411)
let hintY = CGFloat(Double(args[9]) ?? 154)
let appX = CGFloat(Double(args[10]) ?? 245)
let applicationsX = CGFloat(Double(args[11]) ?? 515)
let labelCapsuleY = CGFloat(Double(args[12]) ?? 202)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

let canvas = NSRect(x: 0, y: 0, width: width, height: height)
let backgroundGradient = NSGradient(colors: [
    color(29, 29, 31),
    color(15, 15, 16)
])!
backgroundGradient.draw(in: canvas, angle: -90)

let glowCenter = NSPoint(x: width / 2, y: height * 0.82)
let orangeGlow = NSGradient(colors: [
    color(255, 139, 43, 0.24),
    color(255, 139, 43, 0)
])!
orangeGlow.draw(
    fromCenter: glowCenter,
    radius: 0,
    toCenter: glowCenter,
    radius: 330,
    options: [.drawsAfterEndingLocation]
)

let panelRect = NSRect(x: 72, y: 118, width: width - 144, height: 400)
let panel = NSBezierPath(roundedRect: panelRect, xRadius: 28, yRadius: 28)
color(5, 5, 6, 0.34).setFill()
panel.fill()
color(255, 255, 255, 0.09).setStroke()
panel.lineWidth = 1
panel.stroke()

for (centerX, capsuleWidth) in [(appX, CGFloat(126)), (applicationsX, CGFloat(146))] {
    let capsuleRect = NSRect(
        x: centerX - capsuleWidth / 2,
        y: labelCapsuleY,
        width: capsuleWidth,
        height: 29
    )
    let capsule = NSBezierPath(roundedRect: capsuleRect, xRadius: 9, yRadius: 9)
    color(244, 244, 246, 0.92).setFill()
    capsule.fill()
}

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 31, weight: .bold),
    .foregroundColor: color(242, 242, 243),
    .paragraphStyle: paragraph
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 29, weight: .semibold),
    .foregroundColor: color(255, 139, 43),
    .paragraphStyle: paragraph
]
let hintAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
    .foregroundColor: color(210, 210, 214),
    .paragraphStyle: paragraph
]

title.draw(in: NSRect(x: 0, y: titleY, width: width, height: 42), withAttributes: titleAttributes)
subtitle.draw(
    in: NSRect(x: 0, y: subtitleY, width: width, height: 42),
    withAttributes: subtitleAttributes
)
hint.draw(in: NSRect(x: 0, y: hintY, width: width, height: 24), withAttributes: hintAttributes)

let arrowY = height - 300
let arrow = NSBezierPath()
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 350, y: arrowY))
arrow.line(to: NSPoint(x: 410, y: arrowY))
arrow.move(to: NSPoint(x: 398, y: arrowY + 10))
arrow.line(to: NSPoint(x: 410, y: arrowY))
arrow.line(to: NSPoint(x: 398, y: arrowY - 10))
color(255, 139, 43, 0.82).setStroke()
arrow.stroke()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Could not render DMG background\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
SWIFT

xcrun swift "$BACKGROUND_SCRIPT" \
  "$BACKGROUND_PATH" \
  "$BACKGROUND_WIDTH" \
  "$BACKGROUND_HEIGHT" \
  "$DMG_TITLE" \
  "$DMG_SUBTITLE" \
  "$DMG_HINT" \
  "$TITLE_Y" \
  "$SUBTITLE_Y" \
  "$HINT_Y" \
  "$APP_X" \
  "$APPLICATIONS_X" \
  "$LABEL_CAPSULE_Y"

rm -f "$OUTPUT_DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -format UDRW \
  -fs HFS+ \
  -ov \
  "$RW_DMG" >/dev/null

hdiutil attach "$RW_DMG" \
  -readwrite \
  -noverify \
  -noautoopen \
  -mountpoint "$MOUNT_DIR" >/dev/null
MOUNTED=1

/usr/bin/SetFile -a V "$MOUNT_DIR/.background" >/dev/null 2>&1 || true
/usr/bin/SetFile -a V "$MOUNT_DIR/Applications" >/dev/null 2>&1 || true

osascript <<APPLESCRIPT
tell application "Finder"
  set dmgFolder to POSIX file "$MOUNT_DIR" as alias
  open dmgFolder
  delay 1
  set current view of container window of dmgFolder to icon view
  set toolbar visible of container window of dmgFolder to false
  set statusbar visible of container window of dmgFolder to false
  set pathbar visible of container window of dmgFolder to false
  set bounds of container window of dmgFolder to {100, 100, 100 + $WINDOW_WIDTH, 100 + $WINDOW_HEIGHT}
  set theViewOptions to the icon view options of container window of dmgFolder
  set arrangement of theViewOptions to not arranged
  set icon size of theViewOptions to $ICON_SIZE
  set text size of theViewOptions to 13
  set label position of theViewOptions to bottom
  set background picture of theViewOptions to file ".background:background.png" of dmgFolder
  set position of item "$APP_BUNDLE_NAME" of dmgFolder to {$APP_X, $APP_Y}
  set position of item "Applications" of dmgFolder to {$APPLICATIONS_X, $APPLICATIONS_Y}
  update dmgFolder without registering applications
  delay 1
  close container window of dmgFolder
  delay 2
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" -quiet -force >/dev/null
MOUNTED=0

hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$OUTPUT_DMG" >/dev/null

echo "Created $OUTPUT_DMG"
