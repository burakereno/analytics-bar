#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 7 ]]; then
  echo "usage: install-update.sh DMG TARGET BUNDLE_ID VERSION TEAM_ID EXECUTABLE SHA256" >&2
  exit 64
fi

DMG_PATH="$1"
TARGET_APP="$2"
BUNDLE_ID="$3"
EXPECTED_VERSION="$4"
TEAM_ID="$5"
EXECUTABLE_NAME="$6"
EXPECTED_HASH="$7"

if [[ "$(basename "$TARGET_APP")" != "Analytics Bar.app" ]]; then
  echo "unexpected target app name" >&2
  exit 65
fi

WORK_DIR="$(mktemp -d "${TMPDIR%/}/AnalyticsBarInstaller.XXXXXX")"
chmod 700 "$WORK_DIR"
MOUNT_DIR="$WORK_DIR/mount"
STAGED_APP="$(dirname "$TARGET_APP")/.Analytics Bar.staging.$(uuidgen).app"
BACKUP_APP="$(dirname "$TARGET_APP")/.Analytics Bar.backup.$(uuidgen).app"
DOWNLOAD_DIR="$(dirname "$DMG_PATH")"
PARENT_PID="$PPID"
MOUNTED=0
REPLACED=0
CONFIRMED=0

cleanup() {
  status="$?"
  if [[ "$status" -ne 0 && "$REPLACED" -eq 1 && -d "$BACKUP_APP" ]]; then
    restore_backup
  fi
  if [[ "$MOUNTED" -eq 1 ]]; then
    /usr/bin/hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  fi
  if [[ -d "$STAGED_APP" ]]; then
    rm -rf "$STAGED_APP"
  fi
  if [[ -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi
  case "$DOWNLOAD_DIR" in
    "${TMPDIR%/}"/AnalyticsBar-Update-*) rm -rf "$DOWNLOAD_DIR" ;;
  esac
}
trap cleanup EXIT

restore_backup() {
  if [[ -d "$TARGET_APP" ]]; then
    rm -rf "$TARGET_APP"
  fi
  mv "$BACKUP_APP" "$TARGET_APP"
  /usr/bin/open -n "$TARGET_APP" >/dev/null 2>&1 || true
}

ACTUAL_HASH="$(/usr/bin/shasum -a 256 "$DMG_PATH" | /usr/bin/awk '{print $1}')"
[[ "$ACTUAL_HASH" == "$EXPECTED_HASH" ]] || { echo "DMG checksum mismatch" >&2; exit 66; }

/usr/bin/codesign --verify --strict --verbose=2 "$DMG_PATH"
DMG_TEAM="$(/usr/bin/codesign -dv --verbose=4 "$DMG_PATH" 2>&1 | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
[[ "$DMG_TEAM" == "$TEAM_ID" ]] || { echo "DMG publisher mismatch" >&2; exit 67; }
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"

mkdir -p "$MOUNT_DIR"
/usr/bin/hdiutil attach -readonly "$DMG_PATH" -nobrowse -quiet -mountpoint "$MOUNT_DIR"
MOUNTED=1

SOURCE_APP="$MOUNT_DIR/Analytics Bar.app"
[[ -d "$SOURCE_APP" ]] || { echo "Analytics Bar.app is missing from DMG" >&2; exit 68; }

ACTUAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")"
[[ "$ACTUAL_BUNDLE_ID" == "$BUNDLE_ID" ]] || { echo "bundle identifier mismatch" >&2; exit 69; }
ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_APP/Contents/Info.plist")"
[[ "$ACTUAL_VERSION" == "$EXPECTED_VERSION" ]] || { echo "bundle version mismatch" >&2; exit 70; }
[[ -x "$SOURCE_APP/Contents/MacOS/$EXECUTABLE_NAME" ]] || { echo "expected executable is missing" >&2; exit 71; }

/usr/bin/codesign --verify --deep --strict --verbose=2 "$SOURCE_APP"
APP_TEAM="$(/usr/bin/codesign -dv --verbose=4 "$SOURCE_APP" 2>&1 | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
[[ "$APP_TEAM" == "$TEAM_ID" ]] || { echo "app publisher mismatch" >&2; exit 72; }
/usr/bin/codesign --verify --deep --strict --verbose=2 \
  -R="anchor apple generic and identifier \"$BUNDLE_ID\" and certificate leaf[subject.OU] = \"$TEAM_ID\"" \
  "$SOURCE_APP"
/usr/sbin/spctl --assess --type execute --verbose=4 "$SOURCE_APP"

/usr/bin/ditto "$SOURCE_APP" "$STAGED_APP"
[[ -d "$TARGET_APP" ]] || { echo "installed app is missing" >&2; exit 73; }
mv "$TARGET_APP" "$BACKUP_APP"
REPLACED=1
mv "$STAGED_APP" "$TARGET_APP"

OLD_APP_PIDS="$(/usr/bin/pgrep -x "$EXECUTABLE_NAME" || true)"
kill -TERM "$PARENT_PID" >/dev/null 2>&1 || true
/usr/bin/open -n "$TARGET_APP"

for _ in $(/usr/bin/seq 1 30); do
  NEW_PID=""
  while IFS= read -r CANDIDATE_PID; do
    [[ -n "$CANDIDATE_PID" && "$CANDIDATE_PID" != "$PARENT_PID" ]] || continue
    if printf '%s\n' "$OLD_APP_PIDS" | /usr/bin/grep -Fxq "$CANDIDATE_PID"; then
      continue
    fi
    RUNNING_PATH="$(/bin/ps -p "$CANDIDATE_PID" -o comm= 2>/dev/null || true)"
    if [[ "$RUNNING_PATH" == "$TARGET_APP/Contents/MacOS/$EXECUTABLE_NAME" ]]; then
      NEW_PID="$CANDIDATE_PID"
      break
    fi
  done < <(/usr/bin/pgrep -x "$EXECUTABLE_NAME" || true)
  if [[ -n "$NEW_PID" ]]; then
    CONFIRMED=1
    break
  fi
  /bin/sleep 0.5
done

[[ "$CONFIRMED" -eq 1 ]] || { echo "updated app did not relaunch" >&2; exit 74; }
REPLACED=0
rm -rf "$BACKUP_APP"
echo "Analytics Bar $EXPECTED_VERSION installed successfully"
