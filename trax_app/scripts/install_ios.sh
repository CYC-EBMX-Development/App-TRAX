#!/usr/bin/env bash
# Dev-signed side-load to a physical iPhone with proper YYMMDDNN build number.
#
# Usage:
#   ./scripts/install_ios.sh                           # auto-pick first attached iOS device
#   ./scripts/install_ios.sh <DEVICE_UDID>             # target a specific device
#   ./scripts/install_ios.sh --device-id <DEVICE_UDID> # same, flutter-style
#   ./scripts/install_ios.sh --clean [...]             # force uninstall + reinstall (wipes app data)
#
# Notes:
# - Uses `flutter build ios --release` (dev signing) for the .app bundle.
# - Install strategy (in priority order):
#     1. `xcrun devicectl device install app` — overlay/upgrade install, preserves
#        app data (login state, SharedPreferences, SQLite, sandbox files). This is
#        the iOS-native "覆盖安装" path, behaves like an App Store update.
#     2. If overlay install fails (signing-team change, bundle-id change, version
#        downgrade, corrupted prior install, etc.) → automatically fall back to
#        `flutter install` which uninstalls first then reinstalls.
#     3. `--clean` skips step 1 and goes straight to uninstall+reinstall.
# - Bumps CFBundleVersion (--build-number) to YYMMDDNN, same scheme as APK
#   and TestFlight IPA, so we can correlate installs to release sequence.
# - Picks up API_BASE_URL / AMAP_KEY / AMAP_IOS_SDK_KEY / DEV_DEFAULT_EMAIL
#   from ~/trax-deploy.env (same source the other release scripts use).
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$APP_ROOT/scripts/release_naming.sh"

if [[ -f "$HOME/trax-deploy.env" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/trax-deploy.env"
fi

API_BASE_URL="${API_BASE_URL:-http://43.99.48.204/api}"
AMAP_KEY="${AMAP_KEY:-}"
AMAP_IOS_SDK_KEY="${AMAP_IOS_SDK_KEY:-}"
DEV_DEFAULT_EMAIL="${DEV_DEFAULT_EMAIL:-}"

# Parse args: --clean flag + --device-id / positional UDID
DEVICE_ID=""
CLEAN_INSTALL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      CLEAN_INSTALL=1
      shift
      ;;
    --device-id)
      DEVICE_ID="${2:-}"
      shift 2
      ;;
    -*)
      echo "Unknown flag: $1" >&2
      exit 2
      ;;
    *)
      DEVICE_ID="$1"
      shift
      ;;
  esac
done

# Compute YYMMDDNN build-number from shared release naming.
trax_release_resolve_base "$APP_ROOT"
DATE_STAMP="$TRAX_RELEASE_DATE_STAMP"
SEQ="$TRAX_RELEASE_SEQ_STR"
BUILD_NAME="1.0.0"
BUILD_NUMBER="${DATE_STAMP}${SEQ}"

echo "==> install_ios: build-name=$BUILD_NAME  build-number=$BUILD_NUMBER"
echo "    API_BASE_URL=$API_BASE_URL"
[[ -n "$DEVICE_ID" ]] && echo "    device=$DEVICE_ID"

cd "$APP_ROOT"
"$APP_ROOT/scripts/patch_amap_plugins.sh" >/dev/null 2>&1 || true

flutter build ios --release \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=AMAP_KEY="$AMAP_KEY" \
  --dart-define=AMAP_IOS_SDK_KEY="$AMAP_IOS_SDK_KEY" \
  --dart-define=DEV_DEFAULT_EMAIL="$DEV_DEFAULT_EMAIL" \
  --build-name="$BUILD_NAME" \
  --build-number="$BUILD_NUMBER"

APP_BUNDLE="$APP_ROOT/build/ios/iphoneos/Runner.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "ERROR: $APP_BUNDLE missing after build" >&2
  exit 1
fi

# Resolve device UDID — devicectl needs an explicit one. If user didn't pass one,
# pick the first attached physical iOS device that Flutter reports.
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(flutter devices --machine 2>/dev/null \
    | python3 -c 'import json,sys
for d in json.load(sys.stdin):
    if d.get("platformType")=="ios" and d.get("category")=="mobile" \
       and not d.get("emulator", False) and d.get("isSupported", True):
        print(d.get("id","")); break' 2>/dev/null || true)"
fi

# install_overlay: try iOS-native upgrade install (preserves app data).
# Returns 0 on success, non-zero on any failure (caller decides whether to fall
# back to uninstall+reinstall).
install_overlay() {
  if ! command -v xcrun >/dev/null 2>&1; then
    return 10
  fi
  if ! xcrun --find devicectl >/dev/null 2>&1; then
    return 11
  fi
  if [[ -z "$DEVICE_ID" ]]; then
    return 12
  fi
  echo "==> Overlay install (preserves app data) via devicectl → $DEVICE_ID"
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP_BUNDLE"
}

# install_clean: uninstall first then reinstall (wipes app data). This is the
# safe-but-destructive fallback path that always works.
install_clean() {
  echo "==> Clean install (uninstall + reinstall) via flutter install"
  if [[ -n "$DEVICE_ID" ]]; then
    flutter install --device-id "$DEVICE_ID"
  else
    flutter install
  fi
}

if [[ "$CLEAN_INSTALL" -eq 1 ]]; then
  install_clean
  MODE="clean"
else
  if install_overlay; then
    MODE="overlay"
  else
    rc=$?
    echo "==> Overlay install unavailable/failed (rc=$rc) — falling back to uninstall+reinstall"
    install_clean
    MODE="fallback-clean"
  fi
fi

echo "==> Installed build $BUILD_NUMBER ($MODE) to ${DEVICE_ID:-attached device}."
