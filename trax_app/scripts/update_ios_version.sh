#!/usr/bin/env bash
# Publish the iOS "latest version" manifest to the OTA server.
#
# iOS does not get OTA APK delivery — TestFlight handles installs. We only
# need to publish a small JSON file the running app polls so the avatar
# can show a red dot and the version tile can prompt the user to open
# TestFlight.
#
# Run this AFTER you've finished uploading a new IPA to App Store Connect
# (and the build has been processed / made available in TestFlight).
#
# JSON schema MUST stay in sync with
# `lib/common/services/app_update_service.dart` (AppReleaseInfo.fromJson):
#   { "latest", "filename", "url", "sha1", "size_mb", "released_at" }
# For iOS, `filename`/`url`/`sha1`/`size_mb` are placeholders (the app
# never downloads from them) but kept so the JSON shape matches Android.
#
# Usage:
#   ./scripts/update_ios_version.sh                  # auto-detect latest local IPA
#   ./scripts/update_ios_version.sh 260514-07        # explicit code
#   ./scripts/update_ios_version.sh 260514-07 "Bug fixes and faster GPS"
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source ~/trax-deploy.env

CODE="${1:-}"
NOTES="${2:-}"

if [[ -z "$CODE" ]]; then
  # Auto: pick the highest-numbered IPA in build/dist/ matching trax-test-YYMMDD-NN.ipa
  LATEST_IPA=$(ls -1 "$APP_ROOT"/build/dist/trax-test-*-??.ipa 2>/dev/null \
    | sort | tail -1)
  if [[ -z "$LATEST_IPA" ]]; then
    echo "!! No IPA found and no code argument given."
    echo "   Usage: $0 <YYMMDD-NN> [release notes]"
    exit 1
  fi
  CODE=$(basename "$LATEST_IPA" | sed -E 's/^trax-test-([0-9]{6}-[0-9]{2})\.ipa$/\1/')
  echo "==> auto-detected from $(basename "$LATEST_IPA"): $CODE"
fi

if ! [[ "$CODE" =~ ^[0-9]{6}-[0-9]{2}$ ]]; then
  echo "!! invalid code '$CODE' (expected YYMMDD-NN, e.g. 260514-07)"
  exit 1
fi

RELEASED_AT="$(TZ=Asia/Shanghai date -Iseconds)"
FILENAME="trax-test-${CODE}.ipa"

# Build JSON locally so we can inspect it before pushing.
TMP=$(mktemp)
cat > "$TMP" <<JSON
{
  "latest": "$CODE",
  "filename": "$FILENAME",
  "url": "testflight://",
  "sha1": "",
  "size_mb": 0,
  "released_at": "$RELEASED_AT",
  "notes": "$NOTES",
  "channel": "testflight"
}
JSON

echo "==> Publishing version-ios.json:"
cat "$TMP"
echo

scp "$TMP" "${SSH_USER}@${SERVER_IP}:/tmp/version-ios.json"
ssh "${SSH_USER}@${SERVER_IP}" "
set -e
sudo mv /tmp/version-ios.json /var/www/trax-download/version-ios.json
sudo chown nginx:nginx /var/www/trax-download/version-ios.json 2>/dev/null || true
ls -lh /var/www/trax-download/version-ios.json
"
rm -f "$TMP"

echo
echo "==> Done.  http://${SERVER_IP}/download/version-ios.json"
echo "    The iOS app will pick this up on next AppUpdateService.checkForUpdate()."
