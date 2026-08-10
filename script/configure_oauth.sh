#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env.local"
TEMP_FILE="$ROOT_DIR/.env.local.$(uuidgen)"

cleanup() {
  if [[ -f "$TEMP_FILE" ]]; then
    rm -f "$TEMP_FILE"
  fi
}
trap cleanup EXIT

CLIENT_ID="$(/usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
  activate
  display dialog "Google Desktop OAuth Client ID" default answer "" buttons {"Cancel", "Continue"} default button "Continue" cancel button "Cancel" with title "Analytics Bar Setup"
  return text returned of result
end tell
APPLESCRIPT
)"

CLIENT_SECRET="$(/usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
  activate
  display dialog "Google Desktop OAuth Client Secret" default answer "" buttons {"Cancel", "Save"} default button "Save" cancel button "Cancel" with title "Analytics Bar Setup" with hidden answer
  return text returned of result
end tell
APPLESCRIPT
)"

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
  echo "OAuth configuration was not saved." >&2
  exit 1
fi

umask 077
{
  printf 'GOOGLE_OAUTH_CLIENT_ID=%q\n' "$CLIENT_ID"
  printf 'GOOGLE_OAUTH_CLIENT_SECRET=%q\n' "$CLIENT_SECRET"
} >"$TEMP_FILE"
chmod 600 "$TEMP_FILE"
mv "$TEMP_FILE" "$ENV_FILE"

unset CLIENT_ID CLIENT_SECRET
echo "Analytics Bar OAuth configuration saved locally."
